// A separate file from the socket tests: a suite that uses the widget test binding gets a fake HttpClient, and the recorder
// engine here is a fake without a socket anyway.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/device_helper/data/network_info.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/shell/presentation/shell_view_model.dart';
import 'package:postpilot/features/traffic_recorder/domain/entities/recorded_exchange.dart';
import 'package:postpilot/features/traffic_recorder/domain/usecases/create_collection_from_recording_usecase.dart';
import 'package:postpilot/features/traffic_recorder/presentation/traffic_recorder_dialog.dart';
import 'package:postpilot/features/traffic_recorder/presentation/traffic_recorder_view_model.dart';
import 'package:provider/provider.dart';
import '../support/in_memory_import_export_fakes.dart';
import 'exchange_fixtures.dart';
import 'fake_recorder_engine.dart';

/// The in-memory request repository cannot be watched; opening a request in a tab needs that.
final class _WatchableRequests implements RequestRepository {
  final InMemoryDb db;
  final InMemoryRequestRepository _inner;
  _WatchableRequests(this.db) : _inner = InMemoryRequestRepository(db);

  @override
  Stream<List<RequestSummaryEntity>> watchByCollection(int collectionId) => _inner.watchByCollection(collectionId);

  @override
  Stream<ApiRequestEntity?> watchById(int id) => Stream.value(db.requests.where((r) => r.id == id).firstOrNull);

  @override
  Future<ApiRequestEntity?> findById(int id) => _inner.findById(id);

  @override
  Future<int> createRequest({required int collectionId, int? folderId, required String name}) =>
      _inner.createRequest(collectionId: collectionId, folderId: folderId, name: name);

  @override
  Future<void> saveRequest(ApiRequestEntity request) => _inner.saveRequest(request);

  @override
  Future<void> deleteRequest(int id) => throw UnimplementedError();
}

/// A selectable text (plain or rich) that holds [needle].
Finder selectable(String needle) => find.byWidgetPredicate(
      (w) => w is SelectableText && ((w.data ?? w.textSpan?.toPlainText() ?? '').contains(needle)),
      description: 'selectable text containing "$needle"',
    );

void main() {
  late InMemoryDb db;
  late FakeRecorderEngine engine;
  late TrafficRecorderViewModel vm;
  late CollectionsViewModel collections;
  late ShellViewModel shell;

  setUp(() {
    db = InMemoryDb();
    engine = FakeRecorderEngine();
    vm = TrafficRecorderViewModel(
      CreateCollectionFromRecordingUseCase(db.writer, db.environmentRepository, db.exampleRepository, db.scriptsRepository),
      createEngine: () => engine,
      lookupAddresses: () async => const [LocalAddress('Wi-Fi', '192.168.1.23')],
      saveFile: ({required fileName, required bytes, required mimeType}) async => '/downloads/$fileName',
    );
    final requests = _WatchableRequests(db);
    collections = CollectionsViewModel(db.collectionRepository, requests);
    shell = ShellViewModel(requests);
    addTearDown(() {
      vm.dispose();
      collections.dispose();
      shell.dispose();
    });
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester, {Size size = const Size(1200, 900), ThemeData? theme}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<CollectionsViewModel>.value(value: collections),
        ChangeNotifierProvider<ShellViewModel>.value(value: shell),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(context: context, builder: (_) => TrafficRecorderDialog(viewModel: vm)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Future<void> start(WidgetTester tester, {String upstream = 'https://api.example.com'}) async {
    await tester.enterText(find.widgetWithText(TextField, 'Upstream: the real server'), upstream);
    await tester.pump();
    // The controls scroll on a small screen: the button may be below the visible part.
    await tester.ensureVisible(find.text('Start'));
    await tester.pump();
    await tester.tap(find.text('Start'));
    await settle(tester);
  }

  Future<void> push(WidgetTester tester, Iterable<RecordedExchange> calls) async {
    for (final c in calls) {
      engine.push(c);
    }
    await settle(tester);
  }

  group('before it is started', () {
    testWidgets('explains how it works and says what to enter when Start is pressed without an upstream', (tester) async {
      await open(tester);

      expect(find.text('Traffic recorder'), findsOneWidget);
      expect(find.text('How it works'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Upstream: the real server'), findsOneWidget);

      await tester.tap(find.text('Start'));
      await settle(tester);

      expect(find.textContaining('Enter the address of the server your app talks to'), findsOneWidget);
      expect(engine.starts, 0);
    });

    testWidgets('a taken port is shown as words in the dialog', (tester) async {
      engine.failWith = 'Port 8099 is already in use or not allowed. Choose another port.';
      await open(tester);

      await start(tester);

      expect(find.textContaining('Port 8099 is already in use'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    });
  });

  group('running', () {
    testWidgets('shows the address to give the app, big, with a copy button and the hint line', (tester) async {
      await open(tester);

      await start(tester);

      expect(find.text('Recording :8099'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
      final url = tester.widget<SelectableText>(find.byKey(const ValueKey('recorder-primary-url')));
      expect(url.data, 'http://localhost:8099');
      expect(find.byTooltip('Copy URL'), findsOneWidget);
      expect(find.textContaining('Ask the app to use this'), findsOneWidget);
      expect(find.textContaining('Forwarding to https://api.example.com'), findsOneWidget);
      expect(find.text('Waiting for the app'), findsOneWidget);
    });

    testWidgets('copying the address puts it on the clipboard', (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await open(tester);
      await start(tester);

      await tester.ensureVisible(find.byTooltip('Copy URL'));
      await tester.pump();
      await tester.tap(find.byTooltip('Copy URL'));
      await settle(tester);

      expect(clipboard, 'http://localhost:8099');
    });

    testWidgets('for a phone: a visible warning, the network address first, the adb reverse alternative and the http note', (tester) async {
      await open(tester);

      await tester.tap(find.widgetWithText(FilterChip, 'Also reachable from phones on my network'));
      await settle(tester);
      expect(find.text('Reachable from your network'), findsOneWidget);

      await start(tester);

      expect(engine.config!.host, '0.0.0.0');
      expect(tester.widget<SelectableText>(find.byKey(const ValueKey('recorder-primary-url'))).data, 'http://192.168.1.23:8099');
      expect(find.text('adb reverse tcp:8099 tcp:8099'), findsOneWidget);
      expect(find.text('http://10.0.2.2:8099'), findsOneWidget);
      expect(find.text('Phone on the same Wi-Fi (Wi-Fi)'), findsOneWidget);
      expect(find.text('Plain http:// needs a setting in your app'), findsOneWidget);
    });

    testWidgets('the switches are locked while it runs and Stop ends it', (tester) async {
      await open(tester);
      await start(tester);

      final chip = tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Allow a self-signed upstream'));
      expect(chip.onSelected, isNull);

      await tester.ensureVisible(find.text('Stop'));
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await settle(tester);

      expect(vm.isRunning, isFalse);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Recording :8099'), findsNothing);
    });
  });

  group('the calls', () {
    final login = exchange(
      id: 1,
      method: 'POST',
      path: '/login?api_key=SECRETKEY123',
      status: 201,
      requestHeaders: const [
        RecordedHeader('authorization', 'Bearer abc123tokenvalue'),
        RecordedHeader('content-type', 'application/json'),
      ],
      requestBody: '{"user":"ada","password":"hunter2"}',
      responseBody: '{"ok":true}',
    );

    testWidgets('a row appears when a call finishes, with its path masked, and selecting it shows the masked request', (tester) async {
      await open(tester);
      await start(tester);

      await push(tester, [login]);

      expect(find.text('/login?api_key=••••••'), findsOneWidget);
      expect(find.text('POST'), findsWidgets);
      expect(find.text('201'), findsWidgets);
      expect(find.text('1 call'), findsOneWidget);

      await tester.tap(find.text('/login?api_key=••••••'));
      await settle(tester);

      expect(selectable('Bearer ••••••'), findsOneWidget);
      expect(selectable('abc123tokenvalue'), findsNothing);
      expect(find.text('Resend in PostPilot'), findsOneWidget);
      expect(find.text('Copy as cURL'), findsOneWidget);
    });

    testWidgets('"Show real values" reveals them for the session', (tester) async {
      await open(tester);
      await start(tester);
      await push(tester, [login]);
      await tester.tap(find.text('/login?api_key=••••••'));
      await settle(tester);

      await tester.tap(find.widgetWithText(FilterChip, 'Show real values'));
      await settle(tester);

      expect(selectable('Bearer abc123tokenvalue'), findsOneWidget);
      expect(find.text('/login?api_key=SECRETKEY123'), findsOneWidget);
      expect(find.text('/login?api_key=••••••'), findsNothing);
    });

    testWidgets('Copy as cURL copies the masked command, and the real one only with the toggle on', (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await open(tester);
      await start(tester);
      await push(tester, [login]);
      await tester.tap(find.text('/login?api_key=••••••'));
      await settle(tester);

      await tester.tap(find.text('Copy as cURL'));
      await settle(tester);

      expect(clipboard, contains('curl --request POST'));
      expect(clipboard, contains('Bearer ••••••'));
      expect(clipboard, isNot(contains('abc123tokenvalue')));
      expect(clipboard, isNot(contains('hunter2')));
      expect(find.text('Copied cURL command'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Show real values'));
      await settle(tester);
      await tester.tap(find.text('Copy as cURL'));
      await settle(tester);

      expect(clipboard, contains('Bearer abc123tokenvalue'));
      // The first message is still on screen; the second is queued behind it.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Copied cURL command (with real values)'), findsOneWidget);
    });

    testWidgets('the filter narrows the rows', (tester) async {
      await open(tester);
      await start(tester);
      await push(tester, [exchange(id: 1, path: '/users/1'), exchange(id: 2, path: '/orders/9'), exchange(id: 3, path: '/health')]);
      expect(find.text('3 calls'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Filter by method, path or status'), 'orders');
      await settle(tester);

      expect(find.text('/orders/9'), findsOneWidget);
      expect(find.text('/users/1'), findsNothing);
      expect(find.text('1 of 3 calls'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Filter by method, path or status'), 'nothing like this');
      await settle(tester);
      expect(find.text('No call matches the filter'), findsOneWidget);
    });

    testWidgets('pause stops recording (and says so), resume continues, clear empties the table', (tester) async {
      await open(tester);
      await start(tester);
      await push(tester, [exchange(id: 1, path: '/a')]);

      await tester.tap(find.text('Pause'));
      await settle(tester);
      expect(find.text('Paused :8099'), findsOneWidget);
      await push(tester, [exchange(id: 2, path: '/b')]);
      expect(find.text('/b'), findsNothing);
      expect(find.textContaining('1 not recorded while paused'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      await settle(tester);
      await push(tester, [exchange(id: 3, path: '/c')]);
      expect(find.text('/c'), findsOneWidget);

      await tester.tap(find.text('Clear'));
      await settle(tester);
      expect(find.text('/a'), findsNothing);
      expect(find.text('Waiting for the app'), findsOneWidget);
    });

    testWidgets('a call the recorder answered itself says so in the detail', (tester) async {
      await open(tester);
      await start(tester);
      await push(tester, [
        exchange(id: 1, path: '/chat', status: 501, kind: RecordedKind.refused, error: 'The traffic recorder cannot forward WebSocket connections.'),
      ]);

      await tester.tap(find.text('/chat'));
      await settle(tester);

      expect(find.text('The recorder did not forward this call'), findsOneWidget);
      expect(selectable('cannot forward WebSocket connections'), findsOneWidget);
      final resend = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Resend in PostPilot'));
      expect(resend.onPressed, isNull, reason: 'a refused call has nothing to resend');
    });
  });

  group('Resend in PostPilot', () {
    testWidgets('opens the call as a new request in "My collection" on a fresh install, with no credential, and closes the dialog', (tester) async {
      await open(tester);
      await start(tester);
      await push(tester, [
        exchange(id: 1, path: '/users/42', requestHeaders: const [RecordedHeader('authorization', 'Bearer abc123tokenvalue')]),
      ]);
      await tester.tap(find.text('/users/42'));
      await settle(tester);

      await tester.tap(find.text('Resend in PostPilot'));
      await settle(tester);

      expect(db.collections.single.name, CollectionsViewModel.defaultCollectionName);
      final request = db.requests.single;
      expect(request.url, 'https://api.example.com/users/42');
      expect(request.name, 'GET /users/42');
      expect([for (final h in request.headers) '${h.key}: ${h.value}'], ['Authorization: Bearer {{token}}']);
      expect(shell.selectedRequestId, request.id);
      expect(find.text('Traffic recorder'), findsNothing, reason: 'the dialog closed');
      expect(find.textContaining('Opened as a new request'), findsOneWidget);
      expect(find.textContaining('{{token}}'), findsOneWidget);
      expect(vm.isRunning, isTrue, reason: 'it keeps recording after the dialog is closed');
    });
  });

  group('Create collection from recording', () {
    testWidgets('previews what would be made, then creates it with its environment', (tester) async {
      await open(tester);
      await start(tester);
      await push(tester, [
        exchange(id: 1, path: '/users/1', responseBody: '{"id":1}'),
        exchange(id: 2, path: '/users/2', responseBody: '{"id":2}'),
        exchange(
          id: 3,
          method: 'POST',
          path: '/login',
          requestHeaders: const [RecordedHeader('content-type', 'application/json')],
          requestBody: '{"password":"x"}',
          responseBody: '{"ok":true}',
        ),
        exchange(id: 4, path: '/logo.png'),
      ]);

      await tester.tap(find.text('Create collection…'));
      await settle(tester);

      expect(find.text('Create collection from recording'), findsOneWidget);
      expect(find.text('2 requests in 2 folders, 3 saved examples'), findsOneWidget);
      expect(selectable('1 repeated call merged'), findsOneWidget);
      expect(selectable('Left out: 1 static files'), findsOneWidget);
      expect(selectable('password'), findsWidgets);

      await tester.ensureVisible(find.widgetWithText(SwitchListTile, 'Group into folders'));
      await tester.pump();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Group into folders'));
      await settle(tester);
      expect(find.text('2 requests in 0 folders, 3 saved examples'), findsOneWidget);

      await tester.tap(find.text('Create collection'));
      await settle(tester);

      expect(db.collections.single.name, 'Recorded from api.example.com');
      expect(db.requests.map((r) => r.name), ['GET /users/{userId}', 'POST /login']);
      expect(db.environments.single.name, 'Recorded from api.example.com');
      expect(find.text('Created "Recorded from api.example.com"'), findsOneWidget);
      expect(selectable('Select it and fill in the values'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('the ticked calls are the ones used, and the button says how many', (tester) async {
      await open(tester);
      await start(tester);
      await push(tester, [exchange(id: 1, path: '/a'), exchange(id: 2, path: '/b'), exchange(id: 3, path: '/c')]);

      await tester.tap(find.byType(Checkbox).at(1));
      await settle(tester);
      expect(find.text('Create collection (1)…'), findsOneWidget);

      await tester.tap(find.text('Create collection (1)…'));
      await settle(tester);

      expect(find.textContaining('1 recorded call (the ones you ticked)'), findsOneWidget);
      expect(find.text('1 request in 1 folder, 1 saved example'), findsOneWidget);
    });

    testWidgets('when nothing is left after the filters it says so and cannot create', (tester) async {
      await open(tester);
      await start(tester);
      await push(tester, [exchange(id: 1, path: '/logo.png')]);

      await tester.tap(find.text('Create collection…'));
      await settle(tester);

      expect(selectable('Nothing is left after leaving out 1 call'), findsOneWidget);
      // The dialog's button is disabled: pressing it creates nothing.
      await tester.tap(find.text('Create collection'));
      await settle(tester);
      expect(db.collections, isEmpty);
      expect(db.environments, isEmpty);
    });
  });

  group('layout', () {
    for (final dark in [false, true]) {
      final name = dark ? 'dark' : 'light';
      for (final width in [1200.0, 420.0]) {
        testWidgets('renders and works in $name at ${width.toInt()} px without overflow', (tester) async {
          await open(tester, size: Size(width, 900), theme: dark ? AppTheme.dark : AppTheme.light);
          expect(find.text('Traffic recorder'), findsOneWidget);

          await tester.ensureVisible(find.widgetWithText(FilterChip, 'Also reachable from phones on my network'));
          await tester.pump();
          await tester.tap(find.widgetWithText(FilterChip, 'Also reachable from phones on my network'));
          await settle(tester);
          await start(tester);
          await push(tester, [
            for (var i = 1; i <= 6; i++)
              exchange(
                id: i,
                path: '/api/v1/some/rather/long/path/segment/$i?with=query&and=more&params=here',
                responseBody: '{"id":$i,"items":[1,2,3]}',
                requestHeaders: const [RecordedHeader('authorization', 'Bearer abc123tokenvalue')],
              ),
          ]);
          expect(find.text('Recording :8099'), findsOneWidget);

          await tester.tap(find.byType(Checkbox).at(1));
          await settle(tester);
          await tester.tap(find.textContaining('/api/v1/some/rather/long/path/segment/6').first);
          await settle(tester);
          expect(find.text('Copy as cURL'), findsOneWidget);
          if (width < 600) {
            expect(find.byTooltip('Back to the list'), findsOneWidget);
            await tester.tap(find.byTooltip('Back to the list'));
            await settle(tester);
          }

          await tester.tap(find.text('Create collection (1)…'));
          await settle(tester);
          expect(find.text('Create collection from recording'), findsOneWidget);

          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}


