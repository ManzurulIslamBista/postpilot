import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/import_export/domain/services/collection_loader.dart';
import 'package:postpilot/features/mock_server/data/mock_server_engine.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_cors.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_routes.dart';
import 'package:postpilot/features/mock_server/domain/usecases/build_mock_routes_usecase.dart';
import 'package:postpilot/features/mock_server/presentation/mock_server_view_model.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import '../support/drift_repos.dart';
import '../support/shop_seed.dart';

MockSource _src(String name, String method, String url, {Map<String, String> headers = const {}, String body = '{"ok":true}'}) =>
    MockSource(requestName: name, method: method, url: url, exampleStatus: 200, exampleBody: body, exampleHeaders: headers, exampleName: 'ex');

/// What a real server captured into an example would carry for its own callers.
const _realServerHeaders = {
  'Access-Control-Allow-Origin': 'https://real.example',
  'access-control-allow-credentials': 'true',
  'Access-Control-Expose-Headers': 'x-secret',
  'x-keep': 'yes',
};

void main() {
  group('MockCors', () {
    test('reads * or a list of origins and normalises them', () {
      expect(MockCors.parse(''), ['*']);
      expect(MockCors.parse('  '), ['*']);
      expect(MockCors.parse('*'), ['*']);
      expect(MockCors.parse('http://a.test, *'), ['*']);
      expect(MockCors.parse('HTTP://Localhost:5173/'), ['http://localhost:5173']);
      expect(MockCors.parse('http://a.test, https://b.test:8443 http://a.test'), ['http://a.test', 'https://b.test:8443']);
    });

    test('rejects what is not an origin', () {
      for (final bad in ['localhost:5173', 'http://a.test/path', 'http://a.test?x=1', 'not an origin', 'http://', '://a.test', 'http://u@a.test']) {
        expect(MockCors.parse(bad), isNull, reason: bad);
      }
    });

    test('allows only listed origins unless it is *', () {
      expect(MockCors.allows(['*'], null), isTrue);
      expect(MockCors.allows(['http://a.test'], 'http://a.test'), isTrue);
      expect(MockCors.allows(['http://a.test'], 'HTTP://A.TEST/'), isTrue);
      expect(MockCors.allows(['http://a.test'], 'http://b.test'), isFalse);
      expect(MockCors.allows(['http://a.test'], 'http://a.test.evil.test'), isFalse);
      expect(MockCors.allows(['http://a.test'], null), isFalse);
      expect(MockCors.allows(const [], 'http://a.test'), isFalse);
    });
  });

  group('the mock server\'s own CORS decision', () {
    late MockServerEngine engine;
    final client = HttpClient();

    setUp(() => engine = MockServerEngine.create());
    tearDown(() async => engine.dispose());

    Future<HttpHeaders> call(String path, {String method = 'GET', String? origin, String? requestHeaders}) async {
      final req = await client.openUrl(method, Uri.parse('http://127.0.0.1:${engine.port}$path'));
      if (origin != null) req.headers.set('origin', origin);
      if (requestHeaders != null) req.headers.set('access-control-request-headers', requestHeaders);
      final res = await req.close();
      await res.drain<void>();
      return res.headers;
    }

    Future<void> start(MockServerConfig config) =>
        engine.start(config, MockRouteTable.from([_src('A', 'GET', '/a', headers: _realServerHeaders)]));

    test('with CORS on for every origin, an example\'s Access-Control headers are not replayed', () async {
      await start(const MockServerConfig(port: 0));
      final h = await call('/a', origin: 'https://evil.example');
      expect(h.value('access-control-allow-origin'), '*', reason: 'the mock\'s setting wins over the captured https://real.example');
      expect(h.value('access-control-allow-credentials'), isNull);
      expect(h.value('access-control-expose-headers'), isNull);
      expect(h.value('x-keep'), 'yes', reason: 'ordinary example headers still are');
    });

    test('with CORS off, nothing about CORS is sent, not even the captured headers', () async {
      await start(const MockServerConfig(port: 0, cors: false));
      final h = await call('/a', origin: 'https://real.example');
      expect(h.value('access-control-allow-origin'), isNull);
      expect(h.value('access-control-allow-credentials'), isNull);
      expect(h.value('x-keep'), 'yes');
    });

    test('a named origin may read the answer; any other page may not', () async {
      await start(const MockServerConfig(port: 0, allowedOrigin: 'http://localhost:5173'));
      final ok = await call('/a', origin: 'http://localhost:5173');
      expect(ok.value('access-control-allow-origin'), 'http://localhost:5173');
      expect(ok.value('vary'), 'origin');
      expect(ok.value('access-control-allow-credentials'), isNull);

      for (final other in ['https://evil.example', 'https://real.example', 'http://localhost:5173.evil.example', 'http://localhost:3000']) {
        final h = await call('/a', origin: other);
        expect(h.value('access-control-allow-origin'), isNull, reason: other);
        expect(h.value('vary'), 'origin', reason: 'caches must not hand one origin\'s answer to another');
      }
      expect((await call('/a')).value('access-control-allow-origin'), isNull, reason: 'no Origin header: not a browser cross-origin read');
    });

    test('several origins, written any way, are all allowed', () async {
      await start(const MockServerConfig(port: 0, allowedOrigin: 'HTTP://Localhost:5173/, https://app.test'));
      expect((await call('/a', origin: 'http://localhost:5173')).value('access-control-allow-origin'), 'http://localhost:5173');
      expect((await call('/a', origin: 'https://app.test')).value('access-control-allow-origin'), 'https://app.test');
      expect((await call('/a', origin: 'https://other.test')).value('access-control-allow-origin'), isNull);
    });

    test('a preflight is answered for an allowed origin and refused to others', () async {
      await start(const MockServerConfig(port: 0, allowedOrigin: 'http://localhost:5173'));
      final ok = await call('/a', method: 'OPTIONS', origin: 'http://localhost:5173', requestHeaders: 'x-token, content-type');
      expect(ok.value('access-control-allow-origin'), 'http://localhost:5173');
      expect(ok.value('access-control-allow-methods'), contains('DELETE'));
      expect(ok.value('access-control-allow-headers'), 'x-token, content-type');
      final denied = await call('/a', method: 'OPTIONS', origin: 'https://evil.example', requestHeaders: 'x-token');
      expect(denied.value('access-control-allow-origin'), isNull);
      expect(denied.value('access-control-allow-methods'), isNull);
      expect(denied.value('access-control-allow-headers'), isNull);
    });

    test('an allowed origin that cannot be read allows nobody', () async {
      await start(const MockServerConfig(port: 0, allowedOrigin: 'not an origin'));
      expect((await call('/a', origin: 'http://localhost:5173')).value('access-control-allow-origin'), isNull);
    });

    test('by default the server only listens on this computer', () async {
      await start(const MockServerConfig(port: 0));
      final port = engine.port!;
      final lan = <InternetAddress>[
        for (final nic in await NetworkInterface.list(type: InternetAddressType.IPv4))
          for (final a in nic.addresses)
            if (!a.isLoopback && !a.isLinkLocal) a,
      ];
      for (final address in lan) {
        await expectLater(
          Socket.connect(address, port, timeout: const Duration(seconds: 2)),
          throwsA(anyOf(isA<SocketException>(), isA<TimeoutException>())),
          reason: 'reachable from the network on ${address.address}',
        );
      }
      expect((await call('/a')).value('x-mock-server'), 'postpilot');
    });
  });

  group('view model', () {
    late AppDatabase db;
    late DriftRepos repos;
    late MockServerViewModel vm;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repos = DriftRepos(db);
      final loader = CollectionLoader(repos.collectionRepository, repos.requestRepository, repos.collectionVariableRepository, repos.collectionAuthRepository);
      vm = MockServerViewModel(BuildMockRoutesUseCase(loader, repos.exampleRepository));
    });
    tearDown(() async {
      await vm.stop();
      vm.dispose();
      await db.close();
    });

    test('CORS allows every website by default, and says so', () {
      expect(vm.allowedOrigin, '*');
      expect(vm.allowsEveryWebsite, isTrue);
      vm.update(origin: 'http://localhost:5173');
      expect(vm.allowsEveryWebsite, isFalse);
      vm.update(origin: ' ');
      expect(vm.allowsEveryWebsite, isTrue);
      vm.update(corsOn: false);
      expect(vm.allowsEveryWebsite, isFalse, reason: 'no CORS, no permission to give');
    });

    test('an allowed origin that is not an origin is refused before the server starts', () async {
      vm.update(collection: 1, port: '3001', origin: 'localhost:5173');
      await vm.start();
      expect(vm.error, contains('Allowed origin must be *'));
      expect(vm.isRunning, isFalse);
      // With CORS off the field is not used, so it is not validated either.
      vm.update(corsOn: false);
      expect(vm.allowsEveryWebsite, isFalse);
    });

    test('the origin reaches the running server', () async {
      final collection = await repos.collectionRepository.createCollection('Shop');
      final request = await addRequest(repos, collection, 'Items', url: '{{b}}/items');
      await repos.exampleRepository.add(ResponseExampleEntity(
        id: 0,
        requestId: request,
        name: 'ok',
        statusCode: 200,
        headers: _realServerHeaders,
        body: '[1]',
        savedAt: DateTime.now(),
      ));
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      vm.update(collection: collection, port: '$port', origin: 'http://localhost:5173');
      await vm.start();
      expect(vm.error, isNull);
      expect(vm.isRunning, isTrue);

      final client = HttpClient();
      Future<String?> allowOriginFor(String origin) async {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/items'));
        req.headers.set('origin', origin);
        final res = await req.close();
        await res.drain<void>();
        return res.headers.value('access-control-allow-origin');
      }

      expect(await allowOriginFor('http://localhost:5173'), 'http://localhost:5173');
      expect(await allowOriginFor('https://evil.example'), isNull);
      client.close(force: true);
    });
  });
}
