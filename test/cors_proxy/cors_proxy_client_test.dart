// The web app's side of the CORS proxy, driven against the real proxy engine over real sockets (no widget binding, see
// cors_proxy_engine_test.dart): the adapter that routes calls, the client that follows redirects through it, the error help and
// the connection test. The adapter is platform-neutral, so the desktop `dart:io` adapter stands in for the browser's.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/network/cors_proxy_adapter.dart';
import 'package:postpilot/core/network/dio_api_client.dart';
import 'package:postpilot/core/network/network_failure.dart';
import 'package:postpilot/features/cors_proxy/data/cors_proxy_engine.dart';
import 'package:postpilot/features/cors_proxy/data/cors_proxy_tester.dart';
import 'package:postpilot/features/cors_proxy/domain/cors_proxy_diagnosis.dart';
import 'package:postpilot/features/cors_proxy/domain/cors_proxy_settings.dart';

const _token = 'client-token-123456';
const _cookies = [
  'sid=abc123; Path=/; Expires=Wed, 21 Oct 2026 07:28:00 GMT; HttpOnly',
  'theme=dark; Path=/; SameSite=Lax',
];

/// Adds an Origin header, which the desktop client never sends but a browser always does.
final class _WithOrigin implements HttpClientAdapter {
  final HttpClientAdapter _inner = IOHttpClientAdapter();
  final String origin;
  _WithOrigin(this.origin);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    options.headers['Origin'] = origin;
    return _inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}

void main() {
  late HttpServer upstream;
  late List<({String method, String path, String query, Map<String, String> headers})> seen;
  late CorsProxyEngine proxy;
  late List<CorsProxyEvent> events;
  CorsProxyRoute? route;
  late DioApiClient client;

  setUp(() async {
    seen = [];
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      final headers = <String, String>{};
      req.headers.forEach((name, values) => headers[name] = values.join(', '));
      seen.add((method: req.method, path: req.uri.path, query: req.uri.query, headers: headers));
      final res = req.response;
      switch (req.uri.path) {
        case '/echo':
          res
            ..headers.set('x-upstream', 'yes')
            ..write(jsonEncode({'path': req.uri.path, 'query': req.uri.query, 'headers': headers}));
        case '/redirect':
          res
            ..statusCode = HttpStatus.found
            ..headers.set('location', '/echo?from=redirect');
        case '/cookies':
          res.headers
            ..add('set-cookie', _cookies[0])
            ..add('set-cookie', _cookies[1]);
          res.write('cookies');
        case '/hang':
          return;
      }
      await res.close();
    });
    proxy = CorsProxyEngine.create();
    await proxy.start(const CorsProxyConfig(token: _token, port: 0));
    events = [];
    proxy.events.listen(events.add);
    route = CorsProxyRoute(Uri.parse('http://127.0.0.1:${proxy.port}'), _token);
    client = DioApiClient(corsProxy: () => route);
  });

  tearDown(() async {
    await proxy.dispose();
    await upstream.close(force: true);
  });

  String target(String path) => 'http://127.0.0.1:${upstream.port}$path';

  Future<ApiHttpResponse> get(String path, {Map<String, String> headers = const {}, ApiRequestOptions options = const ApiRequestOptions(), ApiCancelToken? cancel}) =>
      client.send(ApiRequestSpec(method: 'GET', url: target(path), headers: headers, options: options, cancelToken: cancel));

  Future<NetworkException> failure(Future<ApiHttpResponse> call) async {
    try {
      await call;
    } on NetworkException catch (e) {
      return e;
    }
    fail('expected a NetworkException');
  }

  group('the request the adapter builds', () {
    final base = Uri.parse('http://localhost:8787');

    test('names the proxy, the real address, the token and the redirect request, and keeps the rest', () {
      final original = RequestOptions(
        path: 'https://api.example.com/v1/users?x=1&y=%C3%A9',
        method: 'POST',
        headers: {'Authorization': 'Bearer t', 'Content-Type': 'application/json', 'x-postpilot-url': 'spoofed', 'X-PostPilot-Token': 'spoofed'},
        data: '{"a":1}',
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 7),
      );

      final proxied = CorsProxyAdapter.proxiedOptions(original, CorsProxyRoute(base, 'tok-123456'));

      expect(proxied.uri.toString(), 'http://localhost:8787/v1/users', reason: 'the proxy with the path; the query travels in the header');
      expect(proxied.method, 'POST');
      expect(proxied.data, '{"a":1}');
      expect(proxied.connectTimeout, const Duration(seconds: 5));
      expect(proxied.receiveTimeout, const Duration(seconds: 7));
      expect(proxied.headers['X-PostPilot-Url'], 'https://api.example.com/v1/users?x=1&y=%C3%A9');
      expect(proxied.headers['X-PostPilot-Token'], 'tok-123456');
      expect(proxied.headers['X-PostPilot-Redirects'], 'manual');
      expect(proxied.headers['Authorization'], 'Bearer t');
      expect(proxied.headers['Content-Type'], 'application/json');
      expect(proxied.headers.keys.where((k) => k.toLowerCase() == 'x-postpilot-url'), hasLength(1));
      expect(proxied.headers.keys.where((k) => k.toLowerCase() == 'x-postpilot-token'), hasLength(1));
    });

    test('an address beyond ASCII is percent-encoded, because a header value is ASCII', () {
      final proxied = CorsProxyAdapter.proxiedOptions(RequestOptions(path: 'https://api.example.com/café?q=ü'), CorsProxyRoute(base, ''));

      final header = proxied.headers['X-PostPilot-Url'] as String;
      expect(header.codeUnits.every((u) => u > 0x1f && u < 0x7f), isTrue, reason: header);
      expect(header, startsWith('https://api.example.com/caf%C3%A9'));
      expect(proxied.headers.keys.map((k) => k.toLowerCase()), isNot(contains('x-postpilot-token')), reason: 'no token, none sent');
    });
  });

  group('the answer the adapter restores', () {
    Future<ResponseBody> restore(Map<String, List<String>> headers, {int status = 200, String body = 'x'}) =>
        CorsProxyAdapter.restoreResponse(ResponseBody.fromString(body, status, headers: headers), RequestOptions(path: 'https://api.example.com/x'));

    test('a hidden redirect gets its real status back, with Location, without the proxy headers', () async {
      final restored = await restore({
        'x-postpilot-status': ['302'],
        'x-postpilot-status-text': ['Found'],
        'location': ['/next'],
        'x-postpilot-proxy': ['preflight'],
        'content-type': ['text/plain'],
      });

      expect(restored.statusCode, 302);
      expect(restored.statusMessage, 'Found');
      expect(restored.headers['location'], ['/next']);
      expect(restored.headers['content-type'], ['text/plain']);
      expect(restored.headers.keys.where((k) => k.startsWith('x-postpilot-')), isEmpty);
    });

    test('only a redirect status is restored; nothing else can change the status a call returns', () async {
      expect((await restore({'x-postpilot-status': ['404']})).statusCode, 200);
      expect((await restore({'x-postpilot-status': ['abc']})).statusCode, 200);
      expect((await restore({'x-postpilot-status': ['307']})).statusCode, 307);
    });

    test('the Set-Cookie header comes back as one entry per cookie', () async {
      final restored = await restore({
        'X-PostPilot-Set-Cookie': [CorsProxyProtocol.encodeSetCookies(_cookies)],
      });

      expect(restored.headers['set-cookie'], _cookies);
      expect(restored.headers.keys.where((k) => k.startsWith('x-postpilot-')), isEmpty);
    });

    test('an answer the proxy made itself is thrown as a failure, not shown as the server\'s answer', () async {
      final body = jsonEncode({'error': 'token_invalid', 'message': 'The token is wrong. Paste it.'});

      await expectLater(
        restore({'x-postpilot-proxy-error': ['token_invalid']}, status: 401, body: body),
        throwsA(isA<DioException>().having(
          (e) => e.error,
          'error',
          isA<CorsProxyFailure>().having((f) => f.code, 'code', 'token_invalid').having((f) => f.message, 'message', 'The token is wrong. Paste it.'),
        )),
      );
      await expectLater(
        restore({'x-postpilot-proxy-error': ['upstream_refused']}, status: 502, body: jsonEncode({'message': 'api.example.com refused the connection.'})),
        throwsA(isA<DioException>().having((e) => '${e.error}', 'message', 'The CORS proxy could not forward the call. api.example.com refused the connection.')),
      );
      await expectLater(
        restore({'x-postpilot-proxy-error': ['token_required']}, status: 401, body: 'not json'),
        throwsA(isA<DioException>().having((e) => '${e.error}', 'message', 'The proxy refused the call (token_required).')),
      );
    });
  });

  group('a call through the proxy', () {
    test('reaches the target with its headers and comes back with its answer', () async {
      final response = await get('/echo?x=1', headers: {'X-Custom': 'v', 'Authorization': 'Bearer abc'});

      expect(response.statusCode, 200);
      expect(response.headers['x-upstream'], 'yes');
      final echo = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      expect(echo['query'], 'x=1');
      final sent = echo['headers'] as Map<String, dynamic>;
      expect(sent['x-custom'], 'v');
      expect(sent['authorization'], 'Bearer abc');
      expect(sent.keys.where((k) => k.startsWith('x-postpilot-')), isEmpty);
    });

    test('hands the Set-Cookie lines to the cookie extractors, one per cookie', () async {
      final response = await get('/cookies');

      expect(response.setCookies, _cookies);
    });

    test('follows a redirect hop by hop, each hop through the proxy', () async {
      final response = await get('/redirect');

      expect(response.statusCode, 200);
      expect(response.headers['x-upstream'], 'yes');
      expect(seen.map((s) => s.path), ['/redirect', '/echo']);
      expect(seen.last.query, 'from=redirect');
      for (var i = 0; i < 100 && events.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(events, hasLength(2), reason: 'both hops went through the proxy');
    });

    test('shows the 3xx itself when redirects are not followed', () async {
      final response = await get('/redirect', options: const ApiRequestOptions(followRedirects: false));

      expect(response.statusCode, 302);
      expect(response.headers['location'], '/echo?from=redirect');
      expect(seen, hasLength(1));
    });

    test('with the proxy off, the call goes straight to the target, as before', () async {
      route = null;

      final response = await get('/echo');

      expect(response.statusCode, 200);
      expect(seen.single.headers.keys.where((k) => k.startsWith('x-postpilot-')), isEmpty);
      expect(events, isEmpty);
    });

    test('a call to the proxy itself is not routed through it', () async {
      final response = await client.send(ApiRequestSpec(
        method: 'GET',
        url: 'http://127.0.0.1:${proxy.port}/__postpilot/health',
        headers: const {'X-PostPilot-Token': _token},
      ));

      expect(response.statusCode, 200);
      expect(jsonDecode(utf8.decode(response.bodyBytes)), containsPair('ok', true));
    });

    test('cancelling stops a call the target never answers', () async {
      final cancel = ApiCancelToken();
      final call = failure(get('/hang', cancel: cancel));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      cancel.cancel();

      expect((await call).kind, NetworkErrorKind.cancelled);
    });

    test('the timeout still applies', () async {
      final e = await failure(get('/hang', options: const ApiRequestOptions(timeout: Duration(milliseconds: 300))));

      expect(e.kind, NetworkErrorKind.timeout);
      expect(e.summary, contains('did not answer within 300 ms'));
      expect(e.summary, contains('127.0.0.1:${upstream.port}'), reason: 'the server the call was for, not the proxy');
      expect(e.summary, isNot(contains('${proxy.port}')));
    });
  });

  group('when the proxy cannot be used', () {
    test('a wrong token says so, and points at the proxy settings', () async {
      route = CorsProxyRoute(route!.base, 'a-different-token');

      final e = await failure(get('/echo'));

      expect(e.summary, contains('The token is wrong'));
      expect(e.help, NetworkHelp.corsProxy);
      expect(e.kind, NetworkErrorKind.connectionError);
      expect(seen, isEmpty);
    });

    test('a missing token says so', () async {
      route = CorsProxyRoute(route!.base, '');

      final e = await failure(get('/echo'));

      expect(e.summary, contains('header is missing'));
      expect(e.help, NetworkHelp.corsProxy);
    });

    test('a proxy that is not running says how to start it', () async {
      await proxy.stop();

      final e = await failure(get('/echo'));

      expect(e.summary, allOf(contains('did not answer'), contains('dart run bin/postpilot.dart proxy'), contains('127.0.0.1:')));
      expect(e.help, NetworkHelp.corsProxy);
    });

    test('a target that cannot be reached is told as the proxy\'s news, without the query', () async {
      final spare = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closed = spare.port;
      await spare.close();

      final e = await failure(client.send(ApiRequestSpec(method: 'GET', url: 'http://127.0.0.1:$closed/x?api_key=SUPERSECRETVALUE')));

      expect(e.summary, allOf(startsWith('The CORS proxy could not forward the call.'), contains('127.0.0.1:$closed')));
      expect(e.summary, isNot(contains('SUPERSECRETVALUE')));
      expect('$e', isNot(contains('SUPERSECRETVALUE')));
      expect(e.help, NetworkHelp.corsProxy);
    });
  });

  group('error help', () {
    DioException browserError({DioExceptionType type = DioExceptionType.connectionError, Object? error, String? message}) => DioException(
          requestOptions: RequestOptions(path: 'https://api.example.com/x'),
          type: type,
          error: error,
          message: message ?? 'The XMLHttpRequest onError callback was called. This typically indicates an error on the network layer.',
        );

    test('the browser\'s opaque network error is a CORS block or an unreachable server, with the proxy as the way out', () {
      final e = browserError();

      expect(NetworkFailure.summarize(e, const ApiRequestOptions(), web: true), NetworkFailure.corsBlockedSummary);
      expect(NetworkFailure.corsBlockedSummary, startsWith('The browser blocked this call (CORS) or the server is unreachable'));
      expect(NetworkFailure.helpFor(e, web: true), NetworkHelp.corsBlocked);
    });

    test('outside a browser the same error gets no CORS help', () {
      expect(NetworkFailure.helpFor(browserError(error: const SocketException('Connection refused')), web: false), isNull);
      expect(NetworkFailure.helpFor(browserError(), web: false), isNull);
    });

    test('a failure the browser does explain, or that is not a connection error, gets none', () {
      expect(NetworkFailure.helpFor(browserError(error: const SocketException('Failed host lookup: api.example.com')), web: true), isNull);
      expect(NetworkFailure.helpFor(browserError(type: DioExceptionType.receiveTimeout), web: true), isNull);
      expect(NetworkFailure.helpFor(browserError(type: DioExceptionType.cancel), web: true), isNull);
    });

    test('a failure of the proxy itself is told in its own words, in or out of a browser', () {
      final e = browserError(error: const CorsProxyFailure('token_invalid', 'The token is wrong.'));

      expect(NetworkFailure.summarize(e, const ApiRequestOptions()), 'The token is wrong.');
      expect(NetworkFailure.helpFor(e, web: false), NetworkHelp.corsProxy);
      expect(NetworkFailure.helpFor(e, web: true), NetworkHelp.corsProxy);
    });
  });

  group('connection test', () {
    CorsProxySettings settings({String? token = _token, int? port}) =>
        CorsProxySettings(enabled: true, url: 'http://127.0.0.1:${port ?? proxy.port}', token: token ?? '');

    test('says connected when the proxy answers, and which page it allows', () async {
      final plain = await CorsProxyTester().run(settings());
      expect(plain.kind, CorsProxyTestKind.connected);
      expect(plain.message, contains('answered'));
      expect(plain.message, isNot(contains('allows this page')), reason: 'no Origin, no page');

      final page = await CorsProxyTester(adapter: _WithOrigin('http://localhost:3000')).run(settings());
      expect(page.kind, CorsProxyTestKind.connected);
      expect(page.message, contains('allows this page (http://localhost:3000)'));
    });

    test('tells a missing token, a wrong token and a page that is not allowed apart', () async {
      expect((await CorsProxyTester().run(settings(token: ''))).kind, CorsProxyTestKind.tokenMissing);
      expect((await CorsProxyTester().run(settings(token: 'not-the-token-1'))).kind, CorsProxyTestKind.tokenWrong);

      final origin = await CorsProxyTester(adapter: _WithOrigin('https://evil.example'), pageOrigin: 'https://evil.example').run(settings());
      expect(origin.kind, CorsProxyTestKind.originNotAllowed);
      expect(origin.message, contains('--allow-origin https://evil.example'));
    });

    test('tells a proxy that is not running from one the browser blocked', () async {
      final port = proxy.port!;
      await proxy.stop();

      expect((await CorsProxyTester().run(settings(port: port))).kind, CorsProxyTestKind.notRunning);
      expect((await CorsProxyTester(probe: (_) async => false).run(settings(port: port))).kind, CorsProxyTestKind.notRunning);
      final blocked = await CorsProxyTester(probe: (_) async => true, pageOrigin: 'https://app.example.com').run(settings(port: port));
      expect(blocked.kind, CorsProxyTestKind.blocked);
      expect(blocked.message, contains('--allow-origin https://app.example.com'));
    });

    test('tells another server from the proxy, an unusable address, and silence', () async {
      final other = await CorsProxyTester().run(settings(port: upstream.port));
      expect(other.kind, CorsProxyTestKind.notAProxy);

      final bad = await CorsProxyTester().run(const CorsProxySettings(url: 'ftp://nope'));
      expect(bad.kind, CorsProxyTestKind.invalidUrl);

      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(silent.close);
      silent.listen((_) {});
      final quiet = await CorsProxyTester(timeout: const Duration(milliseconds: 300)).run(settings(port: silent.port));
      expect(quiet.kind, CorsProxyTestKind.timeout);
    });
  });
}
