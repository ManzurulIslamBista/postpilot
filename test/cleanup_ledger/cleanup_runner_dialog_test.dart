// The collection runner dialog for real, over the app's own runner and flow service and a scripted server: a run that creates
// records ends with the panel that offers to delete them, "Auto clean up after the run" does it by itself, and a run that
// created nothing looks as it always did. The whole path is exercised: the ledger fed by the run, the panel read from it, the
// deletes sent back through the same send. (Repositories are in-memory fakes: a real database cannot be awaited in a widget test.)
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/auth_renewal/domain/services/relogin_policy.dart';
import 'package:postpilot/features/cleanup_ledger/data/app_cleanup_sender.dart';
import 'package:postpilot/features/cleanup_ledger/domain/entities/cleanup_entry.dart';
import 'package:postpilot/features/cleanup_ledger/domain/entities/cleanup_settings.dart';
import 'package:postpilot/features/cleanup_ledger/presentation/view_models/cleanup_ledger.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_auth_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_variable_repository.dart';
import 'package:postpilot/features/collections/presentation/view_models/collection_runner_view_model.dart';
import 'package:postpilot/features/collections/presentation/widgets/collection_runner_dialog.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/global_variable_repository.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_scripts_repository.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_run_report.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/services/run_data_parser.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/services/flow_environment.dart';
import 'package:postpilot/features/request_flow/domain/usecases/request_flow_service.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'package:postpilot/features/settings/domain/repositories/request_settings_repository.dart';

const _collectionId = 1;
const _cleanupOn = RequestSettings(flow: FlowSettings(cleanup: CleanupSettings(enabled: true)));

ApiRequestEntity _request(int id, String name, String path, {HttpMethod method = HttpMethod.post}) => ApiRequestEntity(
      id: id,
      collectionId: _collectionId,
      folderId: null,
      name: name,
      method: method,
      url: 'https://api.test$path',
      headers: const [],
      queryParams: const [],
      body: method == HttpMethod.post ? const RequestBody(type: BodyType.raw, rawText: '{"name": "Ann"}') : RequestBody.empty,
      auth: const RequestAuth(type: AuthType.none),
    );

/// Creates partners (`POST /partners` answers with the next id from 101) and deletes them; remembers every call.
final class _Server implements ApiClient {
  final calls = <String>[];
  var _next = 100;

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    calls.add('${spec.method} ${spec.url}');
    final created = spec.method == 'POST' && spec.url.endsWith('/partners');
    return ApiHttpResponse(
      statusCode: 200,
      statusMessage: 'OK',
      headers: const {},
      bodyBytes: utf8.encode(jsonEncode(created ? {'id': ++_next, 'name': 'Ann'} : {'deleted': true})),
      duration: const Duration(milliseconds: 5),
    );
  }
}

final class _Requests implements RequestRepository {
  final List<ApiRequestEntity> requests;
  _Requests(this.requests);

  @override
  Stream<List<RequestSummaryEntity>> watchByCollection(int collectionId) => Stream.value([
        for (final r in requests) RequestSummaryEntity(id: r.id, folderId: r.folderId, name: r.name, method: r.method, orderIndex: r.id),
      ]);

  @override
  Future<ApiRequestEntity?> findById(int id) async => requests.where((r) => r.id == id).firstOrNull;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _Collections implements CollectionRepository {
  @override
  Stream<List<CollectionEntity>> watchCollections() => Stream.value(const [CollectionEntity(id: _collectionId, name: 'Shop')]);

  @override
  Stream<List<FolderEntity>> watchFolders(int collectionId) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _Environments implements EnvironmentRepository {
  @override
  Future<Map<String, String>> getActiveVariables() async => const {};

  @override
  Stream<EnvironmentEntity?> watchActive() => Stream.value(const EnvironmentEntity(id: 1, name: 'Staging', isActive: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _FlowEnvironment implements FlowEnvironment {
  @override
  Future<VariableResolver> resolver({required int collectionId, int? folderId, Map<String, String> dataVariables = const {}}) async =>
      VariableResolver(dataVariables);

  @override
  Future<String?> environmentName() async => 'Staging';
}

/// The cleanup switched on for the requests that create.
final class _Settings implements RequestSettingsRepository {
  final Set<int> creating;
  _Settings(this.creating);

  @override
  Future<RequestSettings> get(int requestId) async => creating.contains(requestId) ? _cleanupOn : RequestSettings.none;

  @override
  Stream<RequestSettings> watch(int requestId) => Stream.value(RequestSettings.none);

  @override
  Future<void> save(int requestId, RequestSettings settings) async {}

  @override
  Future<void> delete(int requestId) async {}
}

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
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoAuth implements CollectionAuthRepository {
  @override
  Future<String?> getAuthJson(int collectionId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoVariables implements CollectionVariableRepository {
  @override
  Future<Map<String, String>> getEnabledMap(int collectionId) async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Globals implements GlobalVariableRepository {
  @override
  Future<Map<String, String>> getEnabledMap() async => const {};

  @override
  Stream<List<GlobalVariableEntity>> watchAll() => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoScripts implements RequestScriptsRepository {
  @override
  Future<RequestScriptsEntity?> get(int requestId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _Server server;
  late CleanupLedger ledger;

  tearDown(() => locator.reset());

  Future<void> open(WidgetTester tester, {required Size size, bool dark = false, int creates = 3}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    server = _Server();
    final requests = _Requests([
      for (var i = 1; i <= creates; i++) _request(i, 'Create $i', '/partners'),
      _request(50, 'List partners', '/partners', method: HttpMethod.get),
    ]);
    final settings = _Settings({for (var i = 1; i <= creates; i++) i});
    final resolver = BuildVariableResolverUseCase(_NoVariables(), _Environments(), _Globals());
    final send = SendRequestUseCase(server, resolver, _NoHistory(), _NoAuth());
    final scripts = RunRequestScriptsUseCase(_NoScripts(), resolver, _Environments(), _Globals());
    late final RequestFlowService flow;
    ledger = CleanupLedger(
      AppCleanupSender(
        environmentName: () async => 'Staging',
        candidates: (collectionId) async => [
          for (final s in await requests.watchByCollection(collectionId).first)
            ReloginCandidate(folderPath: '', name: s.name, method: s.method, value: s),
        ],
        findRequest: requests.findById,
        send: (request, variables) async => (await flow.send(request, dataVariables: variables)).response!,
      ),
    );
    flow = RequestFlowService(settings, send, _FlowEnvironment(), onSent: ledger.recordSend);
    final runner = CollectionRunnerService.withFlow(requests, send, scripts, _Collections(), flow, (_) async {});
    final vm = CollectionRunnerViewModel(
      runner,
      const RunDataParser(),
      const CollectionRunExporter(),
      ({required String fileName, required Uint8List bytes, required String mimeType}) async => null,
    );
    locator
      ..registerFactory<CollectionRunnerViewModel>(() => vm)
      ..registerSingleton<CollectionRepository>(_Collections())
      ..registerSingleton<EnvironmentRepository>(_Environments())
      ..registerSingleton<RequestRepository>(requests)
      ..registerSingleton<CleanupLedger>(ledger);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(child: TextButton(onPressed: () => CollectionRunnerDialog.show(context, collectionId: _collectionId), child: const Text('open'))),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> run(WidgetTester tester) async {
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
  }

  List<String> deletes() => server.calls.where((l) => l.startsWith('DELETE')).toList();

  for (final dark in [false, true]) {
    for (final size in const [Size(1200, 900), Size(420, 800)]) {
      final label = '${dark ? 'dark' : 'light'} ${size.width.toInt()}px';

      testWidgets('a run that created records ends with the panel, without overflowing ($label)', (tester) async {
        await open(tester, size: size, dark: dark);
        expect(find.text('Auto clean up after the run'), findsOneWidget, reason: 'the one tick the setup gets');
        expect(find.byKey(const ValueKey('run-cleanup-panel')), findsNothing, reason: 'nothing to show before a run');

        await run(tester);

        expect(find.text('3 records were created by this run'), findsOneWidget);
        expect(find.text('Delete them'), findsOneWidget);
        expect(find.text('Keep'), findsOneWidget);
        expect(ledger.entries, hasLength(3));
        expect(deletes(), isEmpty, reason: 'nothing is deleted until the person says so');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Delete them deletes what the run created, newest first, through the normal send, and the panel says so', (tester) async {
    await open(tester, size: const Size(1200, 900));
    await run(tester);

    await tester.tap(find.byKey(const ValueKey('run-cleanup-delete')));
    await tester.pumpAndSettle();

    expect(deletes(), [
      'DELETE https://api.test/partners/103',
      'DELETE https://api.test/partners/102',
      'DELETE https://api.test/partners/101',
    ]);
    expect(find.text('3 records were created by this run, and deleted'), findsOneWidget);
    expect(ledger.entries.map((e) => e.state), everyElement(CleanupState.deleted));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Keep leaves the records alone and in the ledger', (tester) async {
    await open(tester, size: const Size(1200, 900));
    await run(tester);

    await tester.tap(find.byKey(const ValueKey('run-cleanup-keep')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('run-cleanup-panel')), findsNothing);
    expect(deletes(), isEmpty);
    expect(ledger.deletableCount, 3);
  });

  testWidgets('"Auto clean up after the run" deletes by itself as soon as the run is done', (tester) async {
    await open(tester, size: const Size(1200, 900));
    await tester.tap(find.byKey(const ValueKey('auto-cleanup')));
    await tester.pump();
    expect(ledger.autoCleanup, isTrue);

    await run(tester);

    expect(deletes(), hasLength(3));
    expect(find.text('3 records were created by this run, and deleted'), findsOneWidget);
    expect(ledger.deletableCount, 0);
  });

  testWidgets('a run again offers only the records of that run', (tester) async {
    await open(tester, size: const Size(1200, 900), creates: 2);
    await run(tester);
    await tester.tap(find.byKey(const ValueKey('run-cleanup-delete')));
    await tester.pumpAndSettle();
    expect(find.text('2 records were created by this run, and deleted'), findsOneWidget);

    await tester.tap(find.text('Run again'));
    await tester.pumpAndSettle();

    expect(find.text('2 records were created by this run'), findsOneWidget, reason: 'the new run\'s two, not the four of the session');
    expect(ledger.entries, hasLength(4));
    expect(ledger.deletableCount, 2);
  });

  testWidgets('a run that created nothing has no panel', (tester) async {
    await open(tester, size: const Size(1200, 900), creates: 0);

    await run(tester);

    expect(find.byKey(const ValueKey('run-cleanup-panel')), findsNothing);
    expect(ledger.entries, isEmpty);
  });
}
