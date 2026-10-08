// Real sockets, no widget binding (it would replace HttpClient with one that answers 400): an upstream server and the proxy
// both listen on port 0 of this computer, and a plain HttpClient plays the browser.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/cors_proxy/data/cors_proxy_engine.dart';

const _token = 'proxy-token-123456';
const _page = 'http://localhost:3000';

/// What the upstream saw of one request.
final class _Seen {
  final String method;
  final String path;
  final String query;
  final Map<String, String> headers;
  final String body;
  _Seen(this.method, this.path, this.query, this.headers, this.body);
}

/// A stand-in for the real API.
final class _Upstream {
  late final HttpServer server;
  final seen = <_Seen>[];
  final gzipBody = gzip.encode(utf8.encode('hello gzip'));

  int get port => server.port;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.defaultResponseHeaders.clear();
    server.listen((req) async {
      final res = req.response;
      final raw = await req.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
      final headers = <String, String>{};
      req.headers.forEach((name, values) => headers[name] = values.join(', '));
      seen.add(_Seen(req.method, req.uri.path, req.uri.query, headers, utf8.decode(raw)));
      switch (req.uri.path) {
        case '/echo':
          final out = utf8.encode(jsonEncode({
            'method': req.method,
            'path': req.uri.path,
            'query': req.uri.query,
            'headers': headers,
            'body': utf8.decode(raw),
          }));
          res
            ..headers.contentType = ContentType.json
            ..headers.set('x-upstream', 'yes')
            ..contentLength = out.length
            ..add(out);
        case '/redirect':
          res
            ..statusCode = HttpStatus.found
            ..headers.set('location', '/echo?from=redirect');
        case '/cookies':
          res.headers
            ..add('set-cookie', 'sid=abc123; Path=/; Expires=Wed, 21 Oct 2026 07:28:00 GMT; HttpOnly')
            ..add('set-cookie', 'theme=dark; Path=/; SameSite=Lax');
          res.write('cookies');
        case '/teapot':
          res
            ..statusCode = 418
            ..reasonPhrase = 'I am a teapot'
            ..write('short and stout');
        case '/gzip':
          res
            ..headers.set('content-encoding', 'gzip')
            ..contentLength = gzipBody.length
            ..add(gzipBody);
        case '/cors':
          res.headers
            ..set('access-control-allow-origin', '*')
            ..set('x-postpilot-proxy-error', 'spoof')
            ..set('x-postpilot-status', '999');
          res.write('ok');
        case '/hang':
          return;
        default:
          res
            ..statusCode = HttpStatus.notFound
            ..write('nothing here');
      }
      await res.close();
    });
  }

  Future<void> stop() => server.close(force: true);
}

final class _Answer {
  final int status;
  final String reason;
  final Map<String, List<String>> headers;
  final List<int> bytes;
  _Answer(this.status, this.reason, this.headers, this.bytes);

  String get body => utf8.decode(bytes);
  String? header(String name) => headers[name.toLowerCase()]?.join(', ');
  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
}

void main() {
  late _Upstream upstream;
  late CorsProxyEngine proxy;
  late HttpClient client;
  late List<CorsProxyEvent> events;
  late StreamSubscription<CorsProxyEvent> eventsSubscription;

  Future<void> startProxy({Duration timeout = const Duration(seconds: 60), List<String> origins = const ['https://app.example.com']}) async {
    proxy = CorsProxyEngine.create();
    await proxy.start(CorsProxyConfig(token: _token, port: 0, allowedOrigins: origins, timeout: timeout));
    events = [];
    eventsSubscription = proxy.events.listen(events.add);
  }

  setUp(() async {
    upstream = _Upstream();
    await upstream.start();
    client = HttpClient()..autoUncompress = false;
    await startProxy();
  });

  tearDown(() async {
    await eventsSubscription.cancel();
    await proxy.dispose();
    client.close(force: true);
    await upstream.stop();
  });

  String target(String path) => 'http://127.0.0.1:${upstream.port}$path';

  /// The headers a web page's call carries: the real address, the token and the page's origin.
  Map<String, String> headers(String? to, {String? origin = _page, String? token = _token, Map<String, String> extra = const {}}) => {
        'X-PostPilot-Url': ?to,
        'X-PostPilot-Token': ?token,
        'Origin': ?origin,
        ...extra,
      };

  Future<_Answer> send(String method, Map<String, String> headers, {List<int>? body, String path = '/', void Function(HttpClientRequest)? tweak}) async {
    final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${proxy.port}$path'));
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    if (body != null) {
      request.contentLength = body.length;
      request.add(body);
    }
    tweak?.call(request);
    final response = await request.close();
    final bytes = await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    final out = <String, List<String>>{};
    response.headers.forEach((name, values) => out[name] = values);
    return _Answer(response.statusCode, response.reasonPhrase, out, bytes);
  }

  /// Events are published after the answer is written, so wait for them.
  Future<void> waitForEvents(int count) async {
    for (var i = 0; i < 100 && events.length < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  group('preflight', () {
    test('is answered by the proxy for an allowed page, with the origin echoed, never *, and no token', () async {
      final answer = await send('OPTIONS', {
        'Origin': _page,
        'Access-Control-Request-Method': 'POST',
        'Access-Control-Request-Headers': 'authorization, content-type, x-postpilot-url, x-postpilot-token',
        'Access-Control-Request-Private-Network': 'true',
      });

      expect(answer.status, 204);
      expect(answer.header('access-control-allow-origin'), _page);
      expect(answer.header('vary'), contains('Origin'));
      expect(answer.header('access-control-allow-headers'), startsWith('*'));
      expect(answer.header('access-control-allow-headers'), contains('authorization'), reason: 'a wildcard never covers Authorization');
      expect(answer.header('access-control-allow-headers'), contains('x-postpilot-url'));
      expect(answer.header('access-control-allow-methods'), allOf(contains('POST'), contains('DELETE'), contains('PATCH')));
      expect(answer.header('access-control-allow-private-network'), 'true');
      expect(answer.header('access-control-max-age'), isNotNull);
      expect(upstream.seen, isEmpty, reason: 'a preflight is never forwarded');
    });

    test('lists a custom method the page asks for', () async {
      final answer = await send('OPTIONS', {'Origin': _page, 'Access-Control-Request-Method': 'PROPFIND'});

      expect(answer.header('access-control-allow-methods'), contains('PROPFIND'));
    });

    test('is refused for a page that is not allowed, with nothing the browser could read', () async {
      final answer = await send('OPTIONS', {'Origin': 'https://evil.example', 'Access-Control-Request-Method': 'GET'});

      expect(answer.status, 403);
      expect(answer.headers.keys, isNot(contains('access-control-allow-origin')));
      expect(answer.json['error'], 'origin_not_allowed');
      expect(answer.json['message'], contains('--allow-origin https://evil.example'));
    });

    test('an OPTIONS call without Access-Control-Request-Method is a real call and is forwarded', () async {
      final answer = await send('OPTIONS', headers(target('/echo')));

      expect(answer.status, 200);
      expect(answer.json['method'], 'OPTIONS');
      expect(upstream.seen.single.method, 'OPTIONS');
    });
  });

  group('forwarding', () {
    test('passes method, path, query, headers and body to the target, and its status, headers and body back', () async {
      final answer = await send(
        'POST',
        headers(target('/echo?page=2&q=a%20b'), extra: {
          'Authorization': 'Bearer abc.def',
          'Content-Type': 'application/json',
          'X-Custom': 'custom-value',
          'Referer': 'http://localhost:3000/app',
          'Sec-Fetch-Mode': 'cors',
          'Access-Control-Request-Method': 'POST',
        }),
        path: '/mirrored/path',
        body: utf8.encode('{"name":"Ada"}'),
      );

      expect(answer.status, 200);
      expect(answer.header('x-upstream'), 'yes');
      final echo = answer.json;
      expect(echo['method'], 'POST');
      expect(echo['path'], '/echo', reason: 'the target decides the path, not the address the page asked the proxy');
      expect(echo['query'], 'page=2&q=a%20b');
      expect(echo['body'], '{"name":"Ada"}');
      final seen = echo['headers'] as Map<String, dynamic>;
      expect(seen['authorization'], 'Bearer abc.def');
      expect(seen['x-custom'], 'custom-value');
      expect(seen['content-type'], 'application/json');
      expect(seen['host'], '127.0.0.1:${upstream.port}');
      for (final page in ['origin', 'referer', 'sec-fetch-mode', 'x-postpilot-url', 'x-postpilot-token', 'access-control-request-method']) {
        expect(seen, isNot(contains(page)), reason: '$page describes the web page, not the call');
      }
      expect(answer.header('access-control-allow-origin'), _page);
      expect(answer.headers['access-control-allow-origin'], hasLength(1));
      expect(answer.header('access-control-expose-headers'), allOf(startsWith('*'), contains('x-upstream')));
      expect(answer.header('access-control-allow-headers'), '*');
    });

    test('tells a cache that the answer depends on the real address, because the page asks only for the proxy and a path', () async {
      final answer = await send('GET', headers(target('/echo?page=2')));

      expect(answer.header('vary'), allOf(contains('Origin'), contains('X-PostPilot-Url')));
    });

    test('forwards every method, and a status with its reason, untouched', () async {
      for (final method in ['GET', 'PUT', 'PATCH', 'DELETE', 'HEAD']) {
        final answer = await send(method, headers(target('/echo')));
        expect(answer.status, 200, reason: method);
      }
      expect(upstream.seen.map((s) => s.method), ['GET', 'PUT', 'PATCH', 'DELETE', 'HEAD']);

      final teapot = await send('GET', headers(target('/teapot')));
      expect(teapot.status, 418);
      expect(teapot.reason, 'I am a teapot');
      expect(teapot.body, 'short and stout');
      final missing = await send('GET', headers(target('/nope')));
      expect(missing.status, 404);
    });

    test('streams a large body through, announced or chunked', () async {
      final big = 'x' * 300000;
      final announced = await send('POST', headers(target('/echo')), body: utf8.encode(big));
      expect((announced.json['body'] as String).length, big.length);

      final chunked = await send('POST', headers(target('/echo')), tweak: (r) {
        r.contentLength = -1;
        r.headers.chunkedTransferEncoding = true;
        r.add(utf8.encode('first-'));
        r.add(utf8.encode('second'));
      });
      expect(chunked.json['body'], 'first-second');
      expect(upstream.seen.last.headers['transfer-encoding'], 'chunked');
    });

    test('a call without an Origin (not a browser) works with the token and gets no CORS headers', () async {
      final answer = await send('GET', headers(target('/echo'), origin: null));

      expect(answer.status, 200);
      expect(answer.headers.keys.where((k) => k.startsWith('access-control-')), isEmpty);
    });

    test('a compressed body is passed on exactly as the target sent it', () async {
      final answer = await send('GET', headers(target('/gzip'), extra: {'Accept-Encoding': 'gzip'}));

      expect(answer.header('content-encoding'), 'gzip');
      expect(answer.bytes, upstream.gzipBody);
      expect(upstream.seen.single.headers['accept-encoding'], 'gzip');
    });

    test('the target cannot spoof the proxy: its CORS and X-PostPilot headers never reach the page', () async {
      final answer = await send('GET', headers(target('/cors')));

      expect(answer.headers['access-control-allow-origin'], [_page]);
      expect(answer.headers.keys, isNot(contains('x-postpilot-proxy-error')));
      expect(answer.headers.keys, isNot(contains('x-postpilot-status')));
    });
  });

  group('what a browser hides', () {
    test('Set-Cookie lines are repeated in one header, whole, with the comma of Expires intact', () async {
      final answer = await send('GET', headers(target('/cookies')));

      expect(CorsProxyProtocol.decodeSetCookies(answer.header('x-postpilot-set-cookie')!), [
        'sid=abc123; Path=/; Expires=Wed, 21 Oct 2026 07:28:00 GMT; HttpOnly',
        'theme=dark; Path=/; SameSite=Lax',
      ]);
      expect(answer.header('access-control-expose-headers'), contains('x-postpilot-set-cookie'));
    });

    test('a redirect is passed on untouched: its status and Location', () async {
      final answer = await send('GET', headers(target('/redirect')));

      expect(answer.status, 302);
      expect(answer.header('location'), '/echo?from=redirect');
      expect(upstream.seen, hasLength(1), reason: 'the proxy does not follow it');
    });

    test('a redirect is shown as a 200 that names its real status when the page asks for it, because a browser would follow a 3xx', () async {
      final answer = await send('GET', headers(target('/redirect'), extra: {'X-PostPilot-Redirects': 'manual'}));

      expect(answer.status, 200);
      expect(answer.header('x-postpilot-status'), '302');
      expect(answer.header('x-postpilot-status-text'), 'Found');
      expect(answer.header('location'), '/echo?from=redirect');
      expect(answer.header('access-control-expose-headers'), contains('x-postpilot-status'));
      expect(upstream.seen, hasLength(1));
    });

    test('another status is not hidden even when the page asks', () async {
      final answer = await send('GET', headers(target('/teapot'), extra: {'X-PostPilot-Redirects': 'manual'}));

      expect(answer.status, 418);
      expect(answer.headers.keys, isNot(contains('x-postpilot-status')));
    });
  });

  group('who may use it', () {
    test('every call but a preflight needs the token', () async {
      final missing = await send('GET', headers(target('/echo'), token: null));
      expect(missing.status, 401);
      expect(missing.header('x-postpilot-proxy-error'), 'token_required');
      expect(missing.header('access-control-allow-origin'), _page, reason: 'so the page can read why');
      expect(missing.json['message'], contains('Settings > CORS proxy'));

      final wrong = await send('GET', headers(target('/echo'), token: 'proxy-token-123457'));
      expect(wrong.status, 401);
      expect(wrong.header('x-postpilot-proxy-error'), 'token_invalid');

      final longer = await send('GET', headers(target('/echo'), token: '$_token-and-more'));
      expect(longer.status, 401);
      expect(upstream.seen, isEmpty);
    });

    test('pages on this computer and the named ones are allowed, any other is refused', () async {
      for (final origin in [
        'http://localhost:5173',
        'http://127.0.0.1:3000',
        'http://[::1]:3000',
        'https://localhost:8443',
        'https://app.example.com',
      ]) {
        final answer = await send('GET', headers(target('/echo'), origin: origin));
        expect(answer.status, 200, reason: origin);
        expect(answer.header('access-control-allow-origin'), origin, reason: origin);
      }
      final before = upstream.seen.length;
      for (final origin in [
        'https://evil.example',
        'null',
        'http://localhost.evil.com',
        'http://127.0.0.1.evil.com',
        'http://app.example.com',
        'https://app.example.com:8443',
      ]) {
        final answer = await send('GET', headers(target('/echo'), origin: origin));
        expect(answer.status, 403, reason: origin);
        expect(answer.header('x-postpilot-proxy-error'), 'origin_not_allowed', reason: origin);
        expect(answer.headers.keys, isNot(contains('access-control-allow-origin')), reason: 'the page must not be able to read it: $origin');
      }
      expect(upstream.seen.length, before, reason: 'nothing of a refused call reaches the target');
    });

    test('an address that names another host than this computer is refused (DNS rebinding)', () async {
      final answer = await send('GET', headers(target('/echo'), origin: null), tweak: (r) => r.headers.host = 'evil.example');

      expect(answer.status, 403);
      expect(answer.header('x-postpilot-proxy-error'), 'host_not_allowed');
      expect(upstream.seen, isEmpty);
    });

    test('the proxy refuses to forward to itself, to a non-http address, or to nothing', () async {
      Future<void> refused(String? to, int status, String code) async {
        final answer = await send('GET', headers(to));
        expect((answer.status, answer.header('x-postpilot-proxy-error')), (status, code), reason: '$to');
      }

      await refused('http://127.0.0.1:${proxy.port}/anything', 508, 'proxy_loop');
      await refused('http://localhost:${proxy.port}/', 508, 'proxy_loop');
      await refused('ftp://example.com/file', 400, 'unsupported_scheme');
      await refused('file:///etc/passwd', 400, 'unsupported_scheme');
      await refused('not a url', 400, 'invalid_target');
      await refused(null, 400, 'missing_target');
      expect(upstream.seen, isEmpty);
    });
  });

  group('health', () {
    test('answers ok with the version and the page that was allowed, and wants the token like every call', () async {
      final ok = await send('GET', headers(null), path: '/__postpilot/health');
      expect(ok.status, 200);
      expect(ok.json, {'ok': true, 'version': CorsProxyProtocol.version, 'allowedOrigin': _page});
      expect(ok.header('access-control-allow-origin'), _page);

      final noToken = await send('GET', headers(null, token: null), path: '/__postpilot/health');
      expect(noToken.status, 401);
      expect(noToken.header('x-postpilot-proxy-error'), 'token_required');

      final noOrigin = await send('GET', headers(null, origin: null), path: '/__postpilot/health');
      expect(noOrigin.json['allowedOrigin'], isNull);
      expect(upstream.seen, isEmpty);
    });

    test('a target whose path is the health path is forwarded, not answered by the proxy', () async {
      final answer = await send('GET', headers(target('/__postpilot/health')));

      expect(answer.status, 404, reason: 'what the upstream says about that path');
      expect(upstream.seen.single.path, '/__postpilot/health');
    });
  });

  group('when the target fails', () {
    test('a server that is not there is a 502 that names it, never the query', () async {
      final spare = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = spare.port;
      await spare.close();

      final answer = await send('GET', headers('http://127.0.0.1:$closedPort/secret/path?api_key=SUPERSECRETVALUE'));

      expect(answer.status, 502);
      expect(answer.header('x-postpilot-proxy-error'), 'upstream_refused');
      expect(answer.header('access-control-allow-origin'), _page);
      expect(answer.json['message'], contains('127.0.0.1:$closedPort'));
      expect(answer.body, isNot(contains('SUPERSECRETVALUE')));
      expect(answer.body, isNot(contains('/secret/path')));
    });

    test('a server that never answers is a 502 after the time limit', () async {
      await eventsSubscription.cancel();
      await proxy.dispose();
      await startProxy(timeout: const Duration(milliseconds: 400));

      final answer = await send('GET', headers(target('/hang')));

      expect(answer.status, 502);
      expect(answer.header('x-postpilot-proxy-error'), 'upstream_timeout');
      expect(answer.json['message'], contains('did not answer'));
    });
  });

  group('what it logs', () {
    test('only METHOD host/path status time, with a secret in the query masked and no header or body', () async {
      await send(
        'POST',
        headers(target('/echo?api_key=SUPERSECRETVALUE&page=2'), extra: {'Authorization': 'Bearer s3cr3t-bearer-token', 'Content-Type': 'text/plain'}),
        body: utf8.encode('password=topsecret-body'),
      );
      await send('GET', headers(target('/echo'), token: 'proxy-token-WRONG0'));
      await waitForEvents(2);

      expect(events, hasLength(2));
      final forwarded = events.first;
      expect(forwarded.line, matches(RegExp(r'^POST 127\.0\.0\.1:\d+/echo\?api_key=.+&page=2 200 \d+ ms$')));
      final all = events.map((e) => e.line).join('\n');
      for (final secret in ['SUPERSECRETVALUE', 's3cr3t-bearer-token', 'Bearer', 'topsecret-body', _token, 'proxy-token-WRONG0']) {
        expect(all, isNot(contains(secret)), reason: secret);
      }
      expect(events.last.status, 401);
      expect(events.last.error, 'token_invalid');
    });

    test('a preflight and a good health check are not logged', () async {
      await send('OPTIONS', {'Origin': _page, 'Access-Control-Request-Method': 'GET'});
      await send('GET', headers(null), path: '/__postpilot/health');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(events, isEmpty);
    });
  });

  group('guessing the token', () {
    const lanToken = 'lan-token-0123456789';

    Future<void> restartOnNetwork() async {
      await eventsSubscription.cancel();
      await proxy.dispose();
      proxy = CorsProxyEngine.create();
      await proxy.start(CorsProxyConfig(token: lanToken, port: 0, host: CorsProxyConfig.allInterfaces, allowedOrigins: const ['https://app.example.com']));
      events = [];
      eventsSubscription = proxy.events.listen(events.add);
    }

    test('a proxy other devices can reach locks a device out after ten wrong tokens, even for the right one', () async {
      await restartOnNetwork();
      for (var i = 0; i < CorsProxyAttempts.maxFailures; i++) {
        final wrong = await send('GET', headers(target('/echo'), token: 'wrong-token-$i-0000'));
        expect(wrong.status, 401, reason: 'attempt $i');
        expect(wrong.header('x-postpilot-proxy-error'), 'token_invalid');
      }

      final locked = await send('GET', headers(target('/echo'), token: lanToken));

      expect(locked.status, 429);
      expect(locked.header('x-postpilot-proxy-error'), 'too_many_attempts');
      expect(upstream.seen, isEmpty);
    });

    test('a right token on the way is not counted against the device', () async {
      await restartOnNetwork();
      for (var i = 0; i < CorsProxyAttempts.maxFailures - 1; i++) {
        await send('GET', headers(target('/echo'), token: 'wrong-token-$i-0000'));
      }
      expect((await send('GET', headers(target('/echo'), token: lanToken))).status, 200);
      for (var i = 0; i < CorsProxyAttempts.maxFailures - 1; i++) {
        await send('GET', headers(target('/echo'), token: 'wrong-again-$i-0000'));
      }
      expect((await send('GET', headers(target('/echo'), token: lanToken))).status, 200);
    });

    test('this computer only is not throttled: a wrong token there is a typo', () async {
      for (var i = 0; i < CorsProxyAttempts.maxFailures + 2; i++) {
        expect((await send('GET', headers(target('/echo'), token: 'wrong-token-$i-0000'))).status, 401);
      }
      expect((await send('GET', headers(target('/echo')))).status, 200);
    });

    test('a short token is refused for a proxy that listens on the network', () async {
      final lan = CorsProxyEngine.create();
      await expectLater(
        lan.start(const CorsProxyConfig(token: 'password1', port: 0, host: CorsProxyConfig.allInterfaces)),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('at least 16'))),
      );
      await lan.dispose();
    });
  });

  group('starting', () {
    test('a token that cannot be used is refused before anything listens', () async {
      final engine = CorsProxyEngine.create();
      addTearDown(engine.dispose);

      await expectLater(
        engine.start(const CorsProxyConfig(token: 'short', port: 0)),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('at least 8'))),
      );
      expect(engine.isRunning, isFalse);
    });

    test('a port that is taken says so', () async {
      final engine = CorsProxyEngine.create();
      addTearDown(engine.dispose);

      await expectLater(
        engine.start(CorsProxyConfig(token: _token, port: upstream.port)),
        throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('${upstream.port}'), contains('already in use')))),
      );
    });

    test('it listens on this computer only unless asked, and says which', () {
      expect(const CorsProxyConfig(token: _token).listensOnAllInterfaces, isFalse);
      expect(const CorsProxyConfig(token: _token, host: CorsProxyConfig.allInterfaces).listensOnAllInterfaces, isTrue);
      expect(const CorsProxyConfig(token: _token).host, '127.0.0.1');
    });

    test('stopping closes the port', () async {
      final port = proxy.port!;
      await proxy.stop();

      expect(proxy.isRunning, isFalse);
      await expectLater(Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 2)), throwsA(isA<SocketException>()));
    });
  });
}
