// The app's real services over an in-memory database and a scripted server that remembers every call it got, with the
// cleanup ledger hooked into the flow service the way the injector does it.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/auth_renewal/domain/services/relogin_policy.dart';
import 'package:postpilot/features/cleanup_ledger/data/app_cleanup_sender.dart';
import 'package:postpilot/features/cleanup_ledger/domain/entities/cleanup_settings.dart';
import 'package:postpilot/features/cleanup_ledger/presentation/view_models/cleanup_ledger.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_auth_repository.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/request_flow/data/app_flow_environment.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/usecases/request_flow_service.dart';
import 'package:postpilot/features/safety/data/safety_prefs.dart';
import 'package:postpilot/features/safety/domain/services/production_guard.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import '../support/drift_repos.dart';
import '../support/shop_seed.dart';

/// One call the server received.
final class SentCall {
  final String method;
  final String url;
  final Map<String, String> headers;
  final String body;

  const SentCall(this.method, this.url, this.headers, this.body);

  /// `POST https://api.test/partners`.
  String get line => '$method $url';

  Object? get json => body.isEmpty ? null : jsonDecode(body);

  @override
  String toString() => line;
}

/// What the scripted server answers.
typedef Answer = ({int status, Object? json});

Answer ok(Object? json, {int status = 200}) => (status: status, json: json);

final class _History implements HistoryRepository {
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

final class _Server implements ApiClient {
  final CleanupHarness harness;
  _Server(this.harness);

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    final body = spec.body is List<int> ? utf8.decode(spec.body as List<int>) : '';
    final call = SentCall(spec.method, spec.url, spec.headers, body);
    harness.calls.add(call);
    final answer = harness.server(call);
    return ApiHttpResponse(
      statusCode: answer.status,
      statusMessage: answer.status == 200 ? 'OK' : '',
      headers: const {'content-type': 'application/json'},
      bodyBytes: utf8.encode(jsonEncode(answer.json)),
      duration: const Duration(milliseconds: 5),
    );
  }
}

final class CleanupHarness {
  final AppDatabase db;
  final DriftRepos repos;
  final int collectionId;

  /// Every call the server got, in order.
  final List<SentCall> calls = [];
  Answer Function(SentCall call) server;

  late final BuildVariableResolverUseCase resolver;
  late final SendRequestUseCase send;
  late final RequestFlowService flow;
  late final AppCleanupSender sender;
  late final CleanupLedger ledger;
  late final CollectionRunnerService runner;
  late final ProductionGuard guard;

  CleanupHarness._(this.db, this.repos, this.collectionId, this.server);

  static Future<CleanupHarness> create({
    String? environment = 'Staging',
    Map<String, String> variables = const {'baseUrl': 'https://api.test', 'odooUrl': 'https://odoo.test'},
    Answer Function(SentCall call)? server,
  }) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repos = DriftRepos(db);
    final collectionId = await repos.collectionRepository.createCollection('Shop');
    final harness = CleanupHarness._(db, repos, collectionId, server ?? (_) => ok({}));
    if (environment != null) await harness.useEnvironment(environment, variables);
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
    send = SendRequestUseCase(_Server(this), resolver, _History(), _NoAuth(), null, repos.requestSettingsRepository);
    sender = AppCleanupSender(
      environmentName: () async => (await repos.environmentRepository.watchActive().first)?.name,
      candidates: (collectionId) async => [
        for (final s in await repos.requestRepository.watchByCollection(collectionId).first)
          ReloginCandidate(folderPath: '', name: s.name, method: s.method, value: s),
      ],
      findRequest: repos.requestRepository.findById,
      send: (request, variables) async {
        final outcome = await flow.send(request, dataVariables: variables);
        if (outcome.error != null) throw outcome.error!;
        return outcome.response!;
      },
    );
    ledger = CleanupLedger(sender);
    flow = RequestFlowService(
      repos.requestSettingsRepository,
      send,
      AppFlowEnvironment(resolver, repos.environmentRepository),
      onSent: ledger.recordSend,
    );
    final scripts = RunRequestScriptsUseCase(repos.scriptsRepository, resolver, repos.environmentRepository, repos.globalVariableRepository);
    runner = CollectionRunnerService.withFlow(repos.requestRepository, send, scripts, repos.collectionRepository, flow, (_) async {});
    guard = ProductionGuard(repos.environmentRepository, SafetyPrefs());
  }

  Future<int> useEnvironment(String name, [Map<String, String> variables = const {'baseUrl': 'https://api.test', 'odooUrl': 'https://odoo.test'}]) async {
    final id = await repos.environmentRepository.create(name);
    for (final e in variables.entries) {
      await repos.environmentRepository.upsertVariable(
        EnvironmentVariableEntity(id: 0, environmentId: id, key: e.key, value: e.value, isSecret: false, enabled: true),
      );
    }
    await repos.environmentRepository.setActive(id);
    return id;
  }

  static const cleanupOn = RequestSettings(flow: FlowSettings(cleanup: CleanupSettings(enabled: true)));

  /// Adds a request to the collection, with cleanup switched on unless [settings] says otherwise.
  Future<ApiRequestEntity> add(
    String name, {
    HttpMethod method = HttpMethod.post,
    String url = '{{baseUrl}}/partners',
    RequestBody body = const RequestBody(type: BodyType.raw, rawText: '{"name": "Ann"}'),
    RequestSettings settings = cleanupOn,
  }) async {
    final id = await addRequest(repos, collectionId, name, method: method, url: url, body: body);
    if (!settings.isEmpty) await repos.requestSettingsRepository.save(id, settings);
    return (await repos.requestRepository.findById(id))!;
  }

  /// The calls the server got, as `METHOD url`.
  List<String> get lines => [for (final c in calls) c.line];

  Future<void> dispose() => db.close();
}
