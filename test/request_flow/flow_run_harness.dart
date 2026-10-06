// A paged, flaky, slow fake API that the collection runner, the editor and the command line can all talk to, and the
// two ways of running a collection built over the same database, so a scenario can be run through both.
import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/cli/workspace_runner.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_auth_repository.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_run_options.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/request_flow/data/app_flow_environment.dart';
import 'package:postpilot/features/request_flow/domain/services/flow_executor.dart';
import 'package:postpilot/features/request_flow/domain/usecases/request_flow_service.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import '../support/drift_repos.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/shop_seed.dart';
import 'flow_support.dart';

/// What the fake API answers: status, body (text) and headers.
typedef ServerReply = ({int status, String body, Map<String, String> headers});

/// A reply with a JSON body.
ServerReply reply(Object? json, {int status = 200, Map<String, String> headers = const {}}) =>
    (status: status, body: jsonEncode(json), headers: headers);

/// A server: [answer] is told the request (URL, method, which call this is for that path) and says what comes back.
/// It can throw a [NetworkException] to be unreachable. Both the app's [ApiClient] and the CLI's send function talk
/// to it, and it remembers everything it was asked.
final class FakeApiServer {
  final FutureOr<ServerReply> Function(Uri url, String method, int callOfPath) answer;

  /// `GET https://api.test/jobs?page=2`, in the order received.
  final List<String> requests = [];
  final Map<String, int> _calls = {};

  /// Runs while a request is "in flight", for a test that needs to act mid-run.
  void Function(Uri url)? onRequest;

  FakeApiServer(this.answer);

  Future<ServerReply> _handle(String method, String url) async {
    final uri = Uri.parse(url);
    requests.add('$method $url');
    onRequest?.call(uri);
    final key = '$method ${uri.path}';
    final call = _calls[key] = (_calls[key] ?? 0) + 1;
    return answer(uri, method, call);
  }

  ApiClient get client => _AppClient(this);

  Future<CliResponse> cliSend(CliRequest request) async {
    final r = await _handle(request.method, request.url);
    return CliResponse(
      statusCode: r.status,
      statusMessage: r.status == 200 ? 'OK' : (r.status >= 500 ? 'Server Error' : ''),
      headers: r.headers,
      bodyBytes: utf8.encode(r.body),
      duration: const Duration(milliseconds: 5),
    );
  }

  /// The paths hit, in order (`/jobs`), for a short assertion.
  List<String> get paths => [for (final r in requests) Uri.parse(r.substring(r.indexOf(' ') + 1)).path];
}

final class _AppClient implements ApiClient {
  final FakeApiServer server;
  _AppClient(this.server);

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    final r = await server._handle(spec.method, spec.url);
    return ApiHttpResponse(
      statusCode: r.status,
      statusMessage: r.status == 200 ? 'OK' : (r.status >= 500 ? 'Server Error' : ''),
      headers: r.headers,
      bodyBytes: utf8.encode(r.body),
      duration: const Duration(milliseconds: 5),
    );
  }
}

/// The server is down.
Never unreachable() => throw const NetworkException('connect failed', kind: NetworkErrorKind.connectionError, summary: "Couldn't reach api.test");

final class _NoHistory implements HistoryRepository {
  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _NoAuth implements CollectionAuthRepository {
  @override
  Future<String?> getAuthJson(int collectionId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

/// One collection in a real (in-memory) database, run by the app's runner and, through a snapshot, by the CLI's.
final class FlowHarness {
  final AppDatabase db;
  final DriftRepos repos;
  final FakeFlowClock clock;
  final FakeApiServer server;
  final int collectionId;

  /// The console lines the flow wrote (`attempt 2/3 after 1.2 s`).
  final List<String> consoleNotes = [];
  late final BuildVariableResolverUseCase resolver;
  late final SendRequestUseCase send;
  late final RequestFlowService flow;
  late final CollectionRunnerService runner;

  FlowHarness._(this.db, this.repos, this.clock, this.server, this.collectionId);

  static Future<FlowHarness> create(FakeApiServer server, {String? environment = 'Dev'}) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repos = DriftRepos(db);
    final collectionId = await repos.collectionRepository.createCollection('Jobs');
    final harness = FlowHarness._(db, repos, FakeFlowClock(), server, collectionId);
    if (environment != null) await harness.useEnvironment(environment);
    harness._wire();
    return harness;
  }

  void _wire() {
    resolver = BuildVariableResolverUseCase(
      repos.collectionVariableRepository,
      repos.environmentRepository,
      repos.globalVariableRepository,
      repos.defaultsRepository,
    );
    send = SendRequestUseCase(server.client, resolver, _NoHistory(), _NoAuth(), null, repos.requestSettingsRepository);
    flow = RequestFlowService(
      repos.requestSettingsRepository,
      send,
      AppFlowEnvironment(resolver, repos.environmentRepository),
      executor: FlowExecutor(clock: clock, random: () => 1),
      onNote: consoleNotes.add,
    );
    final scripts = RunRequestScriptsUseCase(repos.scriptsRepository, resolver, repos.environmentRepository, repos.globalVariableRepository);
    runner = CollectionRunnerService.withFlow(repos.requestRepository, send, scripts, repos.collectionRepository, flow, (_) async {});
  }

  Future<void> useEnvironment(String name) async {
    final id = await repos.environmentRepository.create(name);
    await repos.environmentRepository.setActive(id);
  }

  /// Adds a request to the collection, in order, with the settings and tests given.
  Future<int> add(
    String name, {
    RequestSettings settings = RequestSettings.none,
    HttpMethod method = HttpMethod.get,
    String? url,
    List<KeyValueItem> query = const [],
    RequestBody body = RequestBody.empty,
    String? assertionsJson,
    String? extractorsJson,
    int? folderId,
  }) async {
    final id = await addRequest(
      repos,
      collectionId,
      name,
      folderId: folderId,
      method: method,
      url: url ?? 'https://api.test/${name.replaceAll(' ', '-')}',
      query: query,
      body: body,
    );
    if (!settings.isEmpty) await repos.requestSettingsRepository.save(id, settings);
    if (assertionsJson != null || extractorsJson != null) {
      await repos.scriptsRepository.save(
        RequestScriptsEntity(requestId: id, assertionsJson: assertionsJson ?? '[]', extractorsJson: extractorsJson ?? '[]'),
      );
    }
    return id;
  }

  /// A run through the app's runner: every result in order.
  Future<List<CollectionRunResult>> runApp({
    CollectionRunOptions options = const CollectionRunOptions(),
    ApiCancelToken? cancelToken,
  }) =>
      runner.run(collectionId, options: options, cancelToken: cancelToken).toList();

  /// The same collection, as a workspace file, run by the CLI's runner against the same server.
  Future<WorkspaceRunner> cliRunner() async {
    final snapshot = await repos.backupService.snapshot();
    return WorkspaceRunner.parse(
      BackupCodec.encode(snapshot),
      server.cliSend,
      flowExecutor: FlowExecutor(clock: clock, random: () => 1),
    );
  }

  Future<void> dispose() => db.close();
}

/// A one-line summary of what happened to each request, the same shape for the app and the CLI, so a scenario can be
/// run through both and the two compared: `name:state` with `state` one of passed, failed, skipped.
String stateOfApp(CollectionRunResult r) => '${r.request.name}:${r.isSkipped ? 'skipped' : (r.passed ? 'passed' : 'failed')}';

String stateOfCli(RequestOutcome o) => '${o.name}:${o.skipped != null ? 'skipped' : (o.passed ? 'passed' : 'failed')}';
