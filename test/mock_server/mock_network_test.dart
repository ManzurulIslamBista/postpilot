// Network conditions without a socket: what the profiles decide (flapping by a fake clock, loss by a seeded random), and what the
// backend does with the decision (waits, server errors with Retry-After, broken answers, the wire plan for the engine).
import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_backend.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_http.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_network.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_routes.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_scenarios.dart';

/// Time that moves only when told to, or when something waits.
final class _Clock implements MockClock {
  DateTime _now = DateTime.utc(2026, 10, 7);
  final delays = <Duration>[];

  void advance(Duration d) => _now = _now.add(d);

  @override
  DateTime now() => _now;

  @override
  Future<void> delay(Duration duration) async {
    delays.add(duration);
    _now = _now.add(duration);
  }
}

const _body = '{"data":[{"id":1},{"id":2},{"id":3}],"total":3}';

MockRouteTable _table() => MockRouteTable.from([
      const MockSource(requestName: 'List', method: 'GET', url: '{{b}}/users', exampleStatus: 200, exampleBody: _body, exampleName: 'OK'),
      const MockSource(requestName: 'Ping', method: 'GET', url: '{{b}}/ping', exampleStatus: 200, exampleBody: '{"ok":true}', exampleName: 'OK'),
    ]);

MockRequest _get(String path, {String method = 'GET'}) => MockRequest(method: method, path: path);

MockBackend _backend(_Clock clock, {Random? random}) => MockBackend(table: _table(), clock: clock, random: random ?? Random(1));

bool _parses(String s) {
  try {
    jsonDecode(s);
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  group('profiles are data', () {
    test('which profiles do nothing, and a one-line summary of the numbers', () {
      expect(NetworkProfiles.none.isIdle, isTrue);
      expect(const NetworkProfile(id: 'x', name: 'x', errorPercent: 50, errorStatuses: []).isIdle, isTrue, reason: 'errors with no status to answer');
      expect(const NetworkProfile(id: 'x', name: 'x', upSeconds: 10).isIdle, isTrue, reason: 'flapping needs both numbers');
      for (final p in NetworkProfiles.presets) {
        expect(p.isIdle, isFalse, reason: p.name);
        expect(p.summary, isNot('No effect'), reason: p.name);
        expect(NetworkProfiles.byId(p.id), same(p));
      }
      expect(NetworkProfiles.byId('none'), same(NetworkProfiles.none));
      expect(NetworkProfiles.byId('nope'), isNull);
      expect(NetworkProfiles.threeG.summary, 'first byte 300 ms ±25%, 750 kbit/s');
      expect(NetworkProfiles.slowFirstByte.summary, 'first byte 4 s');
      expect(NetworkProfiles.flapping.summary, 'up 10 s, down 5 s');
      expect(NetworkProfiles.serverErrors.summary, '30% 500/502/503 with Retry-After 5 s');
      expect(NetworkProfiles.none.summary, 'No effect');
    });

    test('presets are named and spread the way the task lists them', () {
      expect(NetworkProfiles.presets.map((p) => p.name), [
        'Offline', '2G', '3G', '4G', 'Slow Wi-Fi', 'Lossy', 'Flapping', 'High latency + timeouts', 'Server errors', 'Corrupt answers', 'Slow first byte', 'Slow body',
      ]);
      expect(NetworkProfiles.presets.map((p) => p.id).toSet(), hasLength(NetworkProfiles.presets.length));
      expect(NetworkProfiles.offline.offline, isTrue);
      expect(NetworkProfiles.twoG.bandwidthKbps, lessThan(NetworkProfiles.threeG.bandwidthKbps));
      expect(NetworkProfiles.threeG.bandwidthKbps, lessThan(NetworkProfiles.fourG.bandwidthKbps));
      expect(NetworkProfiles.slowFirstByte.bandwidthKbps, 0, reason: 'a slow first byte is not a slow body');
      expect(NetworkProfiles.slowBody.latencyMs, 0, reason: 'a slow body is not a slow first byte');
    });

    test('copyWith changes what it is given and nothing else', () {
      final p = NetworkProfiles.threeG.copyWith(latencyMs: 450, id: 'custom', name: '3G (edited)');
      expect([p.latencyMs, p.bandwidthKbps, p.jitterPercent, p.id, p.name], [450, 750, 25, 'custom', '3G (edited)']);
    });
  });

  group('MockNetwork.decide', () {
    test('no profile, and "No throttling": nothing applies and no chance is drawn', () {
      final net = MockNetwork(_Clock().now);
      final random = _CountingRandom();
      expect(net.decide('GET /users', random), same(NetworkDecision.none));
      net.setGlobal(NetworkProfiles.none);
      expect(net.decide('GET /users', random), same(NetworkDecision.none));
      expect(random.draws, 0);
      expect(net.isIdle, isTrue);
    });

    test('offline drops the connection', () {
      final net = MockNetwork(_Clock().now)..setGlobal(NetworkProfiles.offline);
      final d = net.decide('GET /users', Random(1));
      expect(d.dropConnection, isTrue);
      expect(d.label, 'Offline: connection dropped');
      expect(d.profile, 'Offline');
      expect(net.isIdle, isFalse);
    });

    test('latency and bandwidth: exact without jitter, kilobit per second turned into bytes per second', () {
      final net = MockNetwork(_Clock().now)..setGlobal(const NetworkProfile(id: 't', name: 'T', latencyMs: 300, bandwidthKbps: 750));
      final d = net.decide(null, Random(1));
      expect(d.latency, const Duration(milliseconds: 300));
      expect(d.bytesPerSecond, 750 * 1000 ~/ 8);
      expect(d.label, 'T: +300 ms, 750 kbit/s');
      expect(d.dropConnection || d.hang || d.errorStatus != null || d.corruption != null || d.truncateAt != null, isFalse);
    });

    test('jitter swings the latency by up to that share either way, reproducibly', () {
      NetworkDecision run(int seed) =>
          (MockNetwork(_Clock().now)..setGlobal(const NetworkProfile(id: 'j', name: 'J', latencyMs: 1000, jitterPercent: 50))).decide(null, Random(seed));
      final swing = (Random(5).nextDouble() * 2 - 1) * 50 / 100;
      expect(run(5).latency, Duration(milliseconds: (1000 * (1 + swing)).round()));
      expect(run(5).latency, run(5).latency);
      for (var seed = 0; seed < 40; seed++) {
        final ms = run(seed).latency.inMilliseconds;
        expect(ms, inInclusiveRange(500, 1500));
      }
      expect({for (var seed = 0; seed < 40; seed++) run(seed).latency.inMilliseconds}.length, greaterThan(20), reason: 'it does vary');
    });

    test('flapping follows the clock: up for N seconds, down for M, over and over, counted from when it was set', () {
      final clock = _Clock();
      final net = MockNetwork(clock.now)..setGlobal(const NetworkProfile(id: 'f', name: 'Flap', upSeconds: 10, downSeconds: 5));
      String state() {
        final d = net.decide('GET /users', Random(1));
        return d.dropConnection ? 'down' : 'up';
      }

      final timeline = <String>[];
      for (final ms in [0, 9999, 10000, 14999, 15000, 24999, 25000, 29999, 30000]) {
        clock._now = DateTime.utc(2026, 10, 7).add(Duration(milliseconds: ms));
        timeline.add('$ms:${state()}');
      }
      expect(timeline, ['0:up', '9999:up', '10000:down', '14999:down', '15000:up', '24999:up', '25000:down', '29999:down', '30000:up']);
      expect(net.decide(null, Random(1)).label, 'Flap: up');

      // Setting it again starts a new cycle: it is up now though it was down a moment ago.
      clock._now = DateTime.utc(2026, 10, 7, 0, 0, 12);
      expect(state(), 'down');
      net.setGlobal(const NetworkProfile(id: 'f', name: 'Flap', upSeconds: 10, downSeconds: 5));
      expect(state(), 'up');
      clock.advance(const Duration(seconds: 10));
      expect(state(), 'down');
    });

    test('a route\'s own profile replaces the whole server\'s; "No throttling" exempts it; null gives it back', () {
      final net = MockNetwork(_Clock().now)..setGlobal(NetworkProfiles.offline);
      net.setRoute('GET /ping', NetworkProfiles.none);
      net.setRoute('GET /slow', const NetworkProfile(id: 's', name: 'S', latencyMs: 100));
      expect(net.decide('GET /ping', Random(1)).dropConnection, isFalse);
      expect(net.decide('GET /slow', Random(1)).dropConnection, isFalse);
      expect(net.decide('GET /slow', Random(1)).latency, const Duration(milliseconds: 100));
      expect(net.decide('GET /users', Random(1)).dropConnection, isTrue);
      expect(net.decide(null, Random(1)).dropConnection, isTrue, reason: 'no route matched: the whole server\'s');
      expect(net.routes.keys, unorderedEquals(['GET /ping', 'GET /slow']));
      net.setRoute('GET /ping', null);
      expect(net.decide('GET /ping', Random(1)).dropConnection, isTrue);
      net.clear();
      expect(net.isIdle, isTrue);
      expect(net.decide('GET /users', Random(1)), same(NetworkDecision.none));
    });

    test('loss: dropped, never answered and cut off at the shares asked for, the same run for the same seed', () {
      const lossy = NetworkProfile(id: 'l', name: 'L', resetPercent: 20, timeoutPercent: 5, truncatePercent: 10);
      List<String> run(int seed, int n) {
        final net = MockNetwork(_Clock().now)..setGlobal(lossy);
        final random = Random(seed);
        return [
          for (var i = 0; i < n; i++)
            () {
              final d = net.decide('GET /users', random);
              return d.dropConnection ? 'drop' : (d.hang ? 'hang' : (d.truncateAt != null ? 'cut' : 'pass'));
            }(),
        ];
      }

      // The first fifty, worked out from the generator itself: one roll for the connection, and a second draw for how far a cut goes.
      final mirror = Random(42);
      final expected = <String>[];
      for (var i = 0; i < 50; i++) {
        final roll = mirror.nextInt(100);
        if (roll < 20) {
          expected.add('drop');
        } else if (roll < 25) {
          expected.add('hang');
        } else if (roll < 35) {
          mirror.nextDouble();
          expected.add('cut');
        } else {
          expected.add('pass');
        }
      }
      expect(run(42, 50), expected);

      final many = run(42, 4000);
      double share(String what) => many.where((s) => s == what).length / many.length * 100;
      expect(share('drop'), closeTo(20, 3));
      expect(share('hang'), closeTo(5, 2));
      expect(share('cut'), closeTo(10, 2.5));
      expect(share('pass'), closeTo(65, 3));
      expect(run(7, 200), run(7, 200));
      expect(run(7, 200), isNot(run(8, 200)));
    });

    test('a cut-off answer is cut between 20% and 80% of the way and says so', () {
      final net = MockNetwork(_Clock().now)..setGlobal(const NetworkProfile(id: 'c', name: 'C', truncatePercent: 100));
      for (var seed = 0; seed < 30; seed++) {
        final d = net.decide('GET /users', Random(seed));
        expect(d.truncateAt, inInclusiveRange(0.2, 0.8));
        expect(d.label, matches(RegExp(r'^C: body cut at \d+%$')));
      }
    });

    test('never answered: no wait either, the connection just stays open', () {
      final net = MockNetwork(_Clock().now)..setGlobal(const NetworkProfile(id: 'h', name: 'H', latencyMs: 6000, timeoutPercent: 100));
      final d = net.decide('GET /users', Random(1));
      expect(d.hang, isTrue);
      expect(d.latency, Duration.zero);
      expect(d.label, 'H: no answer');
    });

    test('server errors: a status from the list, Retry-After when set, and only a share of the requests', () {
      const errors = NetworkProfile(id: 'e', name: 'E', errorPercent: 100, errorStatuses: [502, 503], retryAfterSeconds: 7);
      final net = MockNetwork(_Clock().now)..setGlobal(errors);
      final mirror = Random(1)..nextInt(100);
      final index = mirror.nextInt(2);
      final first = net.decide('GET /users', Random(1));
      expect(first.errorStatus, [502, 503][index]);
      expect(first.retryAfterSeconds, 7);
      expect(first.label, 'E: error ${[502, 503][index]} with Retry-After 7 s');
      final seen = {for (var seed = 0; seed < 60; seed++) net.decide('GET /users', Random(seed)).errorStatus};
      expect(seen, {502, 503});

      final some = MockNetwork(_Clock().now)..setGlobal(NetworkProfiles.serverErrors);
      final random = Random(11);
      final hits = [for (var i = 0; i < 3000; i++) some.decide('GET /users', random).errorStatus != null].where((b) => b).length;
      expect(hits / 3000 * 100, closeTo(30, 3.5));
      final noRetry = MockNetwork(_Clock().now)..setGlobal(errors.copyWith(retryAfterSeconds: 0));
      expect(noRetry.decide('GET /users', Random(1)).retryAfterSeconds, isNull);
    });

    test('corruption picks one of the ticked modes', () {
      final only = MockNetwork(_Clock().now)
        ..setGlobal(const NetworkProfile(id: 'k', name: 'K', corruptPercent: 100, corruptModes: [NetworkCorruption.wrongContentType]));
      final d = only.decide('GET /users', Random(1));
      expect(d.corruption, NetworkCorruption.wrongContentType);
      expect(d.label, 'K: wrong content type');
      final all = MockNetwork(_Clock().now)..setGlobal(NetworkProfiles.corrupt.copyWith(corruptPercent: 100));
      expect({for (var seed = 0; seed < 80; seed++) all.decide('GET /users', Random(seed)).corruption}, NetworkCorruption.values.toSet());
      final off = MockNetwork(_Clock().now)..setGlobal(NetworkProfiles.corrupt.copyWith(corruptModes: const []));
      expect(off.decide('GET /users', Random(1)), same(NetworkDecision.none));
    });
  });

  group('MockBackend with a network', () {
    test('without a profile nothing changes: no wait, no wire plan, no label', () async {
      final clock = _Clock();
      final o = await _backend(clock).handle(_get('/users'));
      expect(o.response!.status, 200);
      expect(o.network, isNull);
      expect(o.wire, isNull);
      expect(o.dropped, isFalse);
      expect(clock.delays, isEmpty);
    });

    test('latency is waited by the clock, on top of the server delay and the scenario; the bandwidth goes to the wire plan', () async {
      final clock = _Clock();
      final b = MockBackend(table: _table(), clock: clock, delay: const Duration(milliseconds: 100))
        ..scenarios.setGlobal(const MockScenario.slow(50))
        ..network.setGlobal(const NetworkProfile(id: 't', name: 'T', latencyMs: 300, bandwidthKbps: 160));
      final o = await b.handle(_get('/users'));
      expect(clock.delays, [const Duration(milliseconds: 450)]);
      expect(o.elapsed, const Duration(milliseconds: 450));
      expect(o.response!.status, 200);
      expect(o.response!.body, _body);
      expect(o.network, 'T: +300 ms, 160 kbit/s');
      expect(o.scenario, 'slow 50 ms (50 ms)');
      expect(o.wire!.bytesPerSecond, 20000);
      expect(o.wire!.truncateAt, isNull);
      expect(o.wire!.declaredLengthExtra, 0);
    });

    test('offline: no answer, marked as dropped (not held open), and the log label says why', () async {
      final b = _backend(_Clock())..network.setGlobal(NetworkProfiles.offline);
      final o = await b.handle(_get('/users'));
      expect(o.response, isNull);
      expect(o.neverAnswers, isTrue);
      expect(o.dropped, isTrue);
      expect(o.route, 'GET /users');
      expect(o.network, 'Offline: connection dropped');
    });

    test('a dropped connection still waits the round trip first', () async {
      final clock = _Clock();
      final b = _backend(clock)..network.setGlobal(const NetworkProfile(id: 'd', name: 'D', latencyMs: 200, resetPercent: 100));
      final o = await b.handle(_get('/users'));
      expect(o.dropped, isTrue);
      expect(clock.delays, [const Duration(milliseconds: 200)]);
      expect(o.network, 'D: connection dropped after +200 ms');
    });

    test('never answered by the network: no answer, not dropped, no wait', () async {
      final clock = _Clock();
      final b = _backend(clock)..network.setGlobal(const NetworkProfile(id: 'h', name: 'H', latencyMs: 6000, timeoutPercent: 100));
      final o = await b.handle(_get('/users'));
      expect(o.neverAnswers, isTrue);
      expect(o.dropped, isFalse);
      expect(clock.delays, isEmpty);
    });

    test('server errors replace the answer, with Retry-After, and keep the mock\'s own header', () async {
      final b = _backend(_Clock())
        ..network.setGlobal(const NetworkProfile(id: 'e', name: 'E', errorPercent: 100, errorStatuses: [503], retryAfterSeconds: 5));
      final o = await b.handle(_get('/users'));
      expect(o.response!.status, 503);
      expect(o.response!.headers['retry-after'], '5');
      expect(o.response!.headers['x-mock-server'], 'postpilot');
      final json = jsonDecode(o.response!.body) as Map<String, dynamic>;
      expect(json['error'], 'Service Unavailable');
      expect(json['message'], contains('simulating a bad network (E)'));
      expect(o.network, 'E: error 503 with Retry-After 5 s');
    });

    test('a scenario that fails the request comes first: the network does not add a second failure', () async {
      final b = _backend(_Clock())
        ..scenarios.setGlobal(const MockScenario(MockScenarioKind.unauthorized))
        ..network.setGlobal(const NetworkProfile(id: 'e', name: 'E', errorPercent: 100, errorStatuses: [503], retryAfterSeconds: 5));
      final o = await b.handle(_get('/users'));
      expect(o.response!.status, 401);
      expect(o.response!.headers.containsKey('retry-after'), isFalse);
    });

    test('corrupt answers: cut-off JSON, a trailing comma, JSON as text/html, a wrong content length', () async {
      Future<MockOutcome> with_(NetworkCorruption mode) =>
          (_backend(_Clock())..network.setGlobal(NetworkProfile(id: 'k', name: 'K', corruptPercent: 100, corruptModes: [mode]))).handle(_get('/users'));

      final cut = await with_(NetworkCorruption.truncatedJson);
      expect(_parses(cut.response!.body), isFalse);
      expect(_body.startsWith(cut.response!.body), isTrue);
      expect(cut.network, 'K: truncated json');

      final comma = await with_(NetworkCorruption.malformedJson);
      expect(_parses(comma.response!.body), isFalse);
      expect(comma.response!.body, '{"data":[{"id":1},{"id":2},{"id":3}],"total":3,}');

      final type = await with_(NetworkCorruption.wrongContentType);
      expect(type.response!.headers['content-type'], 'text/html; charset=utf-8');
      expect(type.response!.headers.keys.where((k) => k.toLowerCase() == 'content-type'), hasLength(1));
      expect(type.response!.body, _body, reason: 'the body itself is fine');
      expect(type.wire, isNull);

      final length = await with_(NetworkCorruption.wrongContentLength);
      expect(length.response!.body, _body);
      expect(length.wire!.declaredLengthExtra, max(16, utf8.encode(_body).length ~/ 2));
      expect(length.wire!.breaksTheBody, isTrue);
    });

    test('broken syntax for an answer with no JSON', () {
      expect(_parses(MockBackend.brokenSyntax(const MockResponse(204)).body), isFalse);
      expect(MockBackend.brokenSyntax(const MockResponse(204)).status, 200);
      expect(_parses(MockBackend.brokenSyntax(const MockResponse(200, body: 'pong')).body), isFalse);
      expect(MockBackend.brokenSyntax(const MockResponse(200, body: '[1,2]')).body, '[1,2,]');
    });

    test('a cut-off body is a wire plan with the share; a HEAD request has no body to cut', () async {
      final b = _backend(_Clock())..network.setGlobal(const NetworkProfile(id: 'c', name: 'C', truncatePercent: 100, bandwidthKbps: 8));
      final o = await b.handle(_get('/users'));
      expect(o.wire!.truncateAt, inInclusiveRange(0.2, 0.8));
      expect(o.wire!.bytesPerSecond, 1000);
      expect(o.network, matches(RegExp(r'^C: 8 kbit/s, body cut at \d+%$')));
      final head = await b.handle(_get('/users', method: 'HEAD'));
      expect(head.headOnly, isTrue);
      expect(head.wire, isNull);
    });

    test('the profile of a route applies to that route only, and flapping uses the backend clock', () async {
      final clock = _Clock();
      final b = _backend(clock)..network.setRoute('GET /ping', const NetworkProfile(id: 'f', name: 'Flap', upSeconds: 10, downSeconds: 5));
      expect((await b.handle(_get('/ping'))).dropped, isFalse);
      expect((await b.handle(_get('/users'))).network, isNull);
      clock.advance(const Duration(seconds: 11));
      expect((await b.handle(_get('/ping'))).dropped, isTrue);
      expect((await b.handle(_get('/users'))).dropped, isFalse, reason: 'another route is not on that network');
      clock.advance(const Duration(seconds: 4));
      expect((await b.handle(_get('/ping'))).dropped, isFalse);
    });
  });
}

/// A generator that counts what is asked of it.
final class _CountingRandom implements Random {
  int draws = 0;

  @override
  bool nextBool() {
    draws++;
    return true;
  }

  @override
  double nextDouble() {
    draws++;
    return 0.5;
  }

  @override
  int nextInt(int max) {
    draws++;
    return 0;
  }
}
