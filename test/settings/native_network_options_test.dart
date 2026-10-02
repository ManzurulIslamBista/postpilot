// Runs the real dart:io adapter against loopback servers, so it needs a VM
// (not the browser). Nothing here leaves the machine.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart' show DioException, HttpClientAdapter, RequestOptions, ResponseBody;
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/network/dio_api_client.dart';
import 'package:postpilot/core/network/http_adapter_config_io.dart';

const _timeout = Duration(seconds: 10);

ApiRequestSpec _get(String url, {ApiRequestOptions options = const ApiRequestOptions(timeout: _timeout)}) =>
    ApiRequestSpec(method: 'GET', url: url, options: options);

bool _opensslInstalled() {
  try {
    return Process.runSync('openssl', ['version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// A throwaway localhost certificate, made with the `openssl` command; the TLS
/// tests are skipped where it is not installed.
Future<SecurityContext?> _selfSignedContext() async {
  final dir = await Directory.systemTemp.createTemp('postpilot_tls_');
  try {
    final result = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', //
      '-keyout', '${dir.path}/key.pem',
      '-out', '${dir.path}/cert.pem',
      '-days', '2',
      '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
    ]);
    if (result.exitCode != 0) return null;
    return SecurityContext()
      ..useCertificateChain('${dir.path}/cert.pem')
      ..usePrivateKey('${dir.path}/key.pem');
  } on ProcessException {
    return null;
  } finally {
    await dir.delete(recursive: true);
  }
}

void main() {
  final servers = <HttpServer>[];
  final sockets = <ServerSocket>[];

  Future<HttpServer> serve(void Function(HttpRequest request) onRequest, {SecurityContext? tls}) async {
    final server = tls == null
        ? await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        : await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, tls);
    servers.add(server);
    server.listen(onRequest, onError: (_) {});
    return server;
  }

  tearDown(() async {
    for (final server in servers) {
      await server.close(force: true);
    }
    for (final socket in sockets) {
      await socket.close();
    }
    servers.clear();
    sockets.clear();
  });

  group('proxyDirectiveFor', () {
    final uri = Uri.parse('https://api.example.com/users');

    test('no proxy is always direct', () {
      expect(proxyDirectiveFor(ProxyConfig.none, uri), 'DIRECT');
    });

    test('the system proxy is what the environment says', () {
      expect(proxyDirectiveFor(ProxyConfig.system, uri), HttpClient.findProxyFromEnvironment(uri));
    });

    test('a custom proxy names its host and port', () {
      const proxy = ProxyConfig(mode: ProxyMode.custom, host: 'proxy.local', port: 3128);

      expect(proxyDirectiveFor(proxy, uri), 'PROXY proxy.local:3128');
    });

    test('credentials travel in the directive, and an IPv6 host is bracketed', () {
      const proxy = ProxyConfig(mode: ProxyMode.custom, host: '::1', port: 3128, username: 'ann', password: 'p@ss:word');

      expect(proxyDirectiveFor(proxy, uri), 'PROXY ann:p@ss:word@[::1]:3128');
    });

    test('credentials with an empty side are left out, since HttpClient would reject them', () {
      const noPassword = ProxyConfig(mode: ProxyMode.custom, host: 'p', port: 1, username: 'ann');
      const noUser = ProxyConfig(mode: ProxyMode.custom, host: 'p', port: 1, password: 'secret');

      expect(proxyDirectiveFor(noPassword, uri), 'PROXY p:1');
      expect(proxyDirectiveFor(noUser, uri), 'PROXY p:1');
    });

    test('credentials dart:io would split apart are refused with a message that does not quote them', () {
      const semicolon = ProxyConfig(mode: ProxyMode.custom, host: 'p', port: 1, username: 'ann', password: 'pa;ss');
      const colon = ProxyConfig(mode: ProxyMode.custom, host: 'p', port: 1, username: 'a:nn', password: 'pass');

      for (final proxy in [semicolon, colon]) {
        expect(
          () => proxyDirectiveFor(proxy, uri),
          throwsA(isA<NetworkException>().having((e) => e.message, 'message', isNot(contains('pass')))),
        );
      }
    });

    test('unsendable credentials do not matter for a request that bypasses the proxy', () {
      const proxy = ProxyConfig(
        mode: ProxyMode.custom,
        host: 'p',
        port: 1,
        username: 'ann',
        password: 'pa;ss',
        bypass: ['example.com'],
      );

      expect(proxyDirectiveFor(proxy, uri), 'DIRECT');
    });

    test('a bypassed host goes direct, and so does a custom proxy with nowhere to connect', () {
      const bypassing = ProxyConfig(mode: ProxyMode.custom, host: 'p', port: 1, bypass: ['*.example.com']);
      const hostless = ProxyConfig(mode: ProxyMode.custom, port: 1);

      expect(proxyDirectiveFor(bypassing, uri), 'DIRECT');
      expect(proxyDirectiveFor(bypassing, Uri.parse('https://other.io/')), 'PROXY p:1');
      expect(proxyDirectiveFor(hostless, uri), 'DIRECT');
    });
  });

  group('requests over the real adapter', () {
    test('a response body arrives whole, headers and status included', () async {
      final server = await serve((request) {
        request.response
          ..statusCode = 201
          ..headers.set('x-answer', '42')
          ..write('hello');
        request.response.close();
      });

      final response = await DioApiClient().send(_get('http://127.0.0.1:${server.port}/'));

      expect(response.statusCode, 201);
      expect(response.headers['x-answer'], '42');
      expect(utf8.decode(response.bodyBytes), 'hello');
      expect(response.truncated, isFalse);
    });

    test('redirects are followed, or shown when following is off', () async {
      final server = await serve((request) {
        if (request.uri.path == '/start') {
          request.response
            ..statusCode = 302
            ..headers.set('location', '/end')
            ..write('moved');
        } else {
          request.response.write('arrived');
        }
        request.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      final client = DioApiClient();

      final followed = await client.send(_get('$base/start'));
      final shown = await client.send(
        _get('$base/start', options: const ApiRequestOptions(timeout: _timeout, followRedirects: false)),
      );

      expect(utf8.decode(followed.bodyBytes), 'arrived');
      expect(shown.statusCode, 302);
      expect(shown.headers['location'], '/end');
    });

    test('an endless redirect stops at the limit with an error', () async {
      final server = await serve((request) {
        request.response
          ..statusCode = 302
          ..headers.set('location', '/again');
        request.response.close();
      });

      await expectLater(
        DioApiClient().send(
          _get('http://127.0.0.1:${server.port}/', options: const ApiRequestOptions(timeout: _timeout, maxRedirects: 4)),
        ),
        throwsA(isA<NetworkException>().having((e) => e.message, 'message', contains('limit 4'))),
      );
    });

    test('a server slower than the timeout is a timeout error', () async {
      final server = await serve((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        try {
          request.response.write('late');
          await request.response.close();
        } catch (_) {}
      });

      await expectLater(
        DioApiClient().send(
          _get('http://127.0.0.1:${server.port}/', options: const ApiRequestOptions(timeout: Duration(milliseconds: 150))),
        ),
        throwsA(isA<NetworkException>().having((e) => e.kind, 'kind', NetworkErrorKind.timeout)),
      );
    });

    test('a huge body is cut at the cap and the connection is closed, not read to the end', () async {
      const chunkCount = 40;
      final chunk = Uint8List(1024 * 1024);
      var sentChunks = 0;
      var clientGone = false;
      final finished = Completer<void>();
      // A raw socket, so the server sees the client hang up whatever HttpServer would report.
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      sockets.add(listener);
      listener.listen((client) async {
        final request = StringBuffer();
        var responding = false;
        Future<void> respond() async {
          try {
            client.write('HTTP/1.1 200 OK\r\nContent-Length: ${chunkCount * chunk.length}\r\n\r\n');
            for (var i = 0; i < chunkCount && !clientGone; i++) {
              client.add(chunk);
              await client.flush();
              sentChunks++;
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            await client.close();
          } catch (_) {
            clientGone = true;
          } finally {
            if (!finished.isCompleted) finished.complete();
          }
        }

        client.listen(
          (data) {
            request.write(latin1.decode(data));
            if (!responding && request.toString().contains('\r\n\r\n')) {
              responding = true;
              unawaited(respond());
            }
          },
          onDone: () => clientGone = true,
          onError: (_) => clientGone = true,
          cancelOnError: true,
        );
      });

      final response = await DioApiClient().send(
        _get('http://127.0.0.1:${listener.port}/', options: const ApiRequestOptions(timeout: _timeout, maxResponseBytes: 1000)),
      );
      await finished.future.timeout(const Duration(seconds: 15));

      expect(response.truncated, isTrue);
      expect(response.sizeBytes, 1000);
      expect(clientGone, isTrue, reason: 'the client should have hung up on the server');
      expect(sentChunks, lessThan(chunkCount), reason: 'the server should not have been able to send everything');
    });

    test('a body under the cap is untouched', () async {
      final server = await serve((request) {
        request.response.write('x' * 500);
        request.response.close();
      });

      final response = await DioApiClient().send(
        _get('http://127.0.0.1:${server.port}/', options: const ApiRequestOptions(timeout: _timeout, maxResponseBytes: 1000)),
      );

      expect(response.truncated, isFalse);
      expect(response.sizeBytes, 500);
    });

    test('the client is still usable after a truncated response', () async {
      final server = await serve((request) {
        request.response.write('y' * 5000);
        request.response.close();
      });
      final client = DioApiClient();
      final url = 'http://127.0.0.1:${server.port}/';

      final cut = await client.send(_get(url, options: const ApiRequestOptions(timeout: _timeout, maxResponseBytes: 100)));
      final whole = await client.send(_get(url));

      expect(cut.truncated, isTrue);
      expect(whole.truncated, isFalse);
      expect(whole.sizeBytes, 5000);
    });
  });

  group('proxy', () {
    test('a custom proxy receives the request, credentials included', () async {
      final seen = <HttpRequest>[];
      final headers = <String, String?>{};
      final proxy = await serve((request) {
        seen.add(request);
        headers['host'] = request.headers.host;
        headers['auth'] = request.headers.value('proxy-authorization');
        request.response.write('via proxy');
        request.response.close();
      });
      final options = ApiRequestOptions(
        timeout: _timeout,
        proxy: ProxyConfig(
          mode: ProxyMode.custom,
          host: '127.0.0.1',
          port: proxy.port,
          username: 'ann',
          password: 'p:ss@word',
        ),
      );

      final response = await DioApiClient().send(_get('http://target.invalid:8081/path?q=1', options: options));

      expect(utf8.decode(response.bodyBytes), 'via proxy');
      expect(seen.single.uri.path, '/path');
      expect(seen.single.uri.query, 'q=1');
      expect(headers['host'], 'target.invalid');
      expect(headers['auth'], 'Basic ${base64Encode(utf8.encode('ann:p:ss@word'))}');
    });

    test('credentials that cannot be sent fail the request with a clear message that does not quote them', () async {
      const proxy = ProxyConfig(mode: ProxyMode.custom, host: '127.0.0.1', port: 9, username: 'ann', password: 'pa;ss');
      final options = ApiRequestOptions(timeout: _timeout, proxy: proxy);

      await expectLater(
        DioApiClient().send(_get('http://target.invalid/', options: options)),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            allOf(contains(ProxyConfig.unsendableCredentialsMessage), isNot(contains('pa;ss'))),
          ),
        ),
      );
    });

    test('a proxy password quoted by a lower layer is masked before the error is shown', () async {
      final client = DioApiClient(
        adapterFactory: ({required verifySsl, required proxy}) =>
            _FailingAdapter('Invalid proxy configuration PROXY ann:s3cret@proxy.local:1, invalid port'),
      );
      const proxy = ProxyConfig(mode: ProxyMode.custom, host: 'proxy.local', port: 1, username: 'ann', password: 's3cret');

      await expectLater(
        client.send(_get('http://target.invalid/', options: const ApiRequestOptions(timeout: _timeout, proxy: proxy))),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            allOf(contains('ann:***@proxy.local:1'), isNot(contains('s3cret'))),
          ),
        ),
      );
    });

    test('a bypassed host is reached directly, not through the proxy', () async {
      var proxied = 0;
      final proxy = await serve((request) {
        proxied++;
        request.response.close();
      });
      final target = await serve((request) {
        request.response.write('direct');
        request.response.close();
      });
      final options = ApiRequestOptions(
        timeout: _timeout,
        proxy: ProxyConfig(mode: ProxyMode.custom, host: '127.0.0.1', port: proxy.port, bypass: const ['127.0.0.1']),
      );

      final response = await DioApiClient().send(_get('http://127.0.0.1:${target.port}/', options: options));

      expect(utf8.decode(response.bodyBytes), 'direct');
      expect(proxied, 0);
    });

    test('changing the proxy applies to the next request without a restart', () async {
      final viaProxy = <String>[];
      final proxy = await serve((request) {
        viaProxy.add(request.headers.host ?? '');
        request.response.write('proxy');
        request.response.close();
      });
      final target = await serve((request) {
        request.response.write('target');
        request.response.close();
      });
      final client = DioApiClient();
      final url = 'http://127.0.0.1:${target.port}/';
      final custom = ApiRequestOptions(
        timeout: _timeout,
        proxy: ProxyConfig(mode: ProxyMode.custom, host: '127.0.0.1', port: proxy.port),
      );

      final first = await client.send(_get(url, options: const ApiRequestOptions(timeout: _timeout, proxy: ProxyConfig.none)));
      final second = await client.send(_get(url, options: custom));
      final third = await client.send(_get(url, options: const ApiRequestOptions(timeout: _timeout, proxy: ProxyConfig.none)));

      expect([first, second, third].map((r) => utf8.decode(r.bodyBytes)), ['target', 'proxy', 'target']);
      expect(viaProxy, ['127.0.0.1']);
    });

    test('an https request sends the proxy credentials on the CONNECT that opens its tunnel', () async {
      final connectHeaders = Completer<String>();
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      sockets.add(socket);
      socket.listen((client) {
        final received = StringBuffer();
        client.listen((data) {
          received.write(latin1.decode(data));
          if (received.toString().contains('\r\n\r\n')) {
            if (!connectHeaders.isCompleted) connectHeaders.complete(received.toString());
            client
              ..write('HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
              ..close();
          }
        }, onError: (_) {});
      });
      final options = ApiRequestOptions(
        timeout: _timeout,
        proxy: ProxyConfig(mode: ProxyMode.custom, host: '127.0.0.1', port: socket.port, username: 'ann', password: 'secret'),
      );

      await expectLater(
        DioApiClient().send(_get('https://secure.invalid/', options: options)),
        throwsA(isA<NetworkException>().having((e) => e.message, 'message', contains('407'))),
      );

      final connect = await connectHeaders.future;
      expect(connect, startsWith('CONNECT secure.invalid:443 '));
      expect(connect.toLowerCase(), contains('proxy-authorization: basic ${base64Encode(utf8.encode('ann:secret'))}'.toLowerCase()));
    });
  });

  group('certificate verification', skip: _opensslInstalled() ? false : 'openssl is not installed', () {
    late SecurityContext tls;

    setUpAll(() async => tls = (await _selfSignedContext())!);

    Future<HttpServer> secureServer() => serve((request) {
          request.response.write('secure');
          request.response.close();
        }, tls: tls);

    test('a self-signed certificate is refused by default and accepted once verification is off', () async {
      final server = await secureServer();
      final url = 'https://127.0.0.1:${server.port}/';
      final client = DioApiClient();

      await expectLater(
        client.send(_get(url)),
        throwsA(isA<NetworkException>().having((e) => e.message, 'message', contains('Verify SSL certificates'))),
      );

      final lax = await client.send(_get(url, options: const ApiRequestOptions(timeout: _timeout, verifySsl: false)));
      expect(utf8.decode(lax.bodyBytes), 'secure');
    });

    test('turning verification back on refuses the same server again, on the same client', () async {
      final server = await secureServer();
      final url = 'https://127.0.0.1:${server.port}/';
      final client = DioApiClient();
      const lax = ApiRequestOptions(timeout: _timeout, verifySsl: false);

      expect((await client.send(_get(url, options: lax))).statusCode, 200);
      await expectLater(client.send(_get(url)), throwsA(isA<NetworkException>()));
      expect((await client.send(_get(url, options: lax))).statusCode, 200);
    });

    test('requests with different settings running at once never share a verification setting', () async {
      final server = await secureServer();
      final url = 'https://127.0.0.1:${server.port}/';
      final client = DioApiClient();

      final outcomes = await Future.wait([
        for (var i = 0; i < 8; i++)
          client
              .send(_get(url, options: ApiRequestOptions(timeout: _timeout, verifySsl: i.isOdd)))
              .then<Object>((r) => r.statusCode, onError: (Object e) => e),
      ]);

      for (var i = 0; i < outcomes.length; i++) {
        if (i.isOdd) {
          expect(outcomes[i], isA<NetworkException>(), reason: 'request $i asked for verification on');
          expect((outcomes[i] as NetworkException).message, isNot(contains('cancelled')));
        } else {
          expect(outcomes[i], 200, reason: 'request $i asked for verification off');
        }
      }
    });
  });
}

/// Stands for `dart:io` rejecting a proxy directive: the error quotes it.
final class _FailingAdapter implements HttpClientAdapter {
  final String message;
  _FailingAdapter(this.message);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      Future.error(DioException(requestOptions: options, error: HttpException(message)));

  @override
  void close({bool force = false}) {}
}
