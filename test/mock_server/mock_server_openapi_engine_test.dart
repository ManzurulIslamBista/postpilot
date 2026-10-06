// The mock server over real sockets, serving the OpenAPI shop: an in-process HttpServer on loopback port 0, driven by a real
// HttpClient. Stateful CRUD, HEAD, OPTIONS, the scenarios applied while it runs, the request log with its masking and its
// cURL, and the body size limit. (A separate file from the dialog tests: the widget test binding fakes every HttpClient.)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/mock_server/data/mock_server_engine.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_backend.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_routes.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_scenarios.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_spec.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_spec_handler.dart';
import 'shop_openapi_fixture.dart';

typedef _Reply = ({int status, String body, HttpHeaders headers});

void main() {
  late MockServerEngine engine;
  late HttpClient client;
  late List<MockLogEntry> log;
  late StreamSubscription<MockLogEntry> sub;

  setUp(() {
    engine = MockServerEngine.create();
    client = HttpClient();
    log = [];
  });

  tearDown(() async {
    client.close(force: true);
    await sub.cancel();
    await engine.dispose();
  });

  Future<void> start({MockServerConfig config = const MockServerConfig(port: 0), MockSpecHandler? spec, MockRouteTable? table}) async {
    final backend = MockBackend(table: table ?? const MockRouteTable([], []), spec: spec ?? MockSpecHandler(MockSpec.parse(shopOpenApiJson)));
    await engine.start(config, table ?? const MockRouteTable([], []), backend: backend);
    sub = engine.log.listen(log.add);
  }

  Future<_Reply> call(String method, String path, {Object? json, String? text, Map<String, String> headers = const {}}) async {
    final req = await client.openUrl(method, Uri.parse('http://127.0.0.1:${engine.port}$path'));
    headers.forEach(req.headers.set);
    final payload = text ?? (json == null ? null : jsonEncode(json));
    if (payload != null) {
      if (json != null) req.headers.contentType = ContentType.json;
      req.write(payload);
    }
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return (status: res.statusCode, body: body, headers: res.headers);
  }

  Map<String, dynamic> map(_Reply r) => jsonDecode(r.body) as Map<String, dynamic>;

  Future<void> logged(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (log.length < count && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(log, hasLength(count));
  }

  const base = '/api/v1';

  test('listens on this computer only unless asked: a connection through the local network address is refused', () async {
    await start();
    final others = [
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
        for (final a in i.addresses)
          if (!a.isLoopback) a,
    ];
    if (others.isEmpty) {
      markTestSkipped('This machine has no network address besides loopback to try.');
      return;
    }
    final socket = Socket.connect(others.first, engine.port!, timeout: const Duration(seconds: 2));
    await expectLater(socket, throwsA(isA<SocketException>()));
    expect((await call('GET', '$base/ping')).status, 204, reason: 'while loopback works');
  });

  test('a stateful CRUD sequence over HTTP: create, list, read, replace, patch, delete, missing', () async {
    await start();
    final created = await call('POST', '$base/users', json: {'name': 'Zed', 'email': 'zed@x.io', 'age': 30, 'password': 'hunter2'});
    expect(created.status, 201);
    expect(created.headers.contentType?.mimeType, 'application/json');
    expect(created.headers.value('x-mock-server'), 'postpilot');
    expect(map(created), allOf(containsPair('id', 11), containsPair('name', 'Zed')));
    expect(created.body, isNot(contains('hunter2')));

    final list = await call('GET', '$base/users?page=3&limit=5');
    expect(((map(list)['data']) as List).map((u) => (u as Map)['id']), [11]);
    expect(list.headers.value('x-total-count'), '11');

    expect(map(await call('GET', '$base/users/11'))['email'], 'zed@x.io');
    expect(map(await call('PUT', '$base/users/11', json: {'name': 'Zed Z', 'email': 'z@x.io'}))['name'], 'Zed Z');
    final patched = map(await call('PATCH', '$base/users/11', json: {'age': 41}));
    expect([patched['age'], patched['name']], [41, 'Zed Z']);

    final deleted = await call('DELETE', '$base/users/11');
    expect(deleted.status, 204);
    expect(deleted.body, isEmpty);
    final gone = await call('GET', '$base/users/11');
    expect(gone.status, 404);
    expect(map(gone)['message'], 'No user with id "11".');
    expect(map(await call('GET', '$base/users'))['total'], 10);

    final bad = await call('POST', '$base/users', json: <String, dynamic>{});
    expect(bad.status, 400);
    expect(map(bad)['code'], 400);

    // The reset button: the dialog calls this on the handler the backend serves.
    (engine.backend!.spec!).resetData();
    expect(map(await call('GET', '$base/users'))['total'], 10);
    expect((await call('GET', '$base/users/11')).status, 404);
  });

  test('HEAD is the GET without a body, and its Content-Length is the body\'s length', () async {
    await start();
    final get = await call('GET', '$base/users/me');
    final head = await call('HEAD', '$base/users/me');
    expect(head.status, 200);
    expect(head.body, isEmpty);
    expect(head.headers.value('content-length'), '${utf8.encode(get.body).length}');
    expect(head.headers.contentType?.mimeType, 'application/json');
    expect((await call('HEAD', '$base/nothing')).status, 404);
  });

  test('OPTIONS: a CORS preflight is answered for any path; without CORS it lists what the path allows', () async {
    await start();
    final preflight = await call('OPTIONS', '$base/users', headers: {'Origin': 'http://localhost:5173', 'Access-Control-Request-Method': 'POST', 'Access-Control-Request-Headers': 'content-type'});
    expect(preflight.status, 204);
    expect(preflight.headers.value('access-control-allow-origin'), '*');
    expect(preflight.headers.value('access-control-allow-headers'), 'content-type');
    expect(preflight.headers.value('access-control-allow-methods'), contains('PATCH'));

    await engine.stop();
    await sub.cancel();
    await start(config: const MockServerConfig(port: 0, cors: false));
    final plain = await call('OPTIONS', '$base/users');
    expect(plain.status, 204);
    expect(plain.headers.value('allow'), 'GET, HEAD, OPTIONS, POST');
    expect(plain.headers.value('access-control-allow-origin'), isNull);
    expect((await call('OPTIONS', '$base/nothing')).status, 404);
  });

  test('scenarios apply to the very next request while the server runs: flaky, 401, back to normal', () async {
    await start();
    final scenarios = engine.backend!.scenarios;
    scenarios.setRoute('GET /ping', const MockScenario.flaky(every: 2));
    expect([for (var i = 0; i < 4; i++) (await call('GET', '$base/ping')).status], [204, 500, 204, 500]);
    scenarios.setGlobal(const MockScenario(MockScenarioKind.unauthorized));
    expect((await call('GET', '$base/users')).status, 401);
    // The fifth call to the route is not one of every 2nd: it passes, though the whole server answers 401.
    expect((await call('GET', '$base/ping')).status, 204, reason: 'a route with its own scenario ignores the global one');
    scenarios.clear();
    expect((await call('GET', '$base/users')).status, 200);
  });

  test('slow waits before answering, timeout never answers, and stopping drops the held connection', () async {
    await start();
    final scenarios = engine.backend!.scenarios;
    scenarios.setGlobal(const MockScenario.slow(200));
    final watch = Stopwatch()..start();
    expect((await call('GET', '$base/ping')).status, 204);
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(180));

    scenarios.setGlobal(const MockScenario(MockScenarioKind.timeout));
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:${engine.port}$base/ping'));
    await expectLater(req.close().timeout(const Duration(milliseconds: 400)), throwsA(isA<TimeoutException>()));
    await logged(2);
    expect(log.last.neverAnswered, isTrue);
    expect(log.last.scenario, 'timeout');
    // The server stops although a connection is still open.
    await engine.stop().timeout(const Duration(seconds: 5));
    expect(engine.isRunning, isFalse);
  });

  test('malformed JSON arrives with status 200 and does not parse', () async {
    await start();
    engine.backend!.scenarios.setRoute('GET /users/:id', const MockScenario(MockScenarioKind.malformedJson));
    final r = await call('GET', '$base/users/3');
    expect(r.status, 200);
    expect(() => jsonDecode(r.body), throwsFormatException);
  });

  test('the request log: route, scenario, status and time, with credentials masked and a cURL command that holds none', () async {
    await start();
    engine.backend!.scenarios.setRoute('POST /users', const MockScenario.slow(40));
    const secretKey = 'sk_live_abcdefghijklmnopqrstuv';
    const bearer = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = await call(
      'POST',
      '$base/users?api_key=$secretKey&note=hello',
      json: {'name': 'Ann', 'email': 'ann@example.com', 'password': 'hunter2-secret'},
      headers: {'Authorization': 'Bearer $bearer', 'X-Trace': 'abc'},
    );
    expect(r.status, 201);
    expect(map(r)['name'], 'Ann', reason: 'the server saw the real values');
    await call('GET', '$base/nothing');
    await logged(2);

    final entry = log.firstWhere((e) => e.method == 'POST');
    expect(entry.route, 'POST /users');
    expect(entry.status, 201);
    expect(entry.scenario, 'slow 40 ms (40 ms)');
    expect(entry.duration.inMilliseconds, greaterThanOrEqualTo(30));
    expect(log.firstWhere((e) => e.method == 'GET').route, isNull);

    final everything = [entry.path, entry.requestHeaders.toString(), entry.requestBody, entry.responseBody, entry.toCurl('http://localhost:3001')].join('\n');
    expect(everything, isNot(contains(secretKey)));
    expect(everything, isNot(contains(bearer)));
    expect(everything, isNot(contains('hunter2-secret')));
    expect(entry.path, contains('note=hello'), reason: 'only the secret parameter is masked');
    expect(entry.requestHeaders['authorization'], startsWith('Bearer '));
    expect(entry.requestHeaders['authorization'], contains('••••'));
    expect(entry.requestHeaders['x-trace'], 'abc');
    expect(entry.requestHeaders.containsKey('host'), isFalse);
    expect(entry.requestBody, contains('"name":"Ann"'));

    final curl = entry.toCurl('http://localhost:3001/');
    expect(curl, startsWith("curl --request POST 'http://localhost:3001$base/users?"));
    expect(curl, contains("--header 'x-trace: abc'"));
    expect(curl, contains('--data-raw '));
    expect(entry.preview, contains('"name":"Ann"'));
  });

  test('a body over 1 MB is refused with 413 and not served', () async {
    await start();
    final r = await call('POST', '$base/users', text: '{"name":"${'x' * (1024 * 1024 + 10)}"}', headers: {'Content-Type': 'application/json'});
    expect(r.status, 413);
    expect(map(r)['error'], contains('1 MB'));
    expect((await call('GET', '$base/ping')).status, 204, reason: 'the server is fine afterwards');
  });

  test('examples can be served by the same engine: variants and templates over HTTP', () async {
    final table = MockRouteTable.from([
      const MockSource(
        requestName: 'Get user',
        method: 'GET',
        url: '{{b}}/users/:id',
        exampleStatus: 200,
        exampleBody: '{"id":{{path.id}},"echo":"{{query.q}}"}',
        exampleName: 'Found',
        examples: [
          MockExample(name: 'Found', status: 200, body: '{"id":{{path.id}},"echo":"{{query.q}}"}'),
          MockExample(name: 'Gone', status: 410, body: '{"gone":true}'),
        ],
      ),
    ]);
    final backend = MockBackend(table: table);
    await engine.start(const MockServerConfig(port: 0), table, backend: backend);
    sub = engine.log.listen(log.add);
    final ok = await call('GET', '/users/7?q=hi%20there');
    expect(map(ok), {'id': 7, 'echo': 'hi there'});
    expect(ok.headers.value('x-mock-example'), 'Found');
    final gone = await call('GET', '/users/7?status=410');
    expect(gone.status, 410);
    expect(map(gone), {'gone': true});
    await logged(2);
    expect(log.first.route, 'GET /users/:id');
  });
}
