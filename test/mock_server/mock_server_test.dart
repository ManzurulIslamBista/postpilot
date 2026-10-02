import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/mock_server/data/mock_server_engine.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_routes.dart';

MockSource _src(String name, String method, String url, {int? status = 200, String? body = '{"ok":true}', Map<String, String> headers = const {}}) =>
    MockSource(requestName: name, method: method, url: url, exampleStatus: status, exampleBody: body, exampleHeaders: headers, exampleName: 'ex');

void main() {
  group('MockRouteTable', () {
    test('reduces URLs to paths: variable base, absolute origin, query dropped', () {
      expect(MockRouteTable.pathOfUrl('{{baseUrl}}/users/:id?x=1'), ['users', ':id']);
      expect(MockRouteTable.pathOfUrl('https://api.test:8080/v1/users/{{userId}}'), ['v1', 'users', '{{userId}}']);
      expect(MockRouteTable.pathOfUrl('/plain/path/'), ['plain', 'path']);
      expect(MockRouteTable.pathOfUrl('{{baseUrl}}'), isEmpty);
    });

    test('builds routes from requests with examples and lists the ones without', () {
      final t = MockRouteTable.from([
        _src('List', 'GET', '{{b}}/users'),
        _src('Create', 'post', '{{b}}/users', status: 201),
        _src('No example', 'GET', '{{b}}/ghost', status: null, body: null),
        _src('Duplicate list', 'GET', '{{b}}/users', body: '{"dup":true}'),
      ]);
      expect(t.routes.map((r) => '${r.method} ${r.path}'), ['GET /users', 'POST /users']);
      expect(t.routes.first.body, '{"ok":true}', reason: 'the first of two requests with the same route wins');
      expect(t.skipped, ['No example']);
    });

    test('matches parameters, prefers static segments, ignores query and trailing slash', () {
      final t = MockRouteTable.from([
        _src('One', 'GET', '{{b}}/users/:id', body: '{"route":"param"}'),
        _src('Me', 'GET', '{{b}}/users/me', body: '{"route":"me"}'),
        _src('Posts', 'GET', '{{b}}/users/{{uid}}/posts', body: '{"route":"posts"}'),
      ]);
      expect(t.match('GET', '/users/42')!.body, contains('param'));
      expect(t.match('GET', '/users/me')!.body, contains('me'));
      expect(t.match('get', '/users/7/posts/?page=2')!.body, contains('posts'));
      expect(t.match('POST', '/users/42'), isNull);
      expect(t.match('GET', '/nothing'), isNull);
      expect(t.match('GET', '/users/a%20b')!.requestName, 'One');
    });

    test('reports which methods exist for a path', () {
      final t = MockRouteTable.from([_src('A', 'GET', '/x'), _src('B', 'DELETE', '/x')]);
      expect(t.methodsFor('/x'), unorderedEquals(['GET', 'DELETE']));
      expect(t.methodsFor('/y'), isEmpty);
    });
  });

  group('MockServerEngine (real sockets)', () {
    late MockServerEngine engine;
    final client = HttpClient();

    setUp(() => engine = MockServerEngine.create());
    tearDown(() async => engine.dispose());

    Future<({int status, String body, HttpHeaders headers})> call(String method, String path) async {
      final req = await client.openUrl(method, Uri.parse('http://127.0.0.1:${engine.port}$path'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      return (status: res.statusCode, body: body, headers: res.headers);
    }

    test('serves examples with their status, headers and body, and CORS', () async {
      await engine.start(
        const MockServerConfig(port: 0),
        MockRouteTable.from([
          _src('List', 'GET', '{{b}}/users', body: '[{"id":1}]', headers: {'x-total': '1', 'Content-Length': '999', 'content-encoding': 'gzip'}),
          _src('Create', 'POST', '{{b}}/users', status: 201, body: '{"id":2}'),
          _src('Text', 'GET', '{{b}}/ping', body: 'pong'),
        ]),
      );
      expect(engine.isRunning, isTrue);

      final list = await call('GET', '/users?page=1');
      expect(list.status, 200);
      expect(jsonDecode(list.body), [{'id': 1}]);
      expect(list.headers.value('x-total'), '1');
      expect(list.headers.value('x-mock-server'), 'postpilot');
      expect(list.headers.value('access-control-allow-origin'), '*');
      expect(list.headers.contentType?.mimeType, 'application/json');

      final created = await call('POST', '/users');
      expect(created.status, 201);
      expect((await call('GET', '/ping')).body, 'pong');
      expect((await call('GET', '/ping')).headers.contentType?.mimeType, 'text/plain');
    });

    test('answers 404 and 405 with a helpful body, and OPTIONS preflights', () async {
      await engine.start(const MockServerConfig(port: 0), MockRouteTable.from([_src('List', 'GET', '/users')]));
      final missing = await call('GET', '/nope');
      expect(missing.status, 404);
      expect(jsonDecode(missing.body)['routes'], ['GET /users']);
      final wrongMethod = await call('DELETE', '/users');
      expect(wrongMethod.status, 405);
      expect(jsonDecode(wrongMethod.body)['mockedMethods'], ['GET']);
      final preflight = await call('OPTIONS', '/users');
      expect(preflight.status, 204);
      expect(preflight.headers.value('access-control-allow-methods'), contains('DELETE'));
    });

    test('CORS can be off, routes can be swapped live, and the log records calls', () async {
      await engine.start(const MockServerConfig(port: 0, cors: false), MockRouteTable.from([_src('A', 'GET', '/a', body: '"a"')]));
      final entries = <MockLogEntry>[];
      final sub = engine.log.listen(entries.add);
      final a = await call('GET', '/a');
      expect(a.headers.value('access-control-allow-origin'), isNull);
      engine.updateRoutes(MockRouteTable.from([_src('B', 'GET', '/a', body: '"b"')]));
      expect(jsonDecode((await call('GET', '/a')).body), 'b');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(entries, hasLength(2));
      expect(entries.first.route, 'GET /a');
      expect(entries.first.status, 200);
      await sub.cancel();
    });

    test('stops, and refuses a busy port with a readable message', () async {
      await engine.start(const MockServerConfig(port: 0), const MockRouteTable([], []));
      final port = engine.port!;
      final other = MockServerEngine.create();
      await expectLater(
        other.start(MockServerConfig(port: port), const MockRouteTable([], [])),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('already in use'))),
      );
      await other.dispose();
      await engine.stop();
      expect(engine.isRunning, isFalse);
      expect(engine.port, isNull);
    });
  });
}
