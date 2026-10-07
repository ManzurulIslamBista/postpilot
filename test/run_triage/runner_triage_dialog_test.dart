// The collection runner dialog with its Triage tab, run for real over fake repositories and a scripted server: a
// finished run is grouped by cause and stored in the run history, "Re-run failed only" sends exactly the failed requests,
// and the next run is compared with the one before.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/theme/app_theme.dart';
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
import 'package:postpilot/features/run_triage/domain/entities/run_record_doc.dart';
import 'package:postpilot/features/run_triage/domain/repositories/run_record_repository.dart';
import 'package:postpilot/features/run_triage/domain/services/run_record_codec.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';

const _collectionId = 1;

ApiRequestEntity _request(int id, String name, String path, {HttpMethod method = HttpMethod.get, int? folderId}) => ApiRequestEntity(
      id: id,
      collectionId: _collectionId,
      folderId: folderId,
      name: name,
      method: method,
      url: 'https://api.test$path?api_key=SECRETVALUE99',
      headers: const [],
      queryParams: const [],
      body: RequestBody.empty,
      auth: const RequestAuth(type: AuthType.none),
    );

final class _Server implements ApiClient {
  final sent = <String>[];
  int Function(String path) statusFor = (_) => 200;
  Completer<void>? gate;

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    sent.add(Uri.parse(spec.url).path);
    final hold = gate;
    if (hold != null) {
      final token = spec.cancelToken;
      await Future.any([hold.future, if (token != null) token.whenCancelled]);
      if (token != null && token.isCancelled) throw StateError('cancelled');
    }
    return ApiHttpResponse(
      statusCode: statusFor(Uri.parse(spec.url).path),
      statusMessage: 'OK',
      headers: const {},
      bodyBytes: utf8.encode('{}'),
      duration: const Duration(milliseconds: 40),
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
  Stream<List<FolderEntity>> watchFolders(int collectionId) =>
      Stream.value(const [FolderEntity(id: 10, collectionId: _collectionId, parentFolderId: null, name: 'Orders')]);

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

final class _Records implements RunRecordRepository {
  final stored = <StoredRun>[];
  bool failToSave = false;
  var _next = 1;

  @override
  Future<int> save(int collectionId, RunRecordDoc doc) async {
    if (failToSave) throw StateError('disk full');
    final id = _next++;
    // Stored the way the real repository does: masked and capped.
    final prepared = RunRecordCodec.prepare(doc);
    stored.insert(
      0,
      StoredRun(
        id: id,
        collectionId: collectionId,
        doc: RunRecordCodec.fromColumns(
          collectionName: '',
          environmentName: prepared.environmentName,
          source: prepared.source,
          passed: prepared.passed,
          failed: prepared.failed,
          skipped: prepared.skipped,
          durationMs: prepared.durationMs,
          summaryJson: prepared.summaryJson,
          resultsJson: prepared.resultsJson,
          startedAt: prepared.startedAt,
        ),
      ),
    );
    return id;
  }

  @override
  Future<List<StoredRun>> recent(int collectionId, {int limit = 50}) async => stored.take(limit).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
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

final class _NoEnvironment implements EnvironmentRepository {
  @override
  Future<Map<String, String>> getActiveVariables() async => const {};

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
  late _Requests requests;
  late _Records records;
  late CollectionRunnerViewModel vm;
  String? clipboard;

  setUp(() {
    server = _Server()..statusFor = (path) => path.startsWith('/orders') ? 401 : 200;
    requests = _Requests([
      _request(1, 'Login', '/login', method: HttpMethod.post),
      _request(2, 'List orders', '/orders', folderId: 10),
      _request(3, 'Get order', '/orders/2', folderId: 10),
      _request(4, 'Health', '/health'),
    ]);
    records = _Records();
    final resolver = BuildVariableResolverUseCase(_NoVariables(), _NoEnvironment(), _Globals());
    final send = SendRequestUseCase(server, resolver, _NoHistory(), _NoAuth());
    final scripts = RunRequestScriptsUseCase(_NoScripts(), resolver, _NoEnvironment(), _Globals());
    final service = CollectionRunnerService(requests, send, scripts, (_) async {});
    vm = CollectionRunnerViewModel(
      service,
      const RunDataParser(),
      const CollectionRunExporter(),
      ({required String fileName, required Uint8List bytes, required String mimeType}) async => null,
    );
    clipboard = null;
  });

  tearDown(() async => locator.reset());

  Future<void> open(WidgetTester tester, {required Size size, bool dark = false, bool withHistory = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    locator
      ..registerFactory<CollectionRunnerViewModel>(() => vm)
      ..registerSingleton<CollectionRepository>(_Collections())
      ..registerSingleton<EnvironmentRepository>(_Environments())
      ..registerSingleton<RequestRepository>(requests);
    if (withHistory) locator.registerSingleton<RunRecordRepository>(records);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Builder(
        builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () => CollectionRunnerDialog.show(context, collectionId: _collectionId), child: const Text('open')))),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> runAndOpenTriage(WidgetTester tester) async {
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Triage'));
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    for (final size in const [Size(1200, 900), Size(420, 800)]) {
      final label = '${dark ? 'dark' : 'light'} ${size.width.toInt()}px';

      testWidgets('a finished run is triaged: two failures, one cause, with the hint ($label)', (tester) async {
        await open(tester, size: size, dark: dark);
        await runAndOpenTriage(tester);

        expect(find.text('2 failures, 1 cause'), findsOneWidget);
        expect(find.text('HTTP 401 Unauthorized'), findsOneWidget);
        expect(find.textContaining('2 requests failed with 401 (Unauthorized)'), findsOneWidget);
        expect(find.textContaining('Renew the auth'), findsOneWidget);
        expect(find.text('2 passed'), findsOneWidget);
        expect(find.text('2 failed'), findsOneWidget);
        expect(find.text('Re-run failed only (2)'), findsOneWidget);
        expect(find.text('Copy as GitHub issue'), findsOneWidget);
        // The results tab is still there and is the first one.
        expect(find.textContaining('Triage (1 cause)'), findsOneWidget);
      });
    }
  }

  testWidgets('the finished run is stored in the run history, masked, with the folder, address and environment', (tester) async {
    await open(tester, size: const Size(1200, 900));
    await runAndOpenTriage(tester);

    final run = records.stored.single.doc;
    expect((run.collection, run.environment, run.source, run.trigger), ('Shop', 'Staging', 'app', 'manual'));
    expect((run.passed, run.failed, run.skipped), (2, 2, 0));
    final failed = run.results.where((r) => r.isFailed).toList();
    expect(failed.map((r) => (r.name, r.folder, r.status)), [('List orders', 'Orders', 401), ('Get order', 'Orders', 401)]);
    expect(failed.first.requestId, 2);
    expect(failed.first.url, 'https://api.test/orders', reason: 'the address as written, without its query');
    expect(jsonEncode(run.results.map((r) => r.toJson()).toList()), isNot(contains('SECRETVALUE99')));
    expect(find.textContaining('Saved to the run history'), findsOneWidget);
  });

  testWidgets('Copy as GitHub issue puts masked Markdown on the clipboard', (tester) async {
    await open(tester, size: const Size(1200, 900));
    await runAndOpenTriage(tester);
    await tester.tap(find.text('Copy as GitHub issue'));
    await tester.pumpAndSettle();
    expect(clipboard, startsWith('## PostPilot: 2 of 4 requests failed in Shop (Staging)'));
    expect(clipboard, contains('#### 1. HTTP 401 Unauthorized: 2 requests'));
    expect(clipboard, contains('`GET https://api.test/orders` (Orders / List orders): status 401'));
    expect(clipboard, isNot(contains('SECRETVALUE99')));
    expect(find.textContaining('Issue text copied'), findsOneWidget);
  });

  testWidgets('Re-run failed only sends exactly the failed requests, then the triage compares with the run before', (tester) async {
    await open(tester, size: const Size(1200, 900));
    await runAndOpenTriage(tester);
    expect(server.sent, ['/login', '/orders', '/orders/2', '/health']);

    // The token was renewed: the orders answer again.
    server.statusFor = (_) => 200;
    await tester.tap(find.text('Re-run failed only (2)'));
    await tester.pumpAndSettle();
    expect(server.sent.skip(4), ['/orders', '/orders/2'], reason: 'only the failed ones, in their usual order');

    await tester.tap(find.textContaining('Triage'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing failed'), findsOneWidget);
    expect(records.stored, hasLength(2));
    expect(records.stored.first.doc.results.map((r) => r.name), ['List orders', 'Get order']);
    // Compared with the run before: both failures are fixed.
    expect(find.textContaining('Since the run before'), findsOneWidget);
    expect(find.text('2 fixed'), findsOneWidget);
    expect(find.text('0 new'), findsOneWidget);
  });

  testWidgets('a second full run shows what is new, fixed and still failing', (tester) async {
    await open(tester, size: const Size(1200, 900));
    await runAndOpenTriage(tester);
    // Orders keep failing, and Health starts failing too.
    server.statusFor = (path) => path == '/health' ? 503 : (path == '/orders' ? 500 : 200);
    await tester.tap(find.text('Edit setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Triage'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Since the run before'), findsOneWidget);
    expect(find.text('1 new'), findsOneWidget);
    expect(find.text('1 fixed'), findsOneWidget);
    expect(find.text('1 still failing'), findsOneWidget);
    expect(find.text('2 failures, 2 causes'), findsOneWidget);
  });

  testWidgets('a stopped run is triaged as partial and is not stored', (tester) async {
    server.gate = Completer<void>();
    await open(tester, size: const Size(1200, 900));
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump();
    server.gate!.complete();
    server.gate = Completer<void>(); // the second request will hang
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Triage'));
    await tester.pumpAndSettle();

    expect(find.textContaining('The run was stopped'), findsOneWidget);
    expect(records.stored, isEmpty);
  });

  testWidgets('without a run history the triage still works, and says nothing about saving', (tester) async {
    await open(tester, size: const Size(1200, 900), withHistory: false);
    await runAndOpenTriage(tester);
    expect(find.text('2 failures, 1 cause'), findsOneWidget);
    expect(find.textContaining('Saved to the run history'), findsNothing);
    expect(find.textContaining('Since the run before'), findsNothing);
  });

  testWidgets('a history that cannot be written is said so, and the triage is still shown', (tester) async {
    records.failToSave = true;
    await open(tester, size: const Size(1200, 900));
    await runAndOpenTriage(tester);
    expect(find.text('2 failures, 1 cause'), findsOneWidget);
    expect(find.textContaining('could not be added to the run history'), findsOneWidget);
    expect(find.textContaining('disk full'), findsOneWidget);
  });

  testWidgets('before a run the Triage tab says there is nothing to look at, and while it runs it waits', (tester) async {
    server.gate = Completer<void>();
    await open(tester, size: const Size(1200, 900));
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.textContaining('Triage'));
    // Not pumpAndSettle: a spinner is turning for as long as the request hangs.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('appears when the run has finished'), findsOneWidget);
    server.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('2 failures, 1 cause'), findsOneWidget);
  });

  testWidgets('a passing run has no causes and no issue to copy', (tester) async {
    server.statusFor = (_) => 200;
    await open(tester, size: const Size(1200, 900));
    await runAndOpenTriage(tester);
    expect(find.text('Nothing failed'), findsOneWidget);
    // `.icon` buttons are private subclasses, so they are found by what they are: a button with this label.
    VoidCallback? onPressedOf(String label) =>
        tester.widget<ButtonStyleButton>(find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>())).onPressed;
    expect(onPressedOf('Copy as GitHub issue'), isNull);
    expect(onPressedOf('Re-run failed only'), isNull);
  });

  testWidgets('the dialog can open with exactly some requests ticked (from the run history)', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    locator
      ..registerFactory<CollectionRunnerViewModel>(() => vm)
      ..registerSingleton<RunRecordRepository>(records);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(onPressed: () => CollectionRunnerDialog.show(context, collectionId: _collectionId, onlyRequestIds: const [2, 3, 999]), child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(vm.requests.map((r) => r.name), ['List orders', 'Get order'], reason: 'an id the collection no longer has is ignored');
    expect(find.textContaining('2 requests x 1 iteration'), findsOneWidget);
  });
}
