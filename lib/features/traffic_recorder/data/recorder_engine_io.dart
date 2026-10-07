import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../domain/services/recorder_headers.dart';
import 'recorder_engine.dart';

bool get isRecorderSupported => true;

RecorderEngine createRecorderEngine() => _IoRecorderEngine();

/// The socket side of the recorder: a `dart:io` server that forwards each request with an `HttpClient` that does not
/// follow redirects and does not inflate bodies, so what the upstream sent is what the app receives, byte for byte.
final class _IoRecorderEngine implements RecorderEngine {
  HttpServer? _server;
  HttpClient? _client;
  RecorderConfig? _config;
  StreamSubscription<HttpRequest>? _subscription;
  final _exchanges = StreamController<RecordedExchange>.broadcast();
  final _inFlight = <HttpClientRequest>{};
  var _nextId = 1;

  @override
  bool get isRunning => _server != null;

  @override
  int? get port => _server?.port;

  @override
  RecorderConfig? get config => _config;

  @override
  Stream<RecordedExchange> get exchanges => _exchanges.stream;

  @override
  Future<void> start(RecorderConfig config) async {
    if (_server != null) await stop();
    final problem = config.problem;
    if (problem != null) throw StateError(problem);
    final HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.tryParse(config.host) ?? config.host, config.port);
    } on SocketException catch (e) {
      // A bind failure on a chosen port is nearly always "in use" or "not allowed" (the OS error codes differ per system
      // and are not always set), so say that instead of the raw message.
      throw StateError(
        config.port != 0
            ? 'Port ${config.port} is already in use or not allowed. Choose another port.'
            : "Couldn't start the recorder: ${e.message}",
      );
    }
    if (_pointsAtItself(config.upstream, server.port)) {
      await server.close(force: true);
      throw StateError(
        'The upstream ${RecorderHeaders.originOf(config.upstream)} is this recorder itself: every call would loop back. '
        'Enter the address of the real server, or choose another port.',
      );
    }
    // The upstream decides the headers of an answer; nothing is added on the way back (the Dart server would otherwise put
    // `x-frame-options` and the like on every response).
    server.defaultResponseHeaders.clear();
    _server = server;
    _config = config;
    _client = _newClient(config);
    _subscription = server.listen(_handle, onError: (Object _) {});
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    for (final request in _inFlight.toList()) {
      try {
        request.abort();
      } catch (_) {}
    }
    _inFlight.clear();
    // `force` also drops the connections of calls still being answered.
    await _server?.close(force: true);
    _server = null;
    _client?.close(force: true);
    _client = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _exchanges.close();
  }

  static bool _pointsAtItself(Uri upstream, int port) {
    final upstreamPort = upstream.hasPort ? upstream.port : (upstream.scheme == 'https' ? 443 : 80);
    final host = upstream.host.toLowerCase();
    final loopback = host == 'localhost' || host == '::1' || host == '0.0.0.0' || host.startsWith('127.');
    return loopback && upstreamPort == port;
  }

  static HttpClient _newClient(RecorderConfig config) {
    final client = HttpClient()
      // The body is passed on exactly as the upstream sent it; a decoded copy is made for the recording only.
      ..autoUncompress = false
      // The app's own User-Agent is forwarded; Dart must not add one of its own when the app sent none.
      ..userAgent = null
      ..connectionTimeout = config.connectTimeout
      ..idleTimeout = const Duration(seconds: 30)
      ..findProxy = config.useSystemProxy ? HttpClient.findProxyFromEnvironment : ((_) => 'DIRECT');
    if (config.allowSelfSigned) {
      final upstreamHost = config.upstream.host;
      // Only for the one server the person named, never for a host a redirect or another call might involve.
      client.badCertificateCallback = (certificate, host, port) => host == upstreamHost;
    }
    return client;
  }

  Future<void> _handle(HttpRequest request) async {
    final config = _config;
    final client = _client;
    final response = request.response;
    if (config == null || client == null) {
      response.statusCode = HttpStatus.serviceUnavailable;
      await _closeQuietly(response);
      return;
    }

    final started = DateTime.now();
    final watch = Stopwatch()..start();
    final method = request.method.toUpperCase();
    final target = _targetOf(request);
    final requestHeaders = _headersOf(request.headers);
    final clientAddress = request.connectionInfo?.remoteAddress.address;
    final localPort = _server?.port ?? config.port;

    RecordedExchange refused(String code, String message) {
      _answerItself(response, status: HttpStatus.notImplemented, code: code, message: message);
      return RecordedExchange(
        id: _nextId++,
        startedAt: started,
        duration: watch.elapsed,
        method: method,
        url: target,
        path: target,
        status: HttpStatus.notImplemented,
        statusMessage: 'Not Implemented',
        clientAddress: clientAddress,
        kind: RecordedKind.refused,
        requestHeaders: requestHeaders,
        error: message,
      );
    }

    final upgrade = _single(request.headers, 'upgrade');
    if (method == 'CONNECT') {
      await _publishAfter(
        response,
        refused(
          'proxy_not_supported',
          'This is a reverse proxy, not an HTTP proxy. Set your app\'s base URL to the recorder\'s address '
              'instead of setting it as a proxy.',
        ),
      );
      return;
    }
    if (upgrade != null) {
      final websocket = upgrade.toLowerCase().contains('websocket');
      await _publishAfter(
        response,
        refused(
          websocket ? 'websocket_not_supported' : 'upgrade_not_supported',
          websocket
              ? 'The traffic recorder cannot forward WebSocket connections. Connect the WebSocket to the real server '
                  'directly (only the HTTP calls go through the recorder), or try it in PostPilot\'s WebSocket tool.'
              : 'The traffic recorder cannot forward a connection upgrade ("${_oneLine(upgrade)}"). Connect to the real '
                  'server directly for that part.',
        ),
      );
      return;
    }

    final requestBody = _Capture(config.maxBodyBytes);
    final responseBody = _Capture(config.maxBodyBytes);
    var committed = false;
    var status = HttpStatus.badGateway;
    var statusMessage = 'Bad Gateway';
    var responseHeaders = const <RecordedHeader>[];
    String? responseEncoding;
    var kind = RecordedKind.proxied;
    String? error;
    Uri? uri;
    HttpClientRequest? outgoing;
    Object? requestStreamError;
    Object? responseStreamError;
    try {
      uri = RecorderHeaders.upstreamUri(config.upstream, target);
      outgoing = await client.openUrl(method, uri);
      _inFlight.add(outgoing);
      outgoing
        ..followRedirects = false
        ..bufferOutput = false;
      _forwardRequestHeaders(request, outgoing, config, localPort);
      _frameRequest(request, outgoing);
      await outgoing.addStream(request.transform(_tee<Uint8List>(requestBody, (e) => requestStreamError ??= e)));
      final upstream = await outgoing.close().timeout(config.timeout);

      status = upstream.statusCode;
      statusMessage = upstream.reasonPhrase;
      responseHeaders = _headersOf(upstream.headers);
      responseEncoding = _single(upstream.headers, 'content-encoding');
      response
        ..statusCode = status
        ..reasonPhrase = statusMessage
        ..bufferOutput = false;
      _copyResponseHeaders(upstream, response);
      final bodyless = method == 'HEAD' || status < 200 || status == HttpStatus.noContent || status == HttpStatus.notModified;
      // A known length is passed on as it is; an unknown one stays chunked, which Dart does by itself.
      if (upstream.contentLength >= 0 && (!bodyless || method == 'HEAD') && status >= 200) {
        response.contentLength = upstream.contentLength;
      }
      committed = true;
      if (bodyless) {
        await upstream.drain<void>();
      } else {
        await response.addStream(
          upstream.transform(_tee<List<int>>(responseBody, (e) => responseStreamError ??= e)).timeout(config.timeout),
        );
      }
      final brokenBody = responseStreamError;
      if (brokenBody != null) throw brokenBody;
      await _closeQuietly(response);
    } catch (e) {
      final failure = requestStreamError != null
          ? const _Failure(
              'request_interrupted',
              'The app closed the connection before it finished sending the request.',
            )
          : _describeFailure(e, config);
      kind = RecordedKind.upstreamFailed;
      error = failure.message;
      if (!committed) {
        status = HttpStatus.badGateway;
        statusMessage = 'Bad Gateway';
        final body = _answerItself(response, status: status, code: failure.code, message: failure.message, upstream: config.upstream);
        responseBody.add(body);
        responseHeaders = const [RecordedHeader('content-type', 'application/json; charset=utf-8')];
      }
      // Once the answer has begun nothing can change its status; Dart drops the connection after the broken body, which
      // is how the app learns it was cut short.
      try {
        outgoing?.abort();
      } catch (_) {}
    } finally {
      if (outgoing != null) _inFlight.remove(outgoing);
    }

    final requestBytes = requestBody.take();
    final responseBytes = responseBody.take();
    final requestInflated = _inflate(requestBytes, _single(request.headers, 'content-encoding'), requestBody.truncated, config.maxBodyBytes);
    final responseInflated = _inflate(responseBytes, responseEncoding, responseBody.truncated, config.maxBodyBytes);
    _publish(RecordedExchange(
      id: _nextId++,
      startedAt: started,
      duration: watch.elapsed,
      method: method,
      url: uri?.toString() ?? target,
      path: target,
      status: status,
      statusMessage: statusMessage,
      clientAddress: clientAddress,
      kind: kind,
      requestHeaders: requestHeaders,
      requestBody: requestInflated.bytes,
      requestBodySize: requestBody.total,
      requestBodyTruncated: requestInflated.truncated,
      responseHeaders: responseHeaders,
      responseBody: responseInflated.bytes,
      responseBodySize: responseBody.total,
      responseBodyTruncated: responseInflated.truncated,
      responseEncoding: responseEncoding,
      responseUndecoded: responseInflated.undecoded,
      error: error,
    ));
  }

  Future<void> _publishAfter(HttpResponse response, RecordedExchange exchange) async {
    await _closeQuietly(response);
    _publish(exchange);
  }

  void _publish(RecordedExchange exchange) {
    if (!_exchanges.isClosed) _exchanges.add(exchange);
  }

  static Future<void> _closeQuietly(HttpResponse response) async {
    try {
      await response.close();
    } catch (_) {
      // The app went away before the answer was written.
    }
  }

  /// Writes a JSON answer made by the recorder itself (never by the upstream), marked with `x-postpilot-recorder`, and
  /// returns the body it wrote. Does not wait for it to be flushed.
  static List<int> _answerItself(
    HttpResponse response, {
    required int status,
    required String code,
    required String message,
    Uri? upstream,
  }) {
    final body = utf8.encode(jsonEncode({
      'error': code,
      'message': message,
      'upstream': ?(upstream == null ? null : RecorderHeaders.originOf(upstream)),
      'recordedBy': 'PostPilot traffic recorder',
    }));
    try {
      response
        ..statusCode = status
        ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
        ..headers.set('x-postpilot-recorder', code)
        ..contentLength = body.length
        ..add(body);
      unawaited(response.close().catchError((Object _) => response));
    } catch (_) {
      // The answer had begun, or the app is gone.
    }
    return body;
  }

  static String _targetOf(HttpRequest request) {
    final path = request.uri.path.isEmpty ? '/' : request.uri.path;
    return request.uri.hasQuery ? '$path?${request.uri.query}' : path;
  }

  static List<RecordedHeader> _headersOf(HttpHeaders headers) {
    final list = <RecordedHeader>[];
    headers.forEach((name, values) {
      for (final value in values) {
        list.add(RecordedHeader(name, value));
      }
    });
    return list;
  }

  static void _forwardRequestHeaders(HttpRequest request, HttpClientRequest out, RecorderConfig config, int localPort) {
    final hostHeader = _single(request.headers, 'host');
    // Dart's HttpClient adds `Accept-Encoding: gzip` to every request, even with autoUncompress off. The app decides what it
    // accepts: without this the upstream would compress for an app that never asked it to.
    out.headers.removeAll(HttpHeaders.acceptEncodingHeader);
    request.headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (RecorderHeaders.dropFromRequest(lower)) return;
      for (var value in values) {
        if (lower == 'accept-encoding' && config.keepResponsesReadable) value = RecorderHeaders.readableAcceptEncoding(value);
        if (config.rewriteHostHeaders && (lower == 'origin' || lower == 'referer')) {
          value = RecorderHeaders.rewriteOriginLike(value, upstream: config.upstream, hostHeader: hostHeader, localPort: localPort);
        }
        try {
          out.headers.add(name, value);
        } catch (_) {
          // A value Dart refuses (a stray control character) is dropped, not fatal.
        }
      }
    });
    try {
      if (config.rewriteHostHeaders) {
        out.headers.set('host', RecorderHeaders.authorityOf(config.upstream));
      } else if (hostHeader != null) {
        out.headers.set('host', hostHeader);
      }
    } catch (_) {}
  }

  /// The body is streamed, so its length is passed on as the app announced it (or chunked, when it did not).
  static void _frameRequest(HttpRequest request, HttpClientRequest out) {
    final length = request.contentLength;
    if (length >= 0) {
      out.contentLength = length;
    } else if (request.headers.chunkedTransferEncoding) {
      out
        ..contentLength = -1
        ..headers.chunkedTransferEncoding = true;
    } else {
      out.contentLength = 0;
    }
  }

  static void _copyResponseHeaders(HttpClientResponse from, HttpResponse to) {
    from.headers.forEach((name, values) {
      if (RecorderHeaders.dropFromResponse(name.toLowerCase())) return;
      for (final value in values) {
        try {
          to.headers.add(name, value);
        } catch (_) {}
      }
    });
  }

  static StreamTransformer<T, T> _tee<T extends List<int>>(_Capture capture, void Function(Object error) onError) =>
      StreamTransformer<T, T>.fromHandlers(
        handleData: (data, sink) {
          capture.add(data);
          sink.add(data);
        },
        handleError: (error, stackTrace, sink) {
          onError(error);
          sink.addError(error, stackTrace);
        },
      );

  /// All values of a header as one text (`HttpHeaders.value` throws when a name is repeated).
  static String? _single(HttpHeaders headers, String name) => headers[name]?.join(', ');

  static String _readable(Duration d) => d.inSeconds >= 1 ? '${d.inSeconds} seconds' : '${d.inMilliseconds} ms';

  static String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static _Failure _describeFailure(Object e, RecorderConfig config) {
    final where = RecorderHeaders.authorityOf(config.upstream);
    final wait = _readable(config.timeout);
    if (e is TimeoutException) {
      return _Failure('upstream_timeout', '$where did not answer within $wait. Is the server running and reachable from this computer?');
    }
    if (e is TlsException) {
      final osMessage = e.osError?.message ?? '';
      return _Failure(
        'upstream_tls',
        'Could not make a secure connection to $where: its certificate was rejected (${_oneLine(osMessage.isEmpty ? e.message : osMessage)}). '
            'If you trust this server (a test or self-signed one), switch on "Allow a self-signed upstream" in the recorder.',
      );
    }
    if (e is SocketException) {
      final os = e.osError;
      final text = '${e.message} ${os?.message ?? ''}'.toLowerCase();
      final code = os?.errorCode;
      if (text.contains('failed host lookup') || text.contains('no such host') || text.contains('nodename nor servname') || code == 11001) {
        return _Failure('upstream_unknown_host', 'Could not find the host of $where. Check the upstream address and this computer\'s network connection.');
      }
      if (text.contains('refused') || code == 10061 || code == 1225 || code == 111 || code == 61) {
        return _Failure('upstream_refused', '$where refused the connection. Is the server running, and is the port right?');
      }
      if (text.contains('timed out') || code == 10060 || code == 1460 || code == 110 || code == 60) {
        return _Failure('upstream_timeout', 'Could not connect to $where in ${_readable(config.connectTimeout)}.');
      }
      return _Failure('upstream_unreachable', 'Could not reach $where: ${_oneLine(e.message)}.');
    }
    if (e is HttpException) {
      return _Failure('upstream_protocol', '$where broke off or sent something that is not valid HTTP: ${_oneLine(e.message)}.');
    }
    if (e is FormatException) {
      return const _Failure('bad_request', 'The address of this call could not be forwarded because it is not a valid URL.');
    }
    return _Failure('recorder_error', 'The recorder failed while forwarding this call (${e.runtimeType}).');
  }

  /// A decoded copy of [raw] for the recording, at most [limit] bytes. Compressed bodies (gzip, deflate) are inflated;
  /// brotli and the like cannot be, which is said by `undecoded`.
  static _Inflated _inflate(Uint8List raw, String? encoding, bool rawTruncated, int limit) {
    final codings = [
      for (final c in (encoding ?? '').split(','))
        if (c.trim().isNotEmpty && c.trim().toLowerCase() != 'identity') c.trim().toLowerCase(),
    ];
    if (codings.isEmpty || raw.isEmpty) return _Inflated(raw, rawTruncated, false);
    if (codings.any((c) => c != 'gzip' && c != 'x-gzip' && c != 'deflate')) return _Inflated(raw, rawTruncated, true);
    var data = raw;
    var truncated = rawTruncated;
    for (final coding in codings.reversed) {
      final step = _inflateOnce(data, coding, limit);
      if (step == null) return _Inflated(raw, rawTruncated, true);
      data = step.bytes;
      truncated = truncated || step.overflow || step.failed;
    }
    return _Inflated(data, truncated, false);
  }

  static ({Uint8List bytes, bool overflow, bool failed})? _inflateOnce(Uint8List data, String coding, int limit) {
    ({Uint8List bytes, bool overflow, bool failed}) attempt(Converter<List<int>, List<int>> decoder) {
      final sink = _CappedSink(limit);
      var failed = false;
      try {
        final conversion = decoder.startChunkedConversion(sink);
        conversion.add(data);
        conversion.close();
      } on _CapReached {
        // Enough for the recording; the rest of a very large body is not inflated.
      } catch (_) {
        failed = true;
      }
      return (bytes: sink.take(), overflow: sink.overflow, failed: failed);
    }

    var result = attempt(coding == 'deflate' ? ZLibDecoder() : GZipCodec().decoder);
    // HTTP's "deflate" is zlib-wrapped, but some servers send the raw stream.
    if (coding == 'deflate' && result.failed && result.bytes.isEmpty) result = attempt(ZLibDecoder(raw: true));
    if (result.failed && result.bytes.isEmpty) return null;
    return result;
  }
}

final class _Failure {
  final String code;
  final String message;
  const _Failure(this.code, this.message);
}

final class _Inflated {
  final Uint8List bytes;
  final bool truncated;
  final bool undecoded;
  const _Inflated(this.bytes, this.truncated, this.undecoded);
}

/// The first [limit] bytes of a body that is streamed through, and how many there were in all.
final class _Capture {
  final int limit;
  final _bytes = BytesBuilder();
  var total = 0;

  _Capture(this.limit);

  void add(List<int> chunk) {
    total += chunk.length;
    final room = limit - _bytes.length;
    if (room <= 0) return;
    _bytes.add(room >= chunk.length ? chunk : chunk.sublist(0, room));
  }

  bool get truncated => total > limit;

  Uint8List take() => _bytes.takeBytes();
}

final class _CapReached implements Exception {
  const _CapReached();
}

/// Collects inflated output up to a limit and then stops the inflating, so a small body that expands enormously (a
/// "zip bomb") cannot fill the memory.
final class _CappedSink implements Sink<List<int>> {
  final int limit;
  final _bytes = BytesBuilder();
  var overflow = false;

  _CappedSink(this.limit);

  @override
  void add(List<int> data) {
    final room = limit - _bytes.length;
    if (data.length <= room) {
      _bytes.add(data);
      return;
    }
    if (room > 0) _bytes.add(data.sublist(0, room));
    overflow = true;
    throw const _CapReached();
  }

  @override
  void close() {}

  Uint8List take() => _bytes.takeBytes();
}
