// The mock server's decisions with no socket and a clock that does not wait: HEAD and OPTIONS, the 404 and 405 answers,
// every scenario (empty list, 401, 403, 404, 500, slow, flaky, malformed JSON, timeout), live changes, the variants of a
// route with several saved examples, and `{{...}}` in an example.
import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_backend.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_example_handler.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_http.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_routes.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_scenarios.dart';

/// Time that only moves when something waits: every wait is recorded.
final class FakeClock implements MockClock {
  DateTime _now = DateTime.utc(2026, 10, 6);
  final delays = <Duration>[];

  @override
  DateTime now() => _now;

  @override
  Future<void> delay(Duration duration) async {
    delays.add(duration);
    _now = _now.add(duration);
  }
}

const _users = '{"data":[{"id":1},{"id":2},{"id":3}],"total":3,"hasMore":true,"next":"abc"}';

MockSource _source(
  String name,
  String method,
  String url, {
  int status = 200,
  String body = '{"ok":true}',
  String exampleName = 'OK',
  List<MockExample> examples = const [],
  Map<String, String> headers = const {},
}) =>
    MockSource(
      requestName: name,
      method: method,
      url: url,
      exampleStatus: status,
      exampleBody: body,
      exampleHeaders: headers,
      exampleName: exampleName,
      examples: examples,
    );

MockRouteTable _table() => MockRouteTable.from([
      _source('List users', 'GET', '{{b}}/users', body: _users),
      _source('Get user', 'GET', '{{b}}/users/:id', body: '{"id":{{path.id}},"name":"{{query.name}}"}', examples: const [
        MockExample(name: 'Found', status: 200, body: '{"id":{{path.id}},"name":"{{query.name}}"}'),
        MockExample(name: 'Not found', status: 404, body: '{"error":"not_found","id":{{path.id}}}', headers: {'X-Reason': 'gone'}),
        MockExample(name: 'Teapot', status: 418, body: '{"error":"teapot"}'),
      ]),
      _source('Login', 'POST', '{{b}}/login', body: '{"token":"t-1"}', examples: const [
        MockExample(name: 'Success', status: 200, body: '{"token":"t-1"}'),
        MockExample(name: 'Admin', status: 200, body: '{"token":"t-admin"}'),
        MockExample(name: 'Denied', status: 401, body: '{"error":"bad credentials"}'),
      ]),
      _source('Text', 'GET', '{{b}}/text', body: 'hello'),
      _source('Stamp', 'GET', '{{b}}/stamp', body: '{"id":"{{\$guid}}","at":{{\$timestamp}},"iso":"{{\$isoTimestamp}}"}'),
    ]);

MockBackend _backend({FakeClock? clock, Random? random, Duration delay = Duration.zero}) =>
    MockBackend(table: _table(), clock: clock ?? FakeClock(), random: random ?? Random(1), delay: delay);

MockRequest _req(String method, String path, {Map<String, List<String>> query = const {}, Map<String, String> headers = const {}, String body = ''}) =>
    MockRequest(method: method, path: path, query: query, headers: headers, body: body);

Map<String, dynamic> _json(MockOutcome o) => jsonDecode(o.response!.body) as Map<String, dynamic>;

void main() {
  group('answers from saved examples', () {
    test('the example with its status, content type and the mock\'s own header', () async {
      final o = await _backend().handle(_req('GET', '/users'));
      expect(o.route, 'GET /users');
      expect(o.response!.status, 200);
      expect(o.response!.headers['content-type'], 'application/json');
      expect(o.response!.headers['x-mock-server'], 'postpilot');
      expect(o.response!.body, _users);
      expect(o.scenario, isNull);
      final text = await _backend().handle(_req('GET', '/text'));
      expect(text.response!.headers['content-type'], 'text/plain');
    });

    test('no route is a 404 that lists the routes; a wrong method is a 405 that names the right ones', () async {
      final b = _backend();
      final missing = await b.handle(_req('GET', '/nope'));
      expect(missing.response!.status, 404);
      expect(missing.route, isNull);
      expect(_json(missing)['error'], 'No mock for GET /nope');
      expect(_json(missing)['routes'], containsAll(['GET /users', 'POST /login']));
      final wrong = await b.handle(_req('DELETE', '/users'));
      expect(wrong.response!.status, 405);
      expect(_json(wrong)['mockedMethods'], ['GET']);
      expect(wrong.response!.headers['allow'], 'GET, HEAD, OPTIONS');
    });
  });

  group('HEAD and OPTIONS', () {
    test('HEAD is answered from the GET route: the same status and headers, the length of the body, no body to send', () async {
      final o = await _backend().handle(_req('HEAD', '/users'));
      expect(o.headOnly, isTrue);
      expect(o.route, 'GET /users');
      expect(o.response!.status, 200);
      expect(o.response!.headers['content-length'], '${utf8.encode(_users).length}');
      expect(o.response!.headers['content-type'], 'application/json');
    });

    test('HEAD on a path with no GET is a plain 404, not a headers-only answer', () async {
      final o = await _backend().handle(_req('HEAD', '/login'));
      expect(o.headOnly, isFalse);
      expect(o.response!.status, 405);
      final none = await _backend().handle(_req('HEAD', '/nope'));
      expect(none.response!.status, 404);
    });

    test('OPTIONS on a known path lists what is allowed; on an unknown one it is a 404', () async {
      final o = await _backend().handle(_req('OPTIONS', '/users'));
      expect(o.response!.status, 204);
      expect(o.response!.headers['allow'], 'GET, HEAD, OPTIONS');
      expect((await _backend().handle(_req('OPTIONS', '/login'))).response!.headers['allow'], 'OPTIONS, POST');
      expect((await _backend().handle(_req('OPTIONS', '/nope'))).response!.status, 404);
    });
  });

  group('scenarios', () {
    test('401, 403, 404 and 500 answer that status on every route, in a plain error body', () async {
      for (final (kind, status, reason) in [
        (MockScenarioKind.unauthorized, 401, 'Unauthorized'),
        (MockScenarioKind.forbidden, 403, 'Forbidden'),
        (MockScenarioKind.notFound, 404, 'Not Found'),
        (MockScenarioKind.serverError, 500, 'Internal Server Error'),
      ]) {
        final b = _backend()..scenarios.setGlobal(MockScenario(kind));
        final o = await b.handle(_req('GET', '/users'));
        expect(o.response!.status, status, reason: kind.name);
        expect(_json(o), {
          'error': reason,
          'message': 'The mock server is set to answer $reason for this request.',
          'status': status,
        });
        expect(o.scenario, kind.label.toLowerCase());
        // A path that is not even a route fails the same way: the server is "down", not "missing the route".
        expect((await b.handle(_req('GET', '/nope'))).response!.status, status);
      }
    });

    test('a failure uses the saved example with that status when the route has one', () async {
      final b = _backend()..scenarios.setGlobal(const MockScenario(MockScenarioKind.unauthorized));
      final login = await b.handle(_req('POST', '/login'));
      expect(login.response!.status, 401);
      expect(_json(login), {'error': 'bad credentials'});
      final user = await b.handle(_req('GET', '/users/4'));
      expect(user.response!.status, 401, reason: 'no 401 example: the plain body');
      expect(_json(user)['status'], 401);
    });

    test('a route\'s own scenario replaces the global one, and "normal" exempts it', () async {
      final b = _backend()
        ..scenarios.setGlobal(const MockScenario(MockScenarioKind.serverError))
        ..scenarios.setRoute('GET /users', MockScenario.normal);
      expect((await b.handle(_req('GET', '/users'))).response!.status, 200);
      expect((await b.handle(_req('GET', '/text'))).response!.status, 500);
      b.scenarios.setRoute('GET /users', const MockScenario(MockScenarioKind.forbidden));
      expect((await b.handle(_req('GET', '/users'))).response!.status, 403);
      b.scenarios.setRoute('GET /users', null);
      expect((await b.handle(_req('GET', '/users'))).response!.status, 500, reason: 'back to the global scenario');
    });

    test('changes apply to the very next request, and clear() restores normal', () async {
      final b = _backend();
      expect((await b.handle(_req('GET', '/text'))).response!.status, 200);
      b.scenarios.setGlobal(const MockScenario(MockScenarioKind.notFound));
      expect((await b.handle(_req('GET', '/text'))).response!.status, 404);
      b.scenarios.clear();
      expect((await b.handle(_req('GET', '/text'))).response!.status, 200);
      expect(b.scenarios.isAllNormal, isTrue);
    });

    test('empty list: lists in the answer are emptied and the counts that describe them are zero', () async {
      final b = _backend()..scenarios.setRoute('GET /users', const MockScenario(MockScenarioKind.emptyList));
      final o = await b.handle(_req('GET', '/users'));
      expect(o.response!.status, 200);
      expect(_json(o), {'data': <dynamic>[], 'total': 0, 'hasMore': false, 'next': null});
      expect(o.scenario, 'empty list');
      // An object with no list is left alone.
      b.scenarios.setRoute('GET /users/:id', const MockScenario(MockScenarioKind.emptyList));
      expect(_json(await b.handle(_req('GET', '/users/7'))), {'id': 7, 'name': ''});
    });

    test('empty list on a plain array, and the paging headers go with it', () {
      final r = MockBackend.emptyLists(MockResponse.json(200, [1, 2, 3], headers: {'x-total-count': '3', 'link': '<x>; rel="next"'}));
      expect(r.body, '[]');
      expect(r.headers['x-total-count'], '0');
      expect(r.headers.containsKey('link'), isFalse);
      // Not JSON: untouched.
      expect(MockBackend.emptyLists(const MockResponse(200, body: 'plain')).body, 'plain');
    });

    test('malformed JSON: status 200, but the body does not parse', () async {
      final b = _backend()..scenarios.setGlobal(const MockScenario(MockScenarioKind.malformedJson));
      final o = await b.handle(_req('GET', '/users'));
      expect(o.response!.status, 200);
      expect(o.response!.headers['content-type'], 'application/json');
      expect(() => jsonDecode(o.response!.body), throwsFormatException);
      expect(_users.startsWith(o.response!.body), isTrue, reason: 'it is the real body, cut off');
      expect(o.response!.body.length, lessThan(_users.length));
    });

    test('malformed JSON for an answer with no body is still not parseable', () {
      final r = MockBackend.malformed(const MockResponse(204));
      expect(r.status, 200);
      expect(() => jsonDecode(r.body), throwsFormatException);
      // A prefix that happens to be valid JSON (a number) is still broken.
      expect(() => jsonDecode(MockBackend.malformed(const MockResponse(200, body: '1234567890')).body), throwsFormatException);
    });

    test('timeout: no answer at all, immediately, without waiting on the clock', () async {
      final clock = FakeClock();
      final b = _backend(clock: clock)..scenarios.setRoute('GET /text', const MockScenario(MockScenarioKind.timeout));
      final o = await b.handle(_req('GET', '/text'));
      expect(o.neverAnswers, isTrue);
      expect(o.response, isNull);
      expect(o.route, 'GET /text');
      expect(o.scenario, 'timeout');
      expect(clock.delays, isEmpty);
      expect((await b.handle(_req('GET', '/users'))).neverAnswers, isFalse, reason: 'only that route hangs');
    });
  });

  group('slow', () {
    test('a fixed latency waits exactly that long, by the clock, and the elapsed time includes it', () async {
      final clock = FakeClock();
      final b = _backend(clock: clock)..scenarios.setGlobal(const MockScenario.slow(300));
      final o = await b.handle(_req('GET', '/users'));
      expect(clock.delays, [const Duration(milliseconds: 300)]);
      expect(o.elapsed, const Duration(milliseconds: 300));
      expect(o.response!.status, 200);
      expect(o.scenario, 'slow 300 ms (300 ms)');
    });

    test('a range waits min + nextInt(max - min + 1) milliseconds, so the draw is reproducible', () async {
      final clock = FakeClock();
      final b = _backend(clock: clock, random: Random(7))..scenarios.setGlobal(const MockScenario.slow(200, 800));
      await b.handle(_req('GET', '/users'));
      await b.handle(_req('GET', '/users'));
      final dice = Random(7);
      expect(clock.delays, [
        Duration(milliseconds: 200 + dice.nextInt(601)),
        Duration(milliseconds: 200 + dice.nextInt(601)),
      ]);
      expect(clock.delays.every((d) => d.inMilliseconds >= 200 && d.inMilliseconds <= 800), isTrue);
    });

    test('a range given backwards is read as a range', () async {
      final clock = FakeClock();
      final b = _backend(clock: clock)..scenarios.setGlobal(const MockScenario.slow(500, 100));
      await b.handle(_req('GET', '/users'));
      expect(clock.delays.single.inMilliseconds, inInclusiveRange(100, 500));
    });

    test('the server-wide delay adds to a slow scenario, and applies alone without one', () async {
      final clock = FakeClock();
      final b = _backend(clock: clock, delay: const Duration(milliseconds: 50))..scenarios.setRoute('GET /users', const MockScenario.slow(100));
      await b.handle(_req('GET', '/users'));
      await b.handle(_req('GET', '/text'));
      expect(clock.delays, [const Duration(milliseconds: 150), const Duration(milliseconds: 50)]);
    });

    test('no wait is requested when there is nothing to wait for', () async {
      final clock = FakeClock();
      await _backend(clock: clock).handle(_req('GET', '/users'));
      expect(clock.delays, isEmpty);
    });
  });

  group('flaky', () {
    test('every 3rd request fails with the chosen status, the others are normal', () async {
      final b = _backend()..scenarios.setRoute('GET /users', const MockScenario.flaky(every: 3, status: 503));
      final statuses = [for (var i = 0; i < 9; i++) (await b.handle(_req('GET', '/users'))).response!.status];
      expect(statuses, [200, 200, 503, 200, 200, 503, 200, 200, 503]);
    });

    test('a route counts only its own requests: traffic to other routes does not shift the pattern', () async {
      final b = _backend()..scenarios.setRoute('GET /users', const MockScenario.flaky(every: 2));
      final statuses = <int>[];
      for (var i = 0; i < 4; i++) {
        statuses.add((await b.handle(_req('GET', '/users'))).response!.status);
        await b.handle(_req('GET', '/text'));
        await b.handle(_req('GET', '/text'));
      }
      expect(statuses, [200, 500, 200, 500]);
    });

    test('a global flaky scenario counts every request together', () async {
      final b = _backend()..scenarios.setGlobal(const MockScenario.flaky(every: 2));
      final statuses = [
        (await b.handle(_req('GET', '/users'))).response!.status,
        (await b.handle(_req('GET', '/text'))).response!.status,
        (await b.handle(_req('GET', '/users'))).response!.status,
        (await b.handle(_req('GET', '/text'))).response!.status,
      ];
      expect(statuses, [200, 500, 200, 500]);
    });

    test('setting the scenario again starts the count again', () async {
      final b = _backend()..scenarios.setGlobal(const MockScenario.flaky(every: 2));
      await b.handle(_req('GET', '/users'));
      b.scenarios.setGlobal(const MockScenario.flaky(every: 2));
      expect((await b.handle(_req('GET', '/users'))).response!.status, 200, reason: 'the first request since the change');
      expect((await b.handle(_req('GET', '/users'))).response!.status, 500);
    });

    test('X% of requests fail: each one is a draw below that percentage', () async {
      final b = _backend(random: Random(3))..scenarios.setGlobal(const MockScenario.flaky(percent: 50));
      final dice = Random(3);
      final expected = [for (var i = 0; i < 20; i++) dice.nextInt(100) < 50 ? 500 : 200];
      final actual = [for (var i = 0; i < 20; i++) (await b.handle(_req('GET', '/users'))).response!.status];
      expect(actual, expected);
      expect(actual.toSet(), {200, 500}, reason: 'both outcomes occur in twenty draws');
    });

    test('0% never fails and 100% always does; every 1st fails every request', () async {
      Future<List<int>> run(MockScenario s) async {
        final b = _backend(random: Random(1))..scenarios.setGlobal(s);
        return [for (var i = 0; i < 6; i++) (await b.handle(_req('GET', '/users'))).response!.status];
      }

      expect(await run(const MockScenario.flaky(percent: 0)), everyElement(200));
      expect(await run(const MockScenario.flaky(percent: 100)), everyElement(500));
      expect(await run(const MockScenario.flaky(every: 1)), everyElement(500));
    });

    test('the log says which requests failed', () async {
      final b = _backend()..scenarios.setGlobal(const MockScenario.flaky(every: 2));
      expect((await b.handle(_req('GET', '/users'))).scenario, 'flaky (every 2nd, 500): passed');
      expect((await b.handle(_req('GET', '/users'))).scenario, 'flaky (every 2nd, 500): failed');
    });
  });

  group('several saved examples on one route', () {
    test('the first successful example is the default, and the answer names the example', () async {
      final o = await _backend().handle(_req('GET', '/users/5', query: {'name': ['Ann']}));
      expect(o.response!.status, 200);
      expect(o.response!.body, '{"id":5,"name":"Ann"}');
      expect(o.response!.headers['x-mock-example'], 'Found');
    });

    test('?status=404 (or the x-mock-status header) picks the example saved with that status', () async {
      final b = _backend();
      final byQuery = await b.handle(_req('GET', '/users/5', query: {'status': ['404']}));
      expect(byQuery.response!.status, 404);
      expect(byQuery.response!.body, '{"error":"not_found","id":5}');
      expect(byQuery.response!.headers['x-reason'], 'gone');
      expect((await b.handle(_req('GET', '/users/5', headers: {'X-Mock-Status': '418'}))).response!.status, 418);
    });

    test('a status nobody saved leaves the default answer: it may be the app\'s own filter', () async {
      final b = _backend();
      expect((await b.handle(_req('GET', '/users/5', query: {'status': ['500']}))).response!.status, 200);
      expect((await b.handle(_req('GET', '/users/5', query: {'status': ['open']}))).response!.status, 200);
    });

    test('?example=Name picks by name, ignoring case; an unknown name is a 404 that lists the available ones', () async {
      final b = _backend();
      expect((await b.handle(_req('GET', '/users/5', query: {'example': ['not found']}))).response!.status, 404);
      final unknown = await b.handle(_req('GET', '/users/5', query: {'example': ['Nope']}));
      expect(unknown.response!.status, 404);
      expect(_json(unknown)['error'], 'No saved example named "Nope" for GET /users/:id');
      expect(_json(unknown)['available'], [
        {'name': 'Found', 'status': 200},
        {'name': 'Not found', 'status': 404},
        {'name': 'Teapot', 'status': 418},
      ]);
    });

    test('a route with one example ignores ?status and ?example: they may be the app\'s own parameters', () async {
      final b = _backend();
      expect((await b.handle(_req('GET', '/users', query: {'status': ['404'], 'example': ['x']}))).response!.status, 200);
    });

    test('a rule picks an example by a JSON body field, a query parameter or a header, and wins over ?status', () async {
      final b = _backend()
        ..rules = [
          const MockMatchRule(id: 'a', routeKey: 'POST /login', source: MockMatchSource.body, field: 'user.role', equals: 'admin', exampleName: 'Admin'),
          const MockMatchRule(id: 'b', routeKey: 'POST /login', source: MockMatchSource.query, field: 'fail', equals: '1', exampleName: 'Denied'),
          const MockMatchRule(id: 'c', routeKey: 'POST /login', source: MockMatchSource.header, field: 'X-Sso', equals: 'yes', exampleName: 'Admin'),
        ];
      Future<String> token(MockRequest r) async => (_json(await b.handle(r))['token'] ?? _json(await b.handle(r))['error']) as String;

      expect(await token(_req('POST', '/login', body: '{"user":{"role":"admin"}}')), 't-admin');
      expect(await token(_req('POST', '/login', body: '{"user":{"role":"guest"}}')), 't-1');
      expect(await token(_req('POST', '/login', body: 'not json')), 't-1');
      expect((await b.handle(_req('POST', '/login', query: {'fail': ['1']}))).response!.status, 401);
      expect(await token(_req('POST', '/login', headers: {'x-sso': 'yes'})), 't-admin');
      // The first matching rule wins, then ?status.
      expect(await token(_req('POST', '/login', query: {'status': ['401']}, body: '{"user":{"role":"admin"}}')), 't-admin');
      expect((await b.handle(_req('POST', '/login', query: {'status': ['401']}))).response!.status, 401);
    });

    test('a rule that is incomplete, or names an example that is gone, is skipped', () async {
      final b = _backend()
        ..rules = [
          const MockMatchRule(id: 'a', routeKey: 'POST /login', source: MockMatchSource.query, field: '', equals: '', exampleName: 'Admin'),
          const MockMatchRule(id: 'b', routeKey: 'POST /login', source: MockMatchSource.query, field: 'x', equals: '1', exampleName: 'Deleted'),
        ];
      expect(_json(await b.handle(_req('POST', '/login', query: {'x': ['1']})))['token'], 't-1');
    });

    test('a failure scenario picks the example of that status for the route that has one', () async {
      final b = _backend()..scenarios.setRoute('GET /users/:id', const MockScenario(MockScenarioKind.notFound));
      final o = await b.handle(_req('GET', '/users/9'));
      expect(o.response!.body, '{"error":"not_found","id":9}');
    });
  });

  group('{{...}} in an example', () {
    test('the guid, the timestamp from the backend\'s clock, path parameters, query parameters', () async {
      final o = await _backend().handle(_req('GET', '/stamp'));
      final body = _json(o);
      expect(body['id'], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      // The fake clock stands at 2026-10-06T00:00:00Z: 20732 days after the epoch.
      expect(body['at'], 20732 * 86400);
      expect(body['iso'], '2026-10-06T00:00:00.000Z');
      expect(body['id'], isNot(_json(await _backend().handle(_req('GET', '/stamp')))['id']), reason: 'a new guid each time');
      final user = await _backend().handle(_req('GET', '/users/12', query: {'name': ['A "B"']}));
      expect(_json(user), {'id': 12, 'name': 'A "B"'});
    });
  });

  group('the routes the dialog lists', () {
    test('keys, notes and the status of each route', () {
      final routes = {for (final r in _backend().routes) r.key: r};
      expect(routes.keys, containsAll(['GET /users', 'GET /users/:id', 'POST /login', 'GET /text', 'GET /stamp']));
      expect(routes['GET /users/:id']!.note, '3 examples');
      expect(routes['POST /login']!.status, 200);
      expect(routes['GET /users']!.title, 'List users');
    });
  });
}
