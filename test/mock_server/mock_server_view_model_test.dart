import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/mock_server/data/mock_server_engine.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_example_handler.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_http.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_pagination.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_scenarios.dart';
import 'package:postpilot/features/mock_server/domain/usecases/build_mock_routes_usecase.dart';
import 'package:postpilot/features/mock_server/presentation/mock_server_view_model.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import '../support/in_memory_import_export_fakes.dart';
import '../support/shop_seed.dart';
import 'fake_mock_engine.dart';
import 'shop_openapi_fixture.dart';

void main() {
  late InMemoryDb db;
  late int collection;
  late FakeMockEngine engine;
  late MockServerViewModel vm;

  setUp(() async {
    db = InMemoryDb();
    collection = await db.collectionRepository.createCollection('Shop');
    final list = await addRequest(db, collection, 'List users', url: '{{baseUrl}}/users');
    await db.exampleRepository.add(ResponseExampleEntity(id: 0, requestId: list, name: 'Gone', statusCode: 410, headers: const {}, body: '{"gone":true}', savedAt: DateTime.utc(2026, 1, 2)));
    await db.exampleRepository.add(ResponseExampleEntity(id: 0, requestId: list, name: 'OK', statusCode: 200, headers: const {'content-type': 'application/json'}, body: '[{"id":1}]', savedAt: DateTime.utc(2026, 1, 1)));
    await addRequest(db, collection, 'No example', url: '{{baseUrl}}/ghost');
    engine = FakeMockEngine();
    vm = MockServerViewModel(BuildMockRoutesUseCase(db.loader, db.exampleRepository), createEngine: () => engine);
    vm.collectionId = collection;
    vm.portText = '3456';
  });

  tearDown(() => vm.dispose());

  group('routes from the collection', () {
    test('the default answer is the newest successful example; the others stay available', () async {
      final table = await BuildMockRoutesUseCase(db.loader, db.exampleRepository)(collection);
      final route = table.routes.single;
      expect(route.path, '/users');
      expect([route.status, route.exampleName], [200, 'OK']);
      expect(route.allExamples.map((e) => '${e.status} ${e.name}'), ['200 OK', '410 Gone']);
      expect(table.skipped, ['No example']);
    });
  });

  group('starting', () {
    test('the engine gets the config, the table and the model\'s own backend', () async {
      vm
        ..update(corsOn: false, others: true, delay: 25)
        ..update(origin: 'http://localhost:5173');
      await vm.start();
      expect(vm.error, isNull);
      expect(vm.isRunning, isTrue);
      expect(engine.config!.port, 3456);
      expect(engine.config!.allowOtherDevices, isTrue);
      expect(engine.config!.cors, isFalse);
      expect(engine.config!.delay, const Duration(milliseconds: 25));
      expect(engine.table!.routes.single.path, '/users');
      expect(identical(engine.backend, vm.backend), isTrue);
      expect(vm.routes.single.key, 'GET /users');
    });

    test('scenarios and rules set before the server starts are the ones it runs with', () async {
      vm
        ..setGlobalScenario(const MockScenario(MockScenarioKind.serverError))
        ..setRouteScenario('GET /users', MockScenario.normal)
        ..setRules(const [MockMatchRule(id: 'r', routeKey: 'GET /users', source: MockMatchSource.query, field: 'a', equals: '1', exampleName: 'Gone')]);
      await vm.start();
      final backend = engine.backend!;
      expect(backend.scenarios.global.kind, MockScenarioKind.serverError);
      expect(backend.scenarios.routes['GET /users']!.isNormal, isTrue);
      expect(backend.rules.single.id, 'r');
      final o = await backend.handle(MockRequest(method: 'GET', path: '/users', query: const {'a': ['1']}));
      expect(o.response!.status, 410, reason: 'the rule picked the saved 410 example');
    });

    test('a changed delay applies to a server that is already running', () async {
      await vm.start();
      vm.update(delay: 80);
      expect(engine.backend!.delay, const Duration(milliseconds: 80));
    });

    test('refuses a bad port and a bad allowed origin, and says what to do', () async {
      vm.portText = '70000';
      await vm.start();
      expect(vm.error, 'Enter a port between 1 and 65535.');
      expect(engine.starts, 0);
      vm.portText = '3456';
      vm.update(origin: 'not an origin');
      await vm.start();
      expect(vm.error, contains('Allowed origin must be *'));
      expect(engine.starts, 0);
    });

    test('a taken port is reported as the engine words it', () async {
      engine.failWith = 'Port 3456 is already in use or not allowed. Choose another port.';
      await vm.start();
      expect(vm.error, contains('already in use'));
      expect(vm.isRunning, isFalse);
      expect(vm.isBusy, isFalse);
    });

    test('stop and reload', () async {
      await vm.start();
      await vm.stop();
      expect(vm.isRunning, isFalse);
      await vm.start();
      // A new example is served after Reload, without a restart.
      await db.exampleRepository.add(ResponseExampleEntity(id: 0, requestId: db.requests.first.id, name: 'Late', statusCode: 200, headers: const {}, body: '[]', savedAt: DateTime.utc(2026, 2, 1)));
      await vm.reload();
      expect(engine.table!.routes.single.allExamples.map((e) => e.name), contains('Late'));
      expect(engine.starts, 2);
    });
  });

  group('serving an OpenAPI document', () {
    test('a document is read, offered as the source and served live', () async {
      vm.loadSpec(shopOpenApiJson);
      expect(vm.specError, isNull);
      expect(vm.spec!.title, 'Shop');
      expect(vm.specHandler!.summary, '17 operations, 3 resources with data in memory');
      await vm.start();
      expect(vm.backend.spec, isNull, reason: 'still serving the saved examples');
      vm.useSource(MockSourceKind.openApi);
      expect(vm.backend.spec, same(vm.specHandler), reason: 'switched while running, no restart');
      expect(vm.routes, hasLength(17));
      final o = await vm.backend.handle(MockRequest(method: 'GET', path: '/api/v1/users'));
      expect(jsonDecode(o.response!.body)['total'], 10);
      vm.useSource(MockSourceKind.examples);
      expect(vm.backend.spec, isNull);
      expect(vm.routes.single.key, 'GET /users');
    });

    test('starting needs a document in this mode, and no collection', () async {
      vm
        ..useSource(MockSourceKind.openApi)
        ..collectionId = null;
      await vm.start();
      expect(vm.error, contains('Load an OpenAPI document first'));
      expect(engine.starts, 0);
      vm.loadSpec(shopOpenApiJson);
      await vm.start();
      expect(vm.error, isNull);
      expect(engine.starts, 1);
      expect(engine.table!.routes, isEmpty);
    });

    test('a document that cannot be read says so and leaves the one in use', () {
      vm.loadSpec(shopOpenApiJson);
      final before = vm.specHandler;
      vm.loadSpec('{"hello": "world"}');
      expect(vm.specError, startsWith('That is not an OpenAPI or Swagger document:'));
      expect(vm.specHandler, same(before));
      vm.loadSpec('openapi: 3.0.0\n  bad: [yaml');
      expect(vm.specError, isNotNull);
      expect(vm.specHandler, same(before));
      vm.loadSpec(shopOpenApiJson);
      expect(vm.specError, isNull);
    });

    test('settings rebuild the handler, so the data starts again; seedCount is kept within sensible bounds', () async {
      vm.loadSpec(shopOpenApiJson);
      final first = vm.specHandler!;
      vm.useSource(MockSourceKind.openApi);
      MockRequest get(String path) => MockRequest(method: 'GET', path: path);
      var o = await vm.backend.handle(get('/api/v1/users'));
      expect(o.response!.status, 200);
      expect(vm.specHandler!.store.itemCount, 10);

      vm.updateSpecOptions(seedCount: 3, pagination: MockPaginationStrategy.none, seed: 9, validate: false);
      expect(vm.specHandler, isNot(same(first)));
      expect(vm.backend.spec, same(vm.specHandler));
      o = await vm.backend.handle(get('/api/v1/users'));
      expect(jsonDecode(o.response!.body)['total'], 3);
      vm.updateSpecOptions(seedCount: 100000);
      expect(vm.seedCount, 500);
      vm.updateSpecOptions(seedCount: -4);
      expect(vm.seedCount, 0);
    });

    test('reset puts the data back', () async {
      vm.loadSpec(shopOpenApiJson);
      vm.useSource(MockSourceKind.openApi);
      await vm.backend.handle(MockRequest(method: 'POST', path: '/api/v1/users', body: '{"name":"Ann","email":"a@b.c"}'));
      expect(vm.specHandler!.store.itemCount, 11);
      vm.resetData();
      expect(vm.specHandler!.store.itemCount, 0);
    });
  });

  group('scenarios from the dialog', () {
    test('global, per route, back to the global one, and everything back to normal', () {
      var changes = 0;
      vm.addListener(() => changes++);
      vm.setGlobalScenario(const MockScenario.slow(100, 300));
      vm.setRouteScenario('GET /users', const MockScenario.flaky(every: 3));
      expect(vm.scenarios.global.label, 'slow 100-300 ms');
      expect(vm.scenarios.routes['GET /users']!.label, 'flaky (every 3rd, 500)');
      vm.setRouteScenario('GET /users', null);
      expect(vm.scenarios.routes, isEmpty);
      vm.clearScenarios();
      expect(vm.scenarios.global.isNormal, isTrue);
      expect(changes, 4);
    });
  });

  group('addresses for each device', () {
    test('nothing while stopped; localhost, the Android emulator, Genymotion and the local network address when running', () async {
      expect(vm.baseUrls(lanIp: '192.168.1.20'), isEmpty);
      await vm.start();
      final urls = vm.baseUrls(lanIp: '192.168.1.20');
      expect(urls.map((u) => u.url), [
        'http://localhost:3456',
        'http://10.0.2.2:3456',
        'http://10.0.3.2:3456',
        'http://192.168.1.20:3456',
      ]);
      expect(urls[1].label, 'Android emulator');
      expect(urls.last.note, contains('Allow other devices'), reason: 'loopback only: a real phone cannot reach it yet');
      expect(vm.baseUrls().map((u) => u.url), isNot(contains('http://192.168.1.20:3456')), reason: 'no network address known');
    });

    test('with other devices allowed the network address is said to be reachable', () async {
      vm.update(others: true);
      await vm.start();
      expect(vm.baseUrls(lanIp: '10.1.1.5').last.note, 'Reachable from other devices on this network.');
    });
  });

  group('the request log', () {
    MockLogEntry entry(int n) => MockLogEntry(at: DateTime(2026, 10, 6, 12, 0, n % 60), method: 'GET', path: '/r$n', status: 200, route: null, duration: Duration.zero);

    test('newest first, kept to 300, cleared on request', () async {
      await vm.start();
      for (var i = 0; i < 305; i++) {
        engine.emit(entry(i));
      }
      await pumpEventQueue();
      expect(vm.requestCount, 300);
      expect(vm.log.first.path, '/r304');
      expect(vm.log.last.path, '/r5');
      vm.clearLog();
      expect(vm.log, isEmpty);
    });
  });
}
