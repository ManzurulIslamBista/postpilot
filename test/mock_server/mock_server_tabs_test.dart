// The mock server dialog's tabs (Routes, From OpenAPI, Scenarios, Requests), opened for real in a light and a dark theme on a
// desktop and a phone screen, with the server replaced by one that has no socket. A document is loaded and served,
// scenarios are switched, a rule is added, a request arrives and is copied as cURL. Flutter turns a layout overflow into a
// test failure, so this also shows every tab fits both sizes.
// (A separate file from the socket tests: the widget test binding fakes every HttpClient.)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/widgets/tool_dialog.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/mock_server/data/mock_server_engine.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_http.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_scenarios.dart';
import 'package:postpilot/features/mock_server/domain/usecases/build_mock_routes_usecase.dart';
import 'package:postpilot/features/mock_server/presentation/mock_openapi_tab.dart';
import 'package:postpilot/features/mock_server/presentation/mock_routes_tab.dart';
import 'package:postpilot/features/mock_server/presentation/mock_scenarios_tab.dart';
import 'package:postpilot/features/mock_server/presentation/mock_server_dialog.dart';
import 'package:postpilot/features/mock_server/presentation/mock_server_view_model.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'package:provider/provider.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/shop_seed.dart';
import 'fake_mock_engine.dart';
import 'shop_openapi_fixture.dart';

void main() {
  late InMemoryDb db;
  late FakeMockEngine engine;
  late MockServerViewModel vm;
  late String? copied;

  setUp(() async {
    await locator.reset();
    copied = null;
    db = InMemoryDb();
    final collection = await db.collectionRepository.createCollection('Shop');
    final list = await addRequest(db, collection, 'List users', url: '{{baseUrl}}/users');
    await db.exampleRepository.add(ResponseExampleEntity(id: 0, requestId: list, name: 'OK', statusCode: 200, headers: const {}, body: '[{"id":1}]', savedAt: DateTime.utc(2026, 1, 1)));
    await db.exampleRepository.add(ResponseExampleEntity(id: 0, requestId: list, name: 'Gone', statusCode: 410, headers: const {}, body: '{"gone":true}', savedAt: DateTime.utc(2026, 1, 2)));
    engine = FakeMockEngine();
    vm = MockServerViewModel(BuildMockRoutesUseCase(db.loader, db.exampleRepository), createEngine: () => engine);
    locator.registerSingleton<MockServerViewModel>(vm);
  });

  tearDown(() => locator.reset());

  /// Real in-memory IO finishes outside the fake clock: alternate between letting it finish and letting the widgets react.
  Future<void> until(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 300 && !condition(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(condition(), isTrue, reason: 'timed out waiting');
  }

  Future<void> open(WidgetTester tester, {Size size = const Size(1200, 900), bool dark = false, Future<String?> Function()? pick}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': shopOpenApiJson};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final collections = CollectionsViewModel(db.collectionRepository, db.requestRepository);
    addTearDown(collections.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<CollectionsViewModel>.value(
      value: collections,
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => ToolDialog.show(context, (_) => MockServerDialog(pickSpecFile: pick)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Pumps frames, as the tab bar and the pages animate.
  Future<void> settle(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tab(WidgetTester tester, String name) async {
    final finder = find.widgetWithText(Tab, name);
    await tester.ensureVisible(finder);
    await tester.tap(finder, warnIfMissed: false);
    await settle(tester);
  }

  Future<void> press(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.tap(finder, warnIfMissed: false);
    await tester.pump();
  }

  /// Brings [finder] into view inside the scrollable of the tab [tabType].
  Future<void> scrollTo(WidgetTester tester, Type tabType, Finder finder) async {
    final scrollable = find.descendant(of: find.byType(tabType), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(finder, 150, scrollable: scrollable, maxScrolls: 60);
  }

  Future<void> start(WidgetTester tester) async {
    await press(tester, 'Start');
    await until(tester, () => vm.isRunning);
  }

  Future<void> loadDocument(WidgetTester tester) async {
    await tab(tester, 'From OpenAPI');
    await tester.enterText(find.byKey(const ValueKey('openapi-text')), shopOpenApiJson);
    await tester.pump();
    await press(tester, 'Load document');
    await tester.pump(const Duration(milliseconds: 200));
  }

  MockRequest get(String path, {Map<String, List<String>> query = const {}}) => MockRequest(method: 'GET', path: path, query: query);

  testWidgets('the four tabs are there, with the server controls above them', (tester) async {
    await open(tester);
    for (final name in ['Routes', 'From OpenAPI', 'Scenarios', 'Requests']) {
      expect(find.widgetWithText(Tab, name), findsOneWidget, reason: name);
    }
    // The secure defaults stay on the first screen.
    expect(find.widgetWithText(TextField, 'Allowed origin'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'CORS'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Allow other devices'), findsOneWidget);
    expect(find.text('Every website can read these answers'), findsOneWidget);
    expect(find.text('Saved examples'), findsOneWidget);
    expect(find.text('OpenAPI document'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final size in const [Size(1200, 900), Size(420, 800)]) {
      final label = '${dark ? 'dark' : 'light'} ${size.width.toInt()}px';

      testWidgets('every tab renders, before and after a document is served and requests arrive ($label)', (tester) async {
        await open(tester, size: size, dark: dark);
        for (final name in ['Routes', 'From OpenAPI', 'Scenarios', 'Requests']) {
          await tab(tester, name);
        }
        await loadDocument(tester);
        expect(find.text('Shop'), findsWidgets);
        await start(tester);
        engine.emit(MockLogEntry(
          at: DateTime(2026, 10, 6, 9, 5, 3),
          method: 'POST',
          path: '/api/v1/users?api_key=••••••',
          status: 201,
          route: 'POST /users',
          duration: const Duration(milliseconds: 12),
          scenario: 'slow 100 ms (100 ms)',
          requestHeaders: const {'authorization': 'Bearer ••••••'},
          requestBody: '{"name":"Ann","password":"••••••"}',
          responseBody: '{"id":11}',
        ));
        await tester.pump(const Duration(milliseconds: 100));
        for (final name in ['Routes', 'From OpenAPI', 'Scenarios', 'Requests', 'Routes']) {
          await tab(tester, name);
        }
        expect(find.textContaining('Serving 17 routes from Shop'), findsOneWidget);
      });
    }
  }

  testWidgets('From OpenAPI: a pasted document is read, served, and its resources listed; Reset puts the data back', (tester) async {
    await open(tester);
    await loadDocument(tester);
    expect(vm.spec!.title, 'Shop');
    expect(vm.source, MockSourceKind.openApi);
    expect(find.textContaining('17 operations, 3 resources with data in memory'), findsOneWidget);
    expect(find.textContaining('Served under /api/v1'), findsOneWidget);
    expect(find.textContaining('This is what the server serves'), findsOneWidget);
    await scrollTo(tester, MockOpenApiTab, find.text('RESOURCES WITH DATA IN MEMORY (3)'));
    await scrollTo(tester, MockOpenApiTab, find.text('/users  and  /users/{id}'));
    expect(find.textContaining('list · create · read · replace · update · delete'), findsOneWidget);
    await scrollTo(tester, MockOpenApiTab, find.textContaining('No data in memory yet'));

    await start(tester);
    await tab(tester, 'From OpenAPI');
    await tester.runAsync(() => vm.backend.handle(get('/api/v1/users')));
    // A request to the server shows on the next frame.
    vm.update();
    await tester.pump();
    await scrollTo(tester, MockOpenApiTab, find.textContaining('10 items in memory across 1 collection'));
    await press(tester, 'Reset data');
    await scrollTo(tester, MockOpenApiTab, find.textContaining('No data in memory yet'));
    expect(vm.specHandler!.store.itemCount, 0);
  });

  testWidgets('From OpenAPI: a bad document is explained, and a file can be opened instead of pasting', (tester) async {
    await open(tester, pick: () async => shopSwagger2Json);
    await tab(tester, 'From OpenAPI');
    await tester.enterText(find.byKey(const ValueKey('openapi-text')), '{"hello": "world"}');
    await tester.pump();
    await press(tester, 'Load document');
    expect(find.textContaining('That is not an OpenAPI or Swagger document'), findsOneWidget);
    expect(vm.spec, isNull);

    await press(tester, 'Open file…');
    await tester.pump(const Duration(milliseconds: 200));
    expect(vm.spec!.title, 'Pets');
    expect(vm.specError, isNull);
    expect(vm.source, MockSourceKind.openApi);
    expect(find.textContaining('Served under /v2'), findsOneWidget);
  });

  testWidgets('From OpenAPI: the file dialog failing is said, not thrown', (tester) async {
    await open(tester, pick: () async => throw const FormatException('The file is larger than 20 MB'));
    await tab(tester, 'From OpenAPI');
    await press(tester, 'Open file…');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining("Couldn't read the file"), findsOneWidget);
    expect(find.textContaining('larger than 20 MB'), findsOneWidget);
  });

  testWidgets('From OpenAPI: a document from the clipboard, and the settings rebuild the data', (tester) async {
    await open(tester);
    await tab(tester, 'From OpenAPI');
    await press(tester, 'Paste from clipboard');
    await tester.pump(const Duration(milliseconds: 200));
    expect(vm.spec!.title, 'Shop');
    await scrollTo(tester, MockOpenApiTab, find.widgetWithText(TextField, 'Items per resource'));
    await tester.enterText(find.widgetWithText(TextField, 'Items per resource'), '3');
    await tester.pump();
    expect(vm.seedCount, 3);
    await tester.enterText(find.widgetWithText(TextField, 'Seed'), '42');
    await tester.pump();
    expect(vm.seed, 42);
    await tester.tap(find.widgetWithText(FilterChip, 'Check requests against the spec'));
    await tester.pump();
    expect(vm.validateRequests, isFalse);
  });

  testWidgets('without any collection the dialog still offers the OpenAPI document', (tester) async {
    db.collections.clear();
    await open(tester);
    expect(find.text('No collections yet'), findsOneWidget);
    await press(tester, 'Serve an OpenAPI document');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.widgetWithText(Tab, 'From OpenAPI'), findsOneWidget);
    expect(vm.source, MockSourceKind.openApi);
  });

  testWidgets('Routes: the address for each device with a copy button', (tester) async {
    await open(tester);
    await start(tester);
    await tab(tester, 'Routes');
    expect(find.text('http://localhost:3001'), findsWidgets);
    expect(find.text('http://10.0.2.2:3001'), findsOneWidget);
    expect(find.text('http://10.0.3.2:3001'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy http://10.0.2.2:3001'));
    await tester.pump();
    expect(copied, 'http://10.0.2.2:3001');
    await scrollTo(tester, MockRoutesTab, find.text('/users'));
    expect(find.text('/users'), findsOneWidget);
  });

  testWidgets('Scenarios: a global scenario with its settings, a route of its own, and back to normal', (tester) async {
    await open(tester);
    await start(tester);
    await tab(tester, 'Scenarios');

    // Whole server: slow, with the two bounds.
    await tester.tap(find.byType(DropdownButtonFormField<MockScenarioKind?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slow').last);
    await tester.pumpAndSettle();
    expect(vm.scenarios.global.kind, MockScenarioKind.slow);
    await tester.enterText(find.widgetWithText(TextField, 'From').first, '200');
    await tester.enterText(find.widgetWithText(TextField, 'To').first, '800');
    await tester.pump();
    expect([vm.scenarios.global.latencyMinMs, vm.scenarios.global.latencyMaxMs], [200, 800]);
    expect(find.textContaining('a random time from 200 to 800 ms'), findsOneWidget);

    // One route: flaky, every 2nd. Its own scenario replaces the slow one, so there is no waiting below.
    final row = find.byKey(const ValueKey('scenario-GET /users'));
    await scrollTo(tester, MockScenariosTab, row);
    await tester.tap(find.descendant(of: row, matching: find.byType(DropdownButtonFormField<MockScenarioKind?>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flaky').last);
    await tester.pumpAndSettle();
    expect(vm.scenarios.routes['GET /users']!.kind, MockScenarioKind.flaky);
    await tester.enterText(find.descendant(of: row, matching: find.widgetWithText(TextField, 'Every Nth')), '2');
    await tester.pump();
    expect(vm.scenarios.routes['GET /users']!.failEvery, 2);
    expect(find.descendant(of: row, matching: find.textContaining('Every 2nd request answers 500')), findsOneWidget);

    // The scenario really reaches the server's backend.
    final statuses = <int>[];
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        statuses.add((await engine.backend!.handle(get('/users'))).response!.status);
      }
    });
    expect(statuses, [200, 500, 200]);

    await scrollTo(tester, MockScenariosTab, find.text('Back to normal everywhere'));
    await tester.tap(find.text('Back to normal everywhere'));
    await tester.pump();
    expect(vm.scenarios.isAllNormal, isTrue);
  });

  testWidgets('Scenarios: a rule that picks a saved example by a query parameter', (tester) async {
    await open(tester);
    await start(tester);
    await tab(tester, 'Scenarios');
    await scrollTo(tester, MockScenariosTab, find.text('Add a rule'));
    await tester.tap(find.text('Add a rule'));
    await tester.pump();
    expect(vm.rules, hasLength(1));
    expect(vm.rules.single.routeKey, 'GET /users');
    expect(vm.rules.single.exampleName, 'Gone', reason: 'defaults to the last saved example');
    await scrollTo(tester, MockScenariosTab, find.widgetWithText(TextField, 'Name'));
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'broken');
    await tester.enterText(find.widgetWithText(TextField, 'equals'), '1');
    await tester.pump();
    expect([vm.rules.single.field, vm.rules.single.equals], ['broken', '1']);
    final o = await tester.runAsync(() => engine.backend!.handle(get('/users', query: {'broken': ['1']})));
    expect(o!.response!.status, 410);
    await tester.tap(find.byTooltip('Remove this rule'));
    await tester.pump();
    expect(vm.rules, isEmpty);
  });

  testWidgets('Scenarios: rules are explained when the server serves a document', (tester) async {
    await open(tester);
    await loadDocument(tester);
    await tab(tester, 'Scenarios');
    await scrollTo(tester, MockScenariosTab, find.textContaining('Rules choose between saved examples'));
    expect(find.textContaining('Rules choose between saved examples'), findsOneWidget);
    final add = find.ancestor(of: find.text('Add a rule'), matching: find.bySubtype<OutlinedButton>());
    await scrollTo(tester, MockScenariosTab, add);
    expect(tester.widget<OutlinedButton>(add).onPressed, isNull);
  });

  testWidgets('Requests: a row opens to the masked headers and bodies, and copies as cURL', (tester) async {
    await open(tester);
    await start(tester);
    await tab(tester, 'Requests');
    expect(find.text('Waiting for requests'), findsOneWidget);
    engine.emit(MockLogEntry(
      at: DateTime(2026, 10, 6, 9, 5, 3),
      method: 'POST',
      path: '/users?api_key=••••••',
      status: 201,
      route: 'POST /users',
      duration: const Duration(milliseconds: 12),
      scenario: 'flaky (every 2nd, 500): passed',
      requestHeaders: const {'authorization': 'Bearer ••••••', 'content-type': 'application/json'},
      requestBody: '{"name":"Ann","password":"••••••"}',
      responseBody: '{"id":11}',
    ));
    engine.emit(MockLogEntry(at: DateTime(2026, 10, 6, 9, 5, 4), method: 'GET', path: '/hang', status: 0, route: null, duration: Duration.zero, scenario: 'timeout'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('09:05:04'), findsOneWidget);
    expect(find.text('no answer'), findsOneWidget);
    expect(find.text('201 · 12 ms'), findsOneWidget);
    expect(find.textContaining('flaky (every 2nd, 500): passed'), findsOneWidget);
    expect(find.textContaining('Passwords, tokens and keys are masked'), findsOneWidget);

    await tester.tap(find.text('/users?api_key=••••••'));
    await tester.pumpAndSettle();
    expect(find.textContaining('authorization: Bearer ••••••'), findsOneWidget);
    expect(find.textContaining('"password":"••••••"'), findsWidgets);
    await tester.tap(find.text('Copy as cURL'));
    await tester.pump();
    expect(copied, startsWith("curl --request POST 'http://localhost:3001/users?api_key=••••••'"));
    expect(copied, contains("--header 'authorization: Bearer ••••••'"));
    expect(copied, contains("--data-raw '{\"name\":\"Ann\",\"password\":\"••••••\"}'"));
    expect(copied, isNot(contains('hunter2')));

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(find.text('Waiting for requests'), findsOneWidget);
  });
}
