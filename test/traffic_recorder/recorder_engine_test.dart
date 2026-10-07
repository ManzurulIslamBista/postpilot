// Real sockets on the loopback interface, no network: an in-process upstream HttpServer, the recorder on port 0, and a plain
// HttpClient standing in for the app. (Plain `test`, not `testWidgets`: the widget binding fakes HttpClient away.)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/traffic_recorder/data/recorder_engine.dart';
import 'package:postpilot/features/traffic_recorder/domain/services/lan_addresses.dart';
import 'test_tls_identity.dart';

const _wait = Duration(seconds: 15);

/// What the upstream received.
final class Seen {
  final String method;
  final Uri uri;
  final Map<String, List<String>> headers;
  final Uint8List body;
  final int contentLength;
  final bool chunked;
  Seen(this.method, this.uri, this.headers, this.body, this.contentLength, this.chunked);

  String? header(String name) => headers[name.toLowerCase()]?.join(', ');
}

final class Upstream {
  final HttpServer server;
  final seen = <Seen>[];
  Upstream._(this.server);

  Uri uri(String scheme, [String path = '']) => Uri.parse('$scheme://127.0.0.1:${server.port}$path');

  static Future<Upstream> start(
    Future<void> Function(HttpRequest request, Uint8List body, Upstream self) handle, {
    SecurityContext? tls,
  }) async {
    final server = tls == null
        ? await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        : await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, tls);
    // The Dart server adds x-frame-options and the like; clear them so that what the app receives shows what the recorder adds.
    server.defaultResponseHeaders.clear();
    final upstream = Upstream._(server);
    server.listen((request) async {
      final body = BytesBuilder();
      await for (final chunk in request) {
        body.add(chunk);
      }
      final headers = <String, List<String>>{};
      request.headers.forEach((name, values) => headers[name] = List.of(values));
      upstream.seen.add(Seen(
        request.method,
        request.uri,
        headers,
        body.takeBytes(),
        request.contentLength,
        request.headers.chunkedTransferEncoding,
      ));
      try {
        await handle(request, upstream.seen.last.body, upstream);
      } catch (_) {}
    });
    addTearDown(() => server.close(force: true));
    return upstream;
  }
}


final class Reply {
  final int status;
  final String reason;
  final Map<String, List<String>> headers;
  final Uint8List body;
  final bool chunked;
  Reply(this.status, this.reason, this.headers, this.body, this.chunked);

  String? header(String name) => headers[name.toLowerCase()]?.join(', ');
  String get text => utf8.decode(body);
}

Future<RecorderEngine> startRecorder(RecorderConfig config) async {
  final engine = RecorderEngine.create();
  addTearDown(engine.dispose);
  await engine.start(config);
  return engine;
}

RecorderConfig configFor(Uri upstream, {String host = '127.0.0.1', int maxBodyBytes = RecorderConfig.defaultMaxBodyBytes}) =>
    RecorderConfig(upstream: upstream, host: host, maxBodyBytes: maxBodyBytes);

/// The app: one request to the recorder, the whole answer read.
Future<Reply> send(
  int port,
  String method,
  String path, {
  Map<String, String> headers = const {},
  List<int>? body,
  bool chunked = false,
  String host = '127.0.0.1',
  bool noAcceptEncoding = false,
}) async {
  final client = HttpClient()
    ..autoUncompress = false
    ..userAgent = null;
  try {
    final request = await client.openUrl(method, Uri.parse('http://$host:$port$path'));
    request.followRedirects = false;
    // Dart's client adds Accept-Encoding: gzip by itself; an app that sends none has to be imitated by taking it off.
    if (noAcceptEncoding) request.headers.removeAll(HttpHeaders.acceptEncodingHeader);
    headers.forEach((name, value) => request.headers.set(name, value));
    if (body != null) {
      if (chunked) {
        request.bufferOutput = false;
        request.contentLength = -1;
        request.headers.chunkedTransferEncoding = true;
        final third = (body.length / 3).ceil();
        for (var i = 0; i < body.length; i += third) {
          request.add(body.sublist(i, i + third > body.length ? body.length : i + third));
          await request.flush();
        }
      } else {
        request.contentLength = body.length;
        await request.addStream(Stream.fromIterable([
          for (var i = 0; i < body.length; i += 65536) body.sublist(i, i + 65536 > body.length ? body.length : i + 65536),
        ]));
      }
    }
    final response = await request.close().timeout(_wait);
    final bytes = BytesBuilder();
    await for (final chunk in response.timeout(_wait)) {
      bytes.add(chunk);
    }
    final replyHeaders = <String, List<String>>{};
    response.headers.forEach((name, values) => replyHeaders[name] = List.of(values));
    return Reply(response.statusCode, response.reasonPhrase, replyHeaders, bytes.takeBytes(), response.headers.chunkedTransferEncoding);
  } finally {
    client.close(force: true);
  }
}

/// [send], and the exchange the recorder published for it.
Future<(Reply, RecordedExchange)> call(
  RecorderEngine engine,
  String method,
  String path, {
  Map<String, String> headers = const {},
  List<int>? body,
  bool chunked = false,
  bool noAcceptEncoding = false,
}) async {
  final recorded = engine.exchanges.first.timeout(_wait);
  final reply = await send(engine.port!, method, path, headers: headers, body: body, chunked: chunked, noAcceptEncoding: noAcceptEncoding);
  return (reply, await recorded);
}

Uint8List pattern(int length) => Uint8List.fromList([for (var i = 0; i < length; i++) (i * 31 + i ~/ 251) % 256]);

Future<void> _respond(HttpRequest request, int status, List<int> body, {Map<String, String> headers = const {}}) async {
  request.response.statusCode = status;
  headers.forEach((name, value) => request.response.headers.set(name, value));
  request.response.contentLength = body.length;
  request.response.add(body);
  await request.response.close();
}

void main() {
  group('forwarding', () {
    test('passes method, path, query, headers and body to the upstream and the status, headers and body back', () async {
      final upstream = await Upstream.start((request, body, _) async {
        request.response.statusCode = 201;
        request.response.headers
          ..set('x-custom', 'abc')
          ..add('set-cookie', 'a=1; Path=/')
          ..add('set-cookie', 'b=2; Path=/')
          ..contentType = ContentType.json;
        final answer = utf8.encode('{"ok":true}');
        request.response.contentLength = answer.length;
        request.response.add(answer);
        await request.response.close();
      });
      final engine = await startRecorder(configFor(upstream.uri('http')));
      final payload = utf8.encode('{"name":"Ada"}');

      final (reply, exchange) = await call(
        engine,
        'POST',
        '/api/users/a%20b?page=2&q=a%20b',
        headers: {'authorization': 'Bearer secret-token-123456', 'x-trace': 't1', 'content-type': 'application/json'},
        body: payload,
      );

      final seen = upstream.seen.single;
      expect(seen.method, 'POST');
      expect(seen.uri.path, '/api/users/a%20b');
      expect(seen.uri.query, 'page=2&q=a%20b');
      expect(seen.header('authorization'), 'Bearer secret-token-123456');
      expect(seen.header('x-trace'), 't1');
      expect(seen.header('content-type'), startsWith('application/json'));
      expect(seen.body, payload);
      expect(seen.contentLength, payload.length);

      expect(reply.status, 201);
      expect(reply.reason, 'Created');
      expect(reply.header('x-custom'), 'abc');
      expect(reply.headers['set-cookie'], ['a=1; Path=/', 'b=2; Path=/']);
      expect(reply.text, '{"ok":true}');
      // The Dart server must not add headers the upstream did not send.
      expect(reply.headers.containsKey('x-frame-options'), isFalse);

      expect(exchange.kind, RecordedKind.proxied);
      expect(exchange.method, 'POST');
      expect(exchange.path, '/api/users/a%20b?page=2&q=a%20b');
      expect(exchange.url, 'http://127.0.0.1:${upstream.server.port}/api/users/a%20b?page=2&q=a%20b');
      expect(exchange.status, 201);
      expect(exchange.requestText, '{"name":"Ada"}');
      expect(exchange.requestBodySize, payload.length);
      expect(exchange.responseText, '{"ok":true}');
      expect(exchange.requestHeader('authorization'), 'Bearer secret-token-123456');
      expect(exchange.responseHeader('x-custom'), 'abc');
      expect(exchange.clientAddress, '127.0.0.1');
      expect(exchange.duration, isNot(Duration.zero));
    });

    test('keeps the upstream path prefix in front of the app path', () async {
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, utf8.encode('ok')));
      final engine = await startRecorder(configFor(Uri.parse('http://127.0.0.1:${upstream.server.port}/v2/')));

      final (_, exchange) = await call(engine, 'GET', '/users?x=1');

      expect(upstream.seen.single.uri.path, '/v2/users');
      expect(upstream.seen.single.uri.query, 'x=1');
      expect(exchange.path, '/users?x=1');
      expect(exchange.url, 'http://127.0.0.1:${upstream.server.port}/v2/users?x=1');
    });

    test('does not follow a redirect: the 302 and its Location come back unchanged', () async {
      final upstream = await Upstream.start((request, body, _) async {
        if (request.uri.path == '/old') {
          await _respond(request, 302, const [], headers: {'location': 'https://elsewhere.example/new?x=1'});
        } else {
          await _respond(request, 200, utf8.encode('followed'));
        }
      });
      final engine = await startRecorder(configFor(upstream.uri('http')));

      final (reply, exchange) = await call(engine, 'GET', '/old');

      expect(reply.status, 302);
      expect(reply.header('location'), 'https://elsewhere.example/new?x=1');
      expect(upstream.seen.map((s) => s.uri.path), ['/old']);
      expect(exchange.status, 302);
    });

    test('answers HEAD, 204 and 304 without a body and keeps the announced length of a HEAD', () async {
      final upstream = await Upstream.start((request, _, _) async {
        switch (request.uri.path) {
          case '/head':
            request.response.statusCode = 200;
            request.response.contentLength = 5;
            await request.response.close();
          case '/none':
            request.response.statusCode = 204;
            await request.response.close();
          default:
            request.response.statusCode = 304;
            request.response.headers.set('etag', '"v1"');
            await request.response.close();
        }
      });
      final engine = await startRecorder(configFor(upstream.uri('http')));

      final head = await send(engine.port!, 'HEAD', '/head');
      final none = await send(engine.port!, 'GET', '/none');
      final notModified = await send(engine.port!, 'GET', '/etag', headers: {'if-none-match': '"v1"'});

      expect(head.status, 200);
      expect(head.header('content-length'), '5');
      expect(head.body, isEmpty);
      expect(none.status, 204);
      expect(none.body, isEmpty);
      expect(notModified.status, 304);
      expect(notModified.header('etag'), '"v1"');
      expect(upstream.seen.map((s) => s.method), ['HEAD', 'GET', 'GET']);
    });
  });

  group('Host, Origin and Referer', () {
    test('are rewritten to the upstream address when it is switched on, and only the recorder\'s own address is touched', () async {
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, const []));
      final engine = await startRecorder(configFor(upstream.uri('http')));
      final port = engine.port!;

      await call(engine, 'GET', '/a', headers: {'origin': 'http://10.0.2.2:$port', 'referer': 'http://10.0.2.2:$port/page?x=1'});
      await call(engine, 'GET', '/b', headers: {'origin': 'http://localhost:5173', 'referer': 'https://app.example.com/home'});

      final upstreamAuthority = '127.0.0.1:${upstream.server.port}';
      expect(upstream.seen[0].header('host'), upstreamAuthority);
      expect(upstream.seen[0].header('origin'), 'http://$upstreamAuthority');
      expect(upstream.seen[0].header('referer'), 'http://$upstreamAuthority/page?x=1');
      // A web app's real origin stays, so the upstream's CORS check can still say yes to it.
      expect(upstream.seen[1].header('origin'), 'http://localhost:5173');
      expect(upstream.seen[1].header('referer'), 'https://app.example.com/home');
    });

    test('are passed through untouched when it is switched off', () async {
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, const []));
      final engine = await startRecorder(RecorderConfig(
        upstream: upstream.uri('http'),
        rewriteHostHeaders: false,
      ));
      final port = engine.port!;

      await call(engine, 'GET', '/a', headers: {'origin': 'http://10.0.2.2:$port'});

      expect(upstream.seen.single.header('host'), '127.0.0.1:$port');
      expect(upstream.seen.single.header('origin'), 'http://10.0.2.2:$port');
    });
  });

  group('compression', () {
    const text = '{"items":[1,2,3],"name":"café"}';

    test('a gzip answer reaches the app byte for byte while the recording holds the inflated text', () async {
      final packed = gzip.encode(utf8.encode(text));
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, packed, headers: {'content-encoding': 'gzip', 'content-type': 'application/json'}));
      final engine = await startRecorder(configFor(upstream.uri('http')));

      final (reply, exchange) = await call(engine, 'GET', '/g', headers: {'accept-encoding': 'gzip'});

      expect(reply.body, packed);
      expect(reply.header('content-encoding'), 'gzip');
      expect(reply.header('content-length'), '${packed.length}');
      expect(exchange.responseEncoding, 'gzip');
      expect(exchange.responseBodySize, packed.length);
      expect(exchange.responseText, text);
      expect(exchange.responseUndecoded, isFalse);
      expect(exchange.responseBodyTruncated, isFalse);
    });

    test('a zlib deflate answer and a raw deflate answer are both inflated for the recording', () async {
      final zlibPacked = zlib.encode(utf8.encode(text));
      final rawPacked = ZLibEncoder(raw: true).convert(utf8.encode(text));
      final upstream = await Upstream.start((request, _, _) {
        final body = request.uri.path == '/zlib' ? zlibPacked : rawPacked;
        return _respond(request, 200, body, headers: {'content-encoding': 'deflate', 'content-type': 'application/json'});
      });
      final engine = await startRecorder(configFor(upstream.uri('http')));

      final (zlibReply, zlibExchange) = await call(engine, 'GET', '/zlib');
      final (rawReply, rawExchange) = await call(engine, 'GET', '/raw');

      expect(zlibReply.body, zlibPacked);
      expect(rawReply.body, rawPacked);
      expect(zlibExchange.responseText, text);
      expect(rawExchange.responseText, text);
    });

    test('brotli cannot be inflated: it is passed on untouched and the recording says it could not read it', () async {
      final fake = Uint8List.fromList(List.generate(64, (i) => (i * 7 + 3) % 256));
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, fake, headers: {'content-encoding': 'br', 'content-type': 'application/json'}));
      final engine = await startRecorder(configFor(upstream.uri('http')));

      final (reply, exchange) = await call(engine, 'GET', '/br');

      expect(reply.body, fake);
      expect(exchange.responseUndecoded, isTrue);
      expect(exchange.responseText, isNull);
      expect(exchange.responseBody, fake);
    });

    test('a body that inflates far beyond the cap is cut instead of filling the memory', () async {
      final packed = gzip.encode(List.filled(5 * 1024 * 1024, 0x61));
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, packed, headers: {'content-encoding': 'gzip', 'content-type': 'text/plain'}));
      final engine = await startRecorder(configFor(upstream.uri('http'), maxBodyBytes: 2048));

      final (reply, exchange) = await call(engine, 'GET', '/bomb');

      expect(reply.body, packed);
      expect(exchange.responseBody.length, 2048);
      expect(exchange.responseBodyTruncated, isTrue);
      expect(exchange.responseText, 'a' * 2048);
    });

    test('Accept-Encoding loses brotli and zstd on the way to the upstream unless that is switched off', () async {
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, const []));
      final readable = await startRecorder(configFor(upstream.uri('http')));
      final verbatim = await startRecorder(RecorderConfig(upstream: upstream.uri('http'), keepResponsesReadable: false));

      await call(readable, 'GET', '/1', headers: {'accept-encoding': 'gzip, deflate, br, zstd'});
      await call(readable, 'GET', '/2', headers: {'accept-encoding': 'br'});
      await call(verbatim, 'GET', '/3', headers: {'accept-encoding': 'gzip, br'});

      expect(upstream.seen[0].header('accept-encoding'), 'gzip, deflate');
      expect(upstream.seen[1].header('accept-encoding'), 'identity');
      expect(upstream.seen[2].header('accept-encoding'), 'gzip, br');
    });

    test('an app that sends no Accept-Encoding is not made to accept gzip (Dart\'s client would add it by itself)', () async {
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, const []));
      final readable = await startRecorder(configFor(upstream.uri('http')));
      final verbatim = await startRecorder(RecorderConfig(upstream: upstream.uri('http'), keepResponsesReadable: false));

      await call(readable, 'GET', '/1', noAcceptEncoding: true);
      await call(verbatim, 'GET', '/2', noAcceptEncoding: true);

      expect(upstream.seen[0].headers.containsKey('accept-encoding'), isFalse);
      expect(upstream.seen[1].headers.containsKey('accept-encoding'), isFalse);
    });
  });

  group('streaming', () {
    test('a chunked answer is streamed: the first chunk reaches the app while the upstream is still sending', () async {
      final gate = Completer<void>();
      final upstream = await Upstream.start((request, _, _) async {
        request.response.bufferOutput = false;
        request.response.headers.contentType = ContentType.text;
        request.response.add(utf8.encode('first;'));
        await request.response.flush();
        await gate.future;
        request.response.add(utf8.encode('second;'));
        await request.response.flush();
        request.response.add(utf8.encode('third'));
        await request.response.close();
      });
      final engine = await startRecorder(configFor(upstream.uri('http')));
      final recorded = engine.exchanges.first.timeout(_wait);

      final client = HttpClient()..autoUncompress = false;
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:${engine.port}/stream'));
      final response = await request.close().timeout(_wait);
      final received = StringBuffer();
      var openedGate = false;
      await for (final chunk in response.timeout(_wait)) {
        received.write(utf8.decode(chunk));
        if (!openedGate) {
          // Proof of streaming: the app is already reading while the upstream waits for this very moment.
          openedGate = true;
          gate.complete();
        }
      }

      expect(response.headers.chunkedTransferEncoding, isTrue);
      expect(response.contentLength, -1);
      expect(received.toString(), 'first;second;third');
      final exchange = await recorded;
      expect(exchange.responseText, 'first;second;third');
    });

    test('a chunked request body is forwarded chunked and recorded whole', () async {
      final upstream = await Upstream.start((request, body, _) => _respond(request, 200, body));
      final engine = await startRecorder(configFor(upstream.uri('http')));
      final payload = utf8.encode('chunked upload ' * 100);

      final (reply, exchange) = await call(engine, 'POST', '/upload', body: payload, chunked: true);

      final seen = upstream.seen.single;
      expect(seen.chunked, isTrue);
      expect(seen.contentLength, -1);
      expect(seen.body, payload);
      expect(reply.body, payload);
      expect(exchange.requestBody, payload);
      expect(exchange.requestBodySize, payload.length);
    });

    test('a large body goes through unchanged in both directions while the recording stays at the cap', () async {
      final upstream = await Upstream.start((request, body, _) => _respond(request, 200, body, headers: {'content-type': 'application/octet-stream'}));
      final engine = await startRecorder(configFor(upstream.uri('http'), maxBodyBytes: 1024));
      final payload = pattern(3 * 1024 * 1024 + 17);

      final (reply, exchange) = await call(engine, 'POST', '/echo', body: payload, headers: {'content-type': 'application/octet-stream'});

      expect(upstream.seen.single.body.length, payload.length);
      expect(reply.body.length, payload.length);
      var identical = true;
      for (var i = 0; i < payload.length && identical; i++) {
        identical = reply.body[i] == payload[i] && upstream.seen.single.body[i] == payload[i];
      }
      expect(identical, isTrue);
      expect(exchange.requestBodySize, payload.length);
      expect(exchange.requestBody.length, 1024);
      expect(exchange.requestBody, payload.sublist(0, 1024));
      expect(exchange.requestBodyTruncated, isTrue);
      expect(exchange.responseBodySize, payload.length);
      expect(exchange.responseBody.length, 1024);
      expect(exchange.responseBodyTruncated, isTrue);
    });
  });

  group('failures', () {
    test('an upstream that refuses the connection is a 502 with a JSON body that says why, and it is recorded', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = probe.port;
      await probe.close();
      final engine = await startRecorder(configFor(Uri.parse('http://127.0.0.1:$closedPort')));

      final (reply, exchange) = await call(engine, 'GET', '/x?token=abc');

      expect(reply.status, 502);
      expect(reply.header('content-type'), startsWith('application/json'));
      expect(reply.header('x-postpilot-recorder'), 'upstream_refused');
      final body = jsonDecode(reply.text) as Map<String, dynamic>;
      expect(body['error'], 'upstream_refused');
      expect(body['message'], contains('127.0.0.1:$closedPort refused the connection'));
      expect(body['upstream'], 'http://127.0.0.1:$closedPort');
      expect(body['recordedBy'], 'PostPilot traffic recorder');
      expect(reply.text, isNot(contains('token=abc')));
      expect(exchange.kind, RecordedKind.upstreamFailed);
      expect(exchange.status, 502);
      expect(exchange.error, contains('refused the connection'));
      expect(exchange.responseText, reply.text);
    });

    test('an upstream that never answers is a 502 after the timeout', () async {
      final hang = Completer<void>();
      final upstream = await Upstream.start((request, _, _) => hang.future);
      addTearDown(() => hang.complete());
      final engine = await startRecorder(RecorderConfig(upstream: upstream.uri('http'), timeout: const Duration(milliseconds: 400)));

      final (reply, exchange) = await call(engine, 'GET', '/slow');

      expect(reply.status, 502);
      expect(reply.header('x-postpilot-recorder'), 'upstream_timeout');
      expect(exchange.error, contains('did not answer within 400 ms'));
      expect(exchange.kind, RecordedKind.upstreamFailed);
    });

    test('an upstream that cuts the body short ends the app\'s connection and is recorded as failed', () async {
      final upstream = await Upstream.start((request, _, _) async {
        // Announces 1000 bytes, sends 10 and drops the connection.
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.add(utf8.encode('HTTP/1.1 200 OK\r\ncontent-length: 1000\r\ncontent-type: text/plain\r\n\r\n0123456789'));
        await socket.flush();
        socket.destroy();
      });
      final engine = await startRecorder(configFor(upstream.uri('http')));
      final recorded = engine.exchanges.first.timeout(_wait);

      Object? appSawError;
      try {
        await send(engine.port!, 'GET', '/cut');
      } catch (e) {
        appSawError = e;
      }

      final exchange = await recorded;
      expect(appSawError, isNotNull, reason: 'the app must see the cut, not a silently shortened body');
      expect(exchange.kind, RecordedKind.upstreamFailed);
      expect(exchange.status, 200);
      expect(exchange.error, isNotNull);
    });

    test('a TLS upstream that is not trusted is a 502 that names the self-signed switch', () async {
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, utf8.encode('secure')), tls: selfSignedServerContext());
      final engine = await startRecorder(configFor(upstream.uri('https')));

      final (reply, exchange) = await call(engine, 'GET', '/tls');

      expect(reply.status, 502);
      expect(reply.header('x-postpilot-recorder'), 'upstream_tls');
      expect(exchange.error, contains('Allow a self-signed upstream'));
      expect(upstream.seen, isEmpty);
    });

    test('with "allow self-signed" the same upstream is reached over TLS', () async {
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, utf8.encode('secure')), tls: selfSignedServerContext());
      final engine = await startRecorder(RecorderConfig(upstream: upstream.uri('https'), allowSelfSigned: true));

      final (reply, exchange) = await call(engine, 'GET', '/tls?x=1');

      expect(reply.status, 200);
      expect(reply.text, 'secure');
      expect(upstream.seen.single.uri.query, 'x=1');
      expect(exchange.url, startsWith('https://127.0.0.1:'));
    });

    test('a plain-http server behind an https upstream address is a TLS failure, not a hang', () async {
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, const []));
      final engine = await startRecorder(configFor(upstream.uri('https')));

      final (reply, _) = await call(engine, 'GET', '/');

      expect(reply.status, 502);
      expect(reply.header('x-postpilot-recorder'), 'upstream_tls');
    });
  });

  group('calls it does not forward', () {
    test('a WebSocket upgrade is refused with a 501 that explains why, and the upstream never sees it', () async {
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, const []));
      final engine = await startRecorder(configFor(upstream.uri('http')));
      final recorded = engine.exchanges.first.timeout(_wait);

      final socket = await Socket.connect(InternetAddress.loopbackIPv4, engine.port!);
      socket.write(
        'GET /chat?room=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
        'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n',
      );
      final answer = await utf8.decoder.bind(socket).join().timeout(_wait);

      expect(answer, startsWith('HTTP/1.1 501'));
      expect(answer, contains('WebSocket'));
      expect(answer, contains('x-postpilot-recorder: websocket_not_supported'));
      final exchange = await recorded;
      expect(exchange.kind, RecordedKind.refused);
      expect(exchange.status, 501);
      expect(exchange.path, '/chat?room=1');
      expect(exchange.error, contains('cannot forward WebSocket'));
      expect(upstream.seen, isEmpty);
    });

    test('a WebSocket client sees its connection refused, not a silent drop', () async {
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, const []));
      final engine = await startRecorder(configFor(upstream.uri('http')));

      await expectLater(
        WebSocket.connect('ws://127.0.0.1:${engine.port}/chat').timeout(_wait),
        throwsA(isA<WebSocketException>()),
      );
    });

    test('a CONNECT request (the recorder set as an HTTP proxy) is refused with the right advice', () async {
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, const []));
      final engine = await startRecorder(configFor(upstream.uri('http')));
      final recorded = engine.exchanges.first.timeout(_wait);

      final socket = await Socket.connect(InternetAddress.loopbackIPv4, engine.port!);
      socket.write('CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\nConnection: close\r\n\r\n');
      final answer = await utf8.decoder.bind(socket).join().timeout(_wait);

      expect(answer, startsWith('HTTP/1.1 501'));
      expect(answer, contains('reverse proxy'));
      expect((await recorded).kind, RecordedKind.refused);
      expect(upstream.seen, isEmpty);
    });
  });

  group('listening', () {
    test('binds to this computer only by default and to every interface when asked, so a phone can connect', () async {
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, utf8.encode('hi')));
      final local = await startRecorder(configFor(upstream.uri('http')));
      final open = await startRecorder(RecorderConfig(upstream: upstream.uri('http'), host: RecorderConfig.allInterfaces));
      expect(open.config!.listensOnAllInterfaces, isTrue);
      expect(local.config!.listensOnAllInterfaces, isFalse);

      expect((await send(open.port!, 'GET', '/', host: '127.0.0.1')).text, 'hi');
      final lan = await RecorderAddresses.lookup();
      if (lan.isNotEmpty) {
        final ip = lan.first.ip;
        // The address a phone on the Wi-Fi would use: reachable when listening everywhere, refused when loopback-only.
        expect((await send(open.port!, 'GET', '/', host: ip)).text, 'hi');
        await expectLater(send(local.port!, 'GET', '/', host: ip), throwsA(isA<SocketException>()));
      }
    });

    test('a call that arrives on the network address is recorded with that address as its client', () async {
      final lan = await RecorderAddresses.lookup();
      if (lan.isEmpty) return;
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, const []));
      final engine = await startRecorder(RecorderConfig(upstream: upstream.uri('http'), host: RecorderConfig.allInterfaces));
      final recorded = engine.exchanges.first.timeout(_wait);

      // Bound to the network address, the connection's source is that address too: what a phone's address is on a real call.
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.openUrl('GET', Uri.parse('http://${lan.first.ip}:${engine.port}/who'));
      final response = await request.close();
      await response.drain<void>();

      expect((await recorded).clientAddress, lan.first.ip);
    });

    test('a port that is taken is reported in words', () async {
      final taken = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(taken.close);
      final engine = RecorderEngine.create();
      addTearDown(engine.dispose);

      await expectLater(
        engine.start(RecorderConfig(upstream: Uri.parse('http://127.0.0.1:9'), port: taken.port)),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('already in use'))),
      );
      expect(engine.isRunning, isFalse);
    });

    test('an upstream that is the recorder itself is refused before it can loop', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      final engine = RecorderEngine.create();
      addTearDown(engine.dispose);

      await expectLater(
        engine.start(RecorderConfig(upstream: Uri.parse('http://localhost:$port'), port: port)),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('this recorder itself'))),
      );
      expect(engine.isRunning, isFalse);
    });

    test('stop closes the port and a stopped engine can start again', () async {
      final upstream = await Upstream.start((request, _, _) => _respond(request, 200, utf8.encode('hi')));
      final engine = await startRecorder(configFor(upstream.uri('http')));
      final firstPort = engine.port!;

      await engine.stop();

      expect(engine.isRunning, isFalse);
      expect(engine.port, isNull);
      await expectLater(send(firstPort, 'GET', '/'), throwsA(isA<SocketException>()));
      await engine.start(configFor(upstream.uri('http')));
      expect((await send(engine.port!, 'GET', '/')).text, 'hi');
    });

    test('a configuration without a usable upstream is refused', () {
      expect(RecorderConfig(upstream: Uri.parse('ftp://example.com')).problem, isNotNull);
      expect(RecorderConfig(upstream: Uri.parse('https://example.com'), port: 70000).problem, contains('port'));
      expect(RecorderConfig(upstream: Uri.parse('https://example.com')).problem, isNull);
    });
  });
}
