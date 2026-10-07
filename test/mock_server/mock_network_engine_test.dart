// The network simulator over a real in-process loopback HttpServer, driven by a real HttpClient: the throttled body takes the time
// its bandwidth says, the headers come before a slow body, a dropped or cut-off answer breaks the way a bad link does, and flapping
// follows a fake clock. (A separate file from the widget tests: the widget test binding fakes every HttpClient.)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/mock_server/data/mock_server_engine.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_backend.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_http.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_network.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_routes.dart';

/// A clock that moves when told to (and when something waits on it): the engine's wait for latency costs no real time.
final class _Clock implements MockClock {
  DateTime _now = DateTime.utc(2026, 10, 7);

  void advance(Duration d) => _now = _now.add(d);

  @override
  DateTime now() => _now;

  @override
  Future<void> delay(Duration duration) async => _now = _now.add(duration);
}

/// 6000 bytes of JSON.
final _big = '{"d":"${'x' * 5992}"}';

MockRouteTable _table() => MockRouteTable.from([
      MockSource(requestName: 'Big', method: 'GET', url: '{{b}}/big', exampleStatus: 200, exampleBody: _big, exampleName: 'OK'),
      const MockSource(requestName: 'Ping', method: 'GET', url: '{{b}}/ping', exampleStatus: 200, exampleBody: '{"ok":true}', exampleName: 'OK'),
    ]);

typedef _Reply = ({int? status, HttpHeaders? headers, List<int> bytes, Object? error, int headersMs, int totalMs});

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

  Future<MockBackend> start({MockClock? clock, Random? random}) async {
    final backend = MockBackend(table: _table(), clock: clock ?? const SystemMockClock(), random: random ?? Random(7));
    await engine.start(const MockServerConfig(port: 0), _table(), backend: backend);
    sub = engine.log.listen(log.add);
    return backend;
  }

  /// One request on its own connection (so a closed connection is never retried on another), keeping whatever arrived before an error.
  Future<_Reply> fetch(String path) async {
    final watch = Stopwatch()..start();
    HttpClientResponse? res;
    final bytes = <int>[];
    Object? error;
    var headersMs = -1;
    try {
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:${engine.port}$path'));
      req.persistentConnection = false;
      res = await req.close();
      headersMs = watch.elapsedMilliseconds;
      await for (final chunk in res) {
        bytes.addAll(chunk);
      }
    } catch (e) {
      error = e;
    }
    return (status: res?.statusCode, headers: res?.headers, bytes: bytes, error: error, headersMs: headersMs, totalMs: watch.elapsedMilliseconds);
  }

  Future<void> logged(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (log.length < count && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(log, hasLength(count));
  }

  /// The first request on a fresh server pays for connecting and warming up: make it before anything is timed.
  Future<void> warmUp() async {
    await fetch('/ping');
    await logged(1);
    log.clear();
  }

  test('a throttled body takes the time its bandwidth says, arrives whole, and is logged with the profile and the time', () async {
    final backend = await start();
    await warmUp();
    final baseline = await fetch('/big');
    expect(baseline.error, isNull);
    expect(baseline.bytes, hasLength(6000));

    // 160 kbit/s is 20 000 bytes a second: 6000 bytes in 6 slices of 50 ms.
    backend.network.setGlobal(const NetworkProfile(id: 't', name: 'T', bandwidthKbps: 160));
    final slow = await fetch('/big');
    expect(slow.error, isNull);
    expect(slow.status, 200);
    expect(utf8.decode(slow.bytes), _big);
    expect(slow.headers!.value('content-length'), '6000', reason: 'the length is declared, so the caller can tell a whole body from a cut one');
    expect(slow.totalMs, greaterThanOrEqualTo(250));
    expect(slow.totalMs, lessThan(3000));
    expect(slow.totalMs, greaterThan(baseline.totalMs + 100));

    await logged(2);
    final entry = log.last;
    expect(entry.network, 'T: 160 kbit/s');
    expect(entry.status, 200);
    expect(entry.dropped, isFalse);
    expect(entry.duration.inMilliseconds, greaterThanOrEqualTo(250), reason: 'the log counts the time the body took');
    expect(log.first.network, isNull, reason: 'the first request had no profile');
  });

  test('a slow body is not a slow first byte: the headers arrive at once, the body trickles after them', () async {
    final backend = await start();
    await warmUp();
    backend.network.setGlobal(NetworkProfiles.slowBody.copyWith(bandwidthKbps: 160));
    final r = await fetch('/big');
    expect(r.error, isNull);
    expect(r.headersMs, lessThan(250));
    expect(r.totalMs - r.headersMs, greaterThanOrEqualTo(150));
  });

  test('a slow first byte is the other way round: nothing for a while, then everything at once', () async {
    final backend = await start();
    await warmUp();
    backend.network.setGlobal(const NetworkProfile(id: 'f', name: 'F', latencyMs: 300));
    final r = await fetch('/big');
    expect(r.error, isNull);
    expect(r.headersMs, greaterThanOrEqualTo(280));
    expect(r.totalMs - r.headersMs, lessThan(250));
    expect(utf8.decode(r.bytes), _big);
    await logged(1);
    expect(log.single.network, 'F: +300 ms');
  });

  test('offline: the connection is closed with no answer, the log says dropped, and the server works again once it is off', () async {
    final backend = await start();
    backend.network.setGlobal(NetworkProfiles.offline);
    final r = await fetch('/ping');
    expect(r.status, isNull);
    expect(r.error, anyOf(isA<HttpException>(), isA<SocketException>()));
    await logged(1);
    expect(log.single.dropped, isTrue);
    expect(log.single.neverAnswered, isTrue);
    expect(log.single.network, 'Offline: connection dropped');
    expect(log.single.route, 'GET /ping');

    backend.network.setGlobal(null);
    final back = await fetch('/ping');
    expect(back.status, 200);
    expect(back.error, isNull);
  });

  test('a cut-off body: the caller gets the start of it, then an error, and the log keeps only what was sent', () async {
    final backend = await start();
    backend.network.setGlobal(const NetworkProfile(id: 'c', name: 'C', truncatePercent: 100));
    final r = await fetch('/big');
    expect(r.status, 200, reason: 'the headers were fine');
    expect(r.headers!.value('content-length'), '6000');
    expect(r.error, isNotNull, reason: 'the body ended before its length');
    expect(r.bytes.length, inInclusiveRange(1199, 4800));
    expect(_big.startsWith(utf8.decode(r.bytes)), isTrue);
    await logged(1);
    expect(log.single.network, matches(RegExp(r'^C: body cut at \d+%$')));
    expect(log.single.responseBody.length, lessThan(6000));
    expect(log.single.status, 200);
  });

  test('a wrong content length: every byte arrives, then the caller is left waiting for more and sees the connection close', () async {
    final backend = await start();
    backend.network.setGlobal(const NetworkProfile(id: 'k', name: 'K', corruptPercent: 100, corruptModes: [NetworkCorruption.wrongContentLength]));
    final r = await fetch('/big');
    expect(r.status, 200);
    expect(r.headers!.value('content-length'), '9000', reason: '6000 bytes plus half as many again');
    expect(r.bytes, hasLength(6000));
    expect(r.error, isNotNull);
    await logged(1);
    expect(log.single.network, 'K: wrong content length');
  });

  test('a wrong content type and broken JSON arrive as ordinary answers', () async {
    final backend = await start();
    backend.network.setGlobal(const NetworkProfile(id: 'k', name: 'K', corruptPercent: 100, corruptModes: [NetworkCorruption.wrongContentType]));
    final html = await fetch('/ping');
    expect(html.error, isNull);
    expect(html.headers!.contentType?.mimeType, 'text/html');
    expect(jsonDecode(utf8.decode(html.bytes)), {'ok': true}, reason: 'the body is fine, only its label is wrong');

    backend.network.setGlobal(const NetworkProfile(id: 'k', name: 'K', corruptPercent: 100, corruptModes: [NetworkCorruption.malformedJson]));
    final broken = await fetch('/ping');
    expect(broken.error, isNull);
    expect(broken.status, 200);
    expect(() => jsonDecode(utf8.decode(broken.bytes)), throwsFormatException);
  });

  test('server errors: 503 with Retry-After, from the network and not the route', () async {
    final backend = await start();
    backend.network.setGlobal(const NetworkProfile(id: 'e', name: 'E', errorPercent: 100, errorStatuses: [503], retryAfterSeconds: 5));
    final r = await fetch('/ping');
    expect(r.status, 503);
    expect(r.headers!.value('retry-after'), '5');
    expect(jsonDecode(utf8.decode(r.bytes))['error'], 'Service Unavailable');
    await logged(1);
    expect(log.single.status, 503);
    expect(log.single.network, 'E: error 503 with Retry-After 5 s');
  });

  test('flapping follows the clock, over real sockets: up, down, up', () async {
    final clock = _Clock();
    final backend = await start(clock: clock);
    backend.network.setGlobal(NetworkProfiles.flapping);
    expect((await fetch('/ping')).status, 200);
    clock.advance(const Duration(seconds: 10));
    final down = await fetch('/ping');
    expect(down.status, isNull);
    expect(down.error, isNotNull);
    clock.advance(const Duration(seconds: 5));
    expect((await fetch('/ping')).status, 200);
    await logged(3);
    expect([for (final e in log.reversed) e.dropped], [false, true, false]);
    expect(log.reversed.first.network, 'Flapping: up');
    expect(log[1].network, 'Flapping: down, connection dropped');
  });

  test('loss: exactly the requests a seeded random picks are dropped', () async {
    final backend = await start(random: Random(3));
    backend.network.setGlobal(const NetworkProfile(id: 'l', name: 'L', resetPercent: 25));
    const n = 40;
    final mirror = Random(3);
    final expected = [for (var i = 0; i < n; i++) mirror.nextInt(100) < 25];
    final failed = <bool>[];
    for (var i = 0; i < n; i++) {
      final r = await fetch('/ping');
      failed.add(r.error != null);
      if (r.error == null) expect(r.status, 200);
    }
    expect(failed, expected);
    expect(expected.where((b) => b), isNotEmpty, reason: 'the run does lose some');
    expect(expected.where((b) => !b), isNotEmpty);
    await logged(n);
    expect(log.where((e) => e.dropped), hasLength(expected.where((b) => b).length));
  });

  test('a route with its own network, and stopping the server ends a body that is still trickling', () async {
    final backend = await start();
    backend.network.setRoute('GET /big', const NetworkProfile(id: 's', name: 'S', bandwidthKbps: 8));
    expect((await fetch('/ping')).status, 200, reason: 'only /big is on that network');

    // 8 kbit/s is 1000 bytes a second: the 6000 bytes would take six seconds.
    final slow = fetch('/big');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final watch = Stopwatch()..start();
    await engine.stop().timeout(const Duration(seconds: 5));
    final r = await slow.timeout(const Duration(seconds: 5));
    expect(watch.elapsedMilliseconds, lessThan(3000));
    expect(r.bytes.length, lessThan(6000));
    expect(r.error, isNotNull);
    expect(engine.isRunning, isFalse);
  });
}
