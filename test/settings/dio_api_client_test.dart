import 'dart:async';
import 'dart:io' show HttpException;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/network/dio_api_client.dart';

typedef _Respond = FutureOr<ResponseBody> Function(RequestOptions options, int index);

/// Answers every request from [respond] and records what reached it.
final class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final _Respond respond;
  final List<RequestOptions> requests = [];

  /// Per request: whether its cancel signal fired, which is what stops a body
  /// from being downloaded on a real connection.
  final List<bool> cancelled = [];
  bool closed = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final index = requests.length;
    requests.add(options);
    cancelled.add(false);
    unawaited(cancelFuture?.then((_) => cancelled[index] = true));
    return respond(options, index);
  }

  @override
  void close({bool force = false}) => closed = true;
}

ResponseBody _ok(List<int> body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromBytes(body, 200, headers: {...headers});

ResponseBody _redirect(String location, {int status = 302}) => ResponseBody.fromString(
      'moved',
      status,
      headers: {
        'location': [location],
      },
    );

Uint8List _bytes(int length, [int start = 0]) => Uint8List.fromList([for (var i = 0; i < length; i++) (start + i) % 256]);

ApiRequestSpec _spec(
  String url, {
  String method = 'GET',
  Map<String, String> headers = const {},
  Object? body,
  ApiRequestOptions options = const ApiRequestOptions(),
  ApiCancelToken? cancelToken,
}) =>
    ApiRequestSpec(method: method, url: url, headers: headers, body: body, options: options, cancelToken: cancelToken);

DioApiClient _clientOver(_FakeAdapter adapter) => DioApiClient(adapterFactory: ({required verifySsl, required proxy}) => adapter);

void main() {
  group('timeout', () {
    test('the option reaches the connect and receive timeouts of the request', () async {
      final adapter = _FakeAdapter((_, _) => _ok(const []));
      final client = _clientOver(adapter);

      await client.send(_spec('https://example.com/', options: const ApiRequestOptions(timeout: Duration(seconds: 7))));

      expect(adapter.requests.single.connectTimeout, const Duration(seconds: 7));
      expect(adapter.requests.single.receiveTimeout, const Duration(seconds: 7));
    });

    test('a null timeout is passed as zero, which Dio reads as "wait forever"', () async {
      final adapter = _FakeAdapter((_, _) => _ok(const []));
      final client = _clientOver(adapter);

      await client.send(_spec('https://example.com/', options: const ApiRequestOptions(timeout: null)));

      expect(adapter.requests.single.connectTimeout, Duration.zero);
      expect(adapter.requests.single.receiveTimeout, Duration.zero);
    });

    test('the default is the 30 seconds of before', () async {
      final adapter = _FakeAdapter((_, _) => _ok(const []));

      await _clientOver(adapter).send(_spec('https://example.com/'));

      expect(adapter.requests.single.connectTimeout, const Duration(seconds: 30));
    });

    test('a request timing out surfaces as a timeout NetworkException', () async {
      final adapter = _FakeAdapter(
        (options, _) => throw DioException.receiveTimeout(timeout: const Duration(seconds: 1), requestOptions: options),
      );

      await expectLater(
        _clientOver(adapter).send(_spec('https://example.com/')),
        throwsA(isA<NetworkException>().having((e) => e.kind, 'kind', NetworkErrorKind.timeout)),
      );
    });
  });

  group('redirects', () {
    test('are followed by default, hop by hop', () async {
      final adapter = _FakeAdapter((options, index) => index == 0 ? _redirect('/next') : _ok('done'.codeUnits));

      final response = await _clientOver(adapter).send(_spec('https://example.com/start'));

      expect(adapter.requests.map((r) => r.uri.toString()), ['https://example.com/start', 'https://example.com/next']);
      expect(response.statusCode, 200);
      expect(String.fromCharCodes(response.bodyBytes), 'done');
    });

    test('followRedirects off returns the 3xx itself, with its Location header', () async {
      final adapter = _FakeAdapter((_, _) => _redirect('/next'));

      final response = await _clientOver(adapter).send(
        _spec('https://example.com/start', options: const ApiRequestOptions(followRedirects: false)),
      );

      expect(adapter.requests, hasLength(1));
      expect(response.statusCode, 302);
      expect(response.headers['location'], '/next');
      expect(String.fromCharCodes(response.bodyBytes), 'moved');
    });

    test('a chain of exactly maxRedirects hops still succeeds', () async {
      final adapter = _FakeAdapter((options, index) => index < 3 ? _redirect('/hop${index + 1}') : _ok(const []));

      final response = await _clientOver(adapter).send(
        _spec('https://example.com/', options: const ApiRequestOptions(maxRedirects: 3)),
      );

      expect(response.statusCode, 200);
      expect(adapter.requests, hasLength(4));
    });

    test('one hop past maxRedirects fails with a "Too many redirects" error', () async {
      final adapter = _FakeAdapter((_, index) => _redirect('/again${index + 1}'));

      await expectLater(
        _clientOver(adapter).send(_spec('https://example.com/', options: const ApiRequestOptions(maxRedirects: 3))),
        throwsA(isA<NetworkException>().having((e) => e.message, 'message', 'Too many redirects (limit 3).')),
      );
      expect(adapter.requests, hasLength(4), reason: 'the first request plus the three hops that were allowed');
    });

    test('a redirect without a usable Location is returned as the response', () async {
      final noLocation = _FakeAdapter((_, _) => ResponseBody.fromString('', 302));
      final deepLink = _FakeAdapter((_, _) => _redirect('myapp://open'));

      expect((await _clientOver(noLocation).send(_spec('https://example.com/'))).statusCode, 302);
      expect((await _clientOver(deepLink).send(_spec('https://example.com/'))).statusCode, 302);
    });

    test('a POST becomes a body-less GET on 302 and 303, but 307 replays it', () async {
      Future<List<RequestOptions>> run(int status) async {
        final adapter = _FakeAdapter((_, index) => index == 0 ? _redirect('/next', status: status) : _ok(const []));
        await _clientOver(adapter).send(_spec(
          'https://example.com/',
          method: 'POST',
          headers: {'Content-Type': 'application/json', 'X-Keep': '1'},
          body: Uint8List.fromList([1, 2, 3]),
        ));
        return adapter.requests;
      }

      for (final status in [302, 303]) {
        final hops = await run(status);
        expect(hops[1].method, 'GET', reason: '$status');
        expect(hops[1].data, isNull, reason: '$status');
        expect(hops[1].headers.keys.where((k) => k.toLowerCase().startsWith('content-')), isEmpty, reason: '$status');
        expect(hops[1].headers['X-Keep'], '1', reason: '$status');
      }

      final replayed = await run(307);
      expect(replayed[1].method, 'POST');
      expect(replayed[1].data, isNotNull);
    });

    test('Authorization and Cookie stay on the same host and are dropped for another', () async {
      Future<RequestOptions> secondHop(String location) async {
        final adapter = _FakeAdapter((_, index) => index == 0 ? _redirect(location) : _ok(const []));
        await _clientOver(adapter).send(
          _spec('https://api.example.com/start', headers: {'Authorization': 'Bearer t', 'Cookie': 'a=b', 'X-Other': '1'}),
        );
        return adapter.requests[1];
      }

      final same = await secondHop('/next');
      expect(same.headers['Authorization'], 'Bearer t');
      expect(same.headers['Cookie'], 'a=b');

      final other = await secondHop('https://elsewhere.io/next');
      expect(other.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
      // The cookie interceptor always sets the header, empty when the jar has nothing for the host.
      expect(other.headers['Cookie'] ?? '', isEmpty);
      expect(other.headers['X-Other'], '1');
    });
  });

  group('response size cap', () {
    test('a body over the cap is cut to it and marked truncated', () async {
      final adapter = _FakeAdapter((_, _) => _ok(_bytes(100)));

      final response = await _clientOver(adapter).send(
        _spec('https://example.com/', options: const ApiRequestOptions(maxResponseBytes: 10)),
      );

      expect(response.truncated, isTrue);
      expect(response.bodyBytes, _bytes(10));
      expect(response.sizeBytes, 10);
    });

    test('the cut may fall in the middle of a chunk, and every earlier chunk is kept whole', () async {
      final adapter = _FakeAdapter(
        (_, _) => ResponseBody(
          Stream.fromIterable([_bytes(4), _bytes(4, 4), _bytes(4, 8)]),
          200,
        ),
      );

      final response = await _clientOver(adapter).send(
        _spec('https://example.com/', options: const ApiRequestOptions(maxResponseBytes: 6)),
      );

      expect(response.bodyBytes, _bytes(6));
      expect(response.truncated, isTrue);
    });

    test('the rest of a cut-off body is not downloaded: the request is cancelled', () async {
      final adapter = _FakeAdapter((_, _) => ResponseBody(Stream.fromIterable([_bytes(8), _bytes(8)]), 200));

      await _clientOver(adapter).send(
        _spec('https://example.com/', options: const ApiRequestOptions(maxResponseBytes: 5)),
      );
      await pumpEventQueue();

      expect(adapter.cancelled.single, isTrue);
    });

    test('a body exactly the size of the cap is whole, not truncated, and its request is left alone', () async {
      final adapter = _FakeAdapter((_, _) => _ok(_bytes(10)));

      final response = await _clientOver(adapter).send(
        _spec('https://example.com/', options: const ApiRequestOptions(maxResponseBytes: 10)),
      );
      await pumpEventQueue();

      expect(response.truncated, isFalse);
      expect(response.bodyBytes, _bytes(10));
      expect(adapter.cancelled.single, isFalse, reason: 'cancelling would throw away a reusable connection');
    });

    test('no cap keeps the whole body', () async {
      final adapter = _FakeAdapter((_, _) => _ok(_bytes(5000)));

      final response = await _clientOver(adapter).send(_spec('https://example.com/'));

      expect(response.truncated, isFalse);
      expect(response.sizeBytes, 5000);
    });

    test('an empty body is never truncated, even under a cap of zero bytes', () async {
      final adapter = _FakeAdapter((_, _) => _ok(const []));

      final response = await _clientOver(adapter).send(
        _spec('https://example.com/', options: const ApiRequestOptions(maxResponseBytes: 0)),
      );

      expect(response.truncated, isFalse);
      expect(response.bodyBytes, isEmpty);
    });

    test('the body of a redirect that is followed is dropped, not kept or counted', () async {
      final adapter = _FakeAdapter((_, index) => index == 0 ? _redirect('/next') : _ok(_bytes(3)));

      final response = await _clientOver(adapter).send(
        _spec('https://example.com/', options: const ApiRequestOptions(maxResponseBytes: 100)),
      );
      await pumpEventQueue();

      expect(response.bodyBytes, _bytes(3));
      expect(response.truncated, isFalse);
      expect(adapter.cancelled, [true, false], reason: 'the redirect body is abandoned, the real one is read to the end');
    });
  });

  group('errors', () {
    test('a certificate the platform does not trust points at the Verify SSL setting', () async {
      final adapter = _FakeAdapter((options, _) => throw DioException.badCertificate(requestOptions: options));

      await expectLater(
        _clientOver(adapter).send(_spec('https://example.com/')),
        throwsA(isA<NetworkException>().having((e) => e.message, 'message', contains('turn off "Verify SSL certificates" in Settings'))),
      );
    });

    test('a failed TLS handshake is recognised as a certificate problem too', () async {
      final adapter = _FakeAdapter(
        (options, _) => throw DioException(
          requestOptions: options,
          error: const HttpException('HandshakeException: Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED)'),
        ),
      );

      await expectLater(
        _clientOver(adapter).send(_spec('https://example.com/')),
        throwsA(isA<NetworkException>().having((e) => e.message, 'message', contains('Verify SSL certificates'))),
      );
    });

    test('other failures carry no such hint', () async {
      final adapter = _FakeAdapter(
        (options, _) => throw DioException.connectionError(requestOptions: options, reason: 'connection refused'),
      );

      await expectLater(
        _clientOver(adapter).send(_spec('https://example.com/')),
        throwsA(isA<NetworkException>().having((e) => e.message, 'message', isNot(contains('Verify SSL')))),
      );
    });

    test('a connection that drops while the body is arriving is a NetworkException', () async {
      Stream<Uint8List> dropping() async* {
        yield _bytes(3);
        throw const HttpException('Connection closed while receiving data');
      }

      final adapter = _FakeAdapter((_, _) => ResponseBody(dropping(), 200));

      await expectLater(
        _clientOver(adapter).send(_spec('https://example.com/')),
        throwsA(isA<NetworkException>().having((e) => e.message, 'message', contains('Connection closed'))),
      );
    });

    test('cancelling the token aborts the send as a cancelled NetworkException', () async {
      final gate = Completer<ResponseBody>();
      final adapter = _FakeAdapter((_, _) => gate.future);
      final token = ApiCancelToken();

      final pending = _clientOver(adapter).send(_spec('https://example.com/', cancelToken: token));
      final outcome = expectLater(
        pending,
        throwsA(isA<NetworkException>().having((e) => e.kind, 'kind', NetworkErrorKind.cancelled)),
      );
      await pumpEventQueue();
      token.cancel();

      await outcome;
    });

    test('a token cancelled while a later hop is in flight still cancels that hop', () async {
      final gate = Completer<ResponseBody>();
      final adapter = _FakeAdapter((_, index) => index == 0 ? _redirect('/next') : gate.future);
      final token = ApiCancelToken();

      final pending = _clientOver(adapter).send(_spec('https://example.com/', cancelToken: token));
      final outcome = expectLater(
        pending,
        throwsA(isA<NetworkException>().having((e) => e.kind, 'kind', NetworkErrorKind.cancelled)),
      );
      await pumpEventQueue();
      expect(adapter.requests, hasLength(2));
      token.cancel();

      await outcome;
    });
  });

  group('response', () {
    test('status, message, joined headers and duration come through', () async {
      final adapter = _FakeAdapter(
        (_, _) => ResponseBody.fromString(
          'hi',
          201,
          statusMessage: 'Created',
          headers: {
            'set-cookie': ['a=1', 'b=2'],
            'content-type': ['text/plain'],
          },
        ),
      );

      final response = await _clientOver(adapter).send(_spec('https://example.com/'));

      expect(response.statusCode, 201);
      expect(response.statusMessage, 'Created');
      expect(response.headers['set-cookie'], 'a=1, b=2');
      expect(response.headers['content-type'], 'text/plain');
      expect(response.duration, isNotNull);
      expect(response.truncated, isFalse);
    });

    test('an error status is a response, not an exception', () async {
      final adapter = _FakeAdapter((_, _) => ResponseBody.fromString('nope', 500));

      final response = await _clientOver(adapter).send(_spec('https://example.com/'));

      expect(response.statusCode, 500);
      expect(String.fromCharCodes(response.bodyBytes), 'nope');
    });
  });

  group('adapter selection', () {
    ({DioApiClient client, List<({bool verifySsl, ProxyConfig proxy, _FakeAdapter adapter})> made}) clientTracking() {
      final made = <({bool verifySsl, ProxyConfig proxy, _FakeAdapter adapter})>[];
      final client = DioApiClient(adapterFactory: ({required verifySsl, required proxy}) {
        final adapter = _FakeAdapter((_, _) => _ok(const []));
        made.add((verifySsl: verifySsl, proxy: proxy, adapter: adapter));
        return adapter;
      });
      return (client: client, made: made);
    }

    const custom = ProxyConfig(mode: ProxyMode.custom, host: 'proxy.local', port: 3128);

    test('one adapter serves every request that needs the same TLS and proxy setup', () async {
      final tracked = clientTracking();

      await tracked.client.send(_spec('https://example.com/a'));
      await tracked.client.send(_spec('https://example.com/b', options: const ApiRequestOptions(timeout: null)));

      expect(tracked.made, hasLength(1));
      expect(tracked.made.single.adapter.requests, hasLength(2));
    });

    test('turning certificate checks off builds a new adapter and closes the old one', () async {
      final tracked = clientTracking();

      await tracked.client.send(_spec('https://example.com/'));
      await tracked.client.send(_spec('https://example.com/', options: const ApiRequestOptions(verifySsl: false)));

      expect(tracked.made.map((m) => m.verifySsl), [true, false]);
      expect(tracked.made[0].adapter.closed, isTrue);
      expect(tracked.made[1].adapter.closed, isFalse);
    });

    test('changing the proxy builds a new adapter with that proxy', () async {
      final tracked = clientTracking();

      await tracked.client.send(_spec('https://example.com/'));
      await tracked.client.send(_spec('https://example.com/', options: const ApiRequestOptions(proxy: custom)));
      await tracked.client.send(_spec('https://example.com/', options: const ApiRequestOptions(proxy: custom)));
      await tracked.client.send(_spec('https://example.com/', options: const ApiRequestOptions(proxy: ProxyConfig.none)));

      expect(tracked.made.map((m) => m.proxy), [ProxyConfig.system, custom, ProxyConfig.none]);
      expect(tracked.made.map((m) => m.adapter.closed), [true, true, false]);
    });

    test('going back to the first setup builds a fresh adapter rather than reusing a closed one', () async {
      final tracked = clientTracking();

      await tracked.client.send(_spec('https://example.com/'));
      await tracked.client.send(_spec('https://example.com/', options: const ApiRequestOptions(verifySsl: false)));
      await tracked.client.send(_spec('https://example.com/'));

      expect(tracked.made, hasLength(3));
      expect(tracked.made[2].adapter.requests, hasLength(1));
      expect(tracked.made[2].adapter.closed, isFalse);
    });

    test('an adapter with a request still on it stays open until that request has its response', () async {
      final gate = Completer<void>();
      final made = <({bool verifySsl, _FakeAdapter adapter})>[];
      final client = DioApiClient(adapterFactory: ({required verifySsl, required proxy}) {
        final adapter = _FakeAdapter((_, _) async {
          if (verifySsl) await gate.future;
          return _ok(const []);
        });
        made.add((verifySsl: verifySsl, adapter: adapter));
        return adapter;
      });

      final slow = client.send(_spec('https://example.com/slow'));
      await pumpEventQueue();
      await client.send(_spec('https://example.com/other', options: const ApiRequestOptions(verifySsl: false)));

      expect(made.map((m) => m.verifySsl), [true, false]);
      expect(made[0].adapter.closed, isFalse, reason: 'it is still serving the slow request');

      gate.complete();
      await slow;
      await pumpEventQueue();

      expect(made[0].adapter.closed, isTrue);
      expect(made[1].adapter.closed, isFalse);
    });

    test('two sends in flight with different setups each reach an adapter built for their own', () async {
      final made = <({bool verifySsl, _FakeAdapter adapter})>[];
      final client = DioApiClient(adapterFactory: ({required verifySsl, required proxy}) {
        final adapter = _FakeAdapter((_, _) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return _ok(const []);
        });
        made.add((verifySsl: verifySsl, adapter: adapter));
        return adapter;
      });

      await Future.wait([
        for (var i = 0; i < 6; i++)
          client.send(_spec(
            i.isEven ? 'https://verified.example/$i' : 'https://unverified.example/$i',
            options: ApiRequestOptions(verifySsl: i.isEven),
          )),
      ]);

      for (final entry in made) {
        for (final request in entry.adapter.requests) {
          expect(
            request.uri.host,
            entry.verifySsl ? 'verified.example' : 'unverified.example',
            reason: 'a request that asked for verifySsl=${!entry.verifySsl} went out on the wrong adapter',
          );
        }
      }
      expect(made.expand((m) => m.adapter.requests), hasLength(6));
    });
  });
}
