import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../documentation/domain/services/secret_masker.dart';
import '../../traffic_recorder/domain/services/recorder_headers.dart';
import 'cors_proxy_engine.dart';

bool get isCorsProxySupported => true;

CorsProxyEngine createCorsProxyEngine() => _IoCorsProxyEngine();

/// The socket side of the proxy: a `dart:io` server that forwards each call with an `HttpClient` that follows no redirect and
/// inflates nothing, so what the target sent is what the page receives, byte for byte, plus the CORS headers.
final class _IoCorsProxyEngine implements CorsProxyEngine {
  static const _methods = 'GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS';
  static final _headerToken = RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");

  HttpServer? _server;
  HttpClient? _client;
  CorsProxyConfig? _config;
  CorsProxyOrigins _origins = CorsProxyOrigins();
  Set<String> _ownHosts = const {};
  StreamSubscription<HttpRequest>? _subscription;
  final _events = StreamController<CorsProxyEvent>.broadcast();
  final _inFlight = <HttpClientRequest>{};
  final _attempts = CorsProxyAttempts();

  @override
  bool get isRunning => _server != null;

  @override
  int? get port => _server?.port;

  @override
  CorsProxyConfig? get config => _config;

  @override
  Stream<CorsProxyEvent> get events => _events.stream;

  @override
  Future<void> start(CorsProxyConfig config) async {
    if (_server != null) await stop();
    final problem = config.problem;
    if (problem != null) throw StateError(problem);
    final HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.tryParse(config.host) ?? config.host, config.port);
    } on SocketException catch (e) {
      throw StateError(
        config.port != 0
            ? 'Port ${config.port} is already in use or not allowed. Choose another port with --port.'
            : "Couldn't start the CORS proxy: ${e.message}",
      );
    }
    // The target decides the headers of an answer; the Dart server would otherwise add `x-frame-options` and the like.
    server.defaultResponseHeaders.clear();
    _server = server;
    _config = config;
    _origins = config.origins;
    _ownHosts = config.listensOnAllInterfaces ? await _localAddresses() : const {};
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
    await _server?.close(force: true);
    _server = null;
    _client?.close(force: true);
    _client = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  static Future<Set<String>> _localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list();
      return {for (final i in interfaces) for (final a in i.addresses) a.address.toLowerCase()};
    } catch (_) {
      return const {};
    }
  }

  static HttpClient _newClient(CorsProxyConfig config) {
    final client = HttpClient()
      // The body is passed on exactly as the target sent it; the page's browser inflates it.
      ..autoUncompress = false
      // The page's own User-Agent is forwarded; Dart must not add one when the page sent none.
      ..userAgent = null
      ..connectionTimeout = config.connectTimeout
      ..idleTimeout = const Duration(seconds: 30)
      ..findProxy = ((_) => 'DIRECT');
    if (config.insecure) client.badCertificateCallback = (certificate, host, port) => true;
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

    final at = DateTime.now();
    final watch = Stopwatch()..start();
    final method = request.method.toUpperCase();
    final ownPort = _server?.port ?? config.port;
    final hostHeader = _single(request.headers, 'host');
    final ownAuthority = 'localhost:$ownPort';
    final requestedOrigin = _single(request.headers, 'origin');
    // The origin that may read this answer: the normalized form of what the page sent, when it is allowed.
    final corsOrigin = requestedOrigin == null ? null : (_origins.allows(requestedOrigin) ? CorsProxyOrigins.normalize(requestedOrigin) : null);

    void publish(String host, String path, int status, [String? error]) {
      if (!_events.isClosed) {
        _events.add(CorsProxyEvent(at: at, method: method, host: host, path: path, status: status, duration: watch.elapsed, error: error));
      }
    }

    Future<void> refuse(CorsProxyRefusal refusal, {String path = '', bool readableByPage = true}) async {
      _answerItself(response, refusal.status, {
        'error': refusal.code,
        'message': refusal.message,
        'proxy': 'PostPilot CORS proxy',
      }, errorCode: refusal.code, corsOrigin: readableByPage ? corsOrigin : null);
      publish(ownAuthority, path.isEmpty ? _safePath(request.uri) : path, refusal.status, refusal.code);
      await _closeQuietly(response);
    }

    // A page on another host name that was pointed at this computer (DNS rebinding) must not reach a proxy that listens only
    // here: its Host is not ours.
    if (!config.listensOnAllInterfaces && hostHeader != null && !_isLoopbackHost(_hostOf(hostHeader))) {
      await refuse(
        const CorsProxyRefusal(
          HttpStatus.forbidden,
          'host_not_allowed',
          'This proxy only answers calls addressed to localhost or 127.0.0.1. Use --allow-lan to serve other addresses.',
        ),
        readableByPage: false,
      );
      return;
    }
    if (requestedOrigin != null && corsOrigin == null) {
      final shown = _oneLine(requestedOrigin);
      await refuse(
        CorsProxyRefusal(
          HttpStatus.forbidden,
          'origin_not_allowed',
          'The page at ${shown.length > 120 ? '${shown.substring(0, 120)}...' : shown} is not allowed to use this proxy. '
              'Restart it with --allow-origin $shown to allow that page.',
        ),
        readableByPage: false,
      );
      return;
    }

    // The preflight a browser sends before a call with custom headers: answered here, never forwarded, no token (a preflight
    // cannot carry one).
    if (method == 'OPTIONS' && _single(request.headers, 'access-control-request-method') != null) {
      if (corsOrigin == null) {
        await refuse(
          const CorsProxyRefusal(
            HttpStatus.forbidden,
            'origin_required',
            'A browser preflight needs an Origin header, and the origin must be allowed.',
          ),
          readableByPage: false,
        );
        return;
      }
      _answerPreflight(request, corsOrigin);
      await _closeQuietly(response);
      return;
    }

    final tokenGiven = _single(request.headers, CorsProxyProtocol.tokenHeader.toLowerCase());
    if (tokenGiven == null || tokenGiven.isEmpty) {
      await refuse(CorsProxyRefusal(
        HttpStatus.unauthorized,
        'token_required',
        'The ${CorsProxyProtocol.tokenHeader} header is missing. Paste the token this proxy printed when it started into PostPilot (Settings > CORS proxy).',
      ));
      return;
    }
    // Only a proxy that other devices can reach is guessed at; on this computer a wrong token is a typo.
    final caller = request.connectionInfo?.remoteAddress.address ?? '';
    final throttled = config.listensOnAllInterfaces;
    if (throttled && _attempts.isLocked(caller, at)) {
      await refuse(const CorsProxyRefusal(
        HttpStatus.tooManyRequests,
        'too_many_attempts',
        'Too many wrong tokens from this device. Wait a minute, then paste the token this proxy printed.',
      ));
      return;
    }
    if (!CorsProxyToken.matches(tokenGiven, config.token)) {
      if (throttled) _attempts.recordFailure(caller, at);
      await refuse(const CorsProxyRefusal(
        HttpStatus.unauthorized,
        'token_invalid',
        'The token is wrong. Paste the token this proxy printed when it started into PostPilot (Settings > CORS proxy).',
      ));
      return;
    }
    if (throttled) _attempts.clear(caller);

    final targetHeaders = request.headers[CorsProxyProtocol.urlHeader.toLowerCase()];
    if (targetHeaders == null && request.uri.path == CorsProxyProtocol.healthPath && (method == 'GET' || method == 'HEAD')) {
      _answerItself(response, HttpStatus.ok, {
        'ok': true,
        'version': CorsProxyProtocol.version,
        'allowedOrigin': corsOrigin,
      }, corsOrigin: corsOrigin);
      await _closeQuietly(response);
      return;
    }

    if (method == 'CONNECT' || _single(request.headers, 'upgrade') != null) {
      await refuse(const CorsProxyRefusal(
        HttpStatus.notImplemented,
        'not_supported',
        'This proxy forwards plain HTTP calls only: no CONNECT tunnel and no WebSocket upgrade.',
      ));
      return;
    }
    if (targetHeaders != null && targetHeaders.length > 1) {
      await refuse(const CorsProxyRefusal(
        HttpStatus.badRequest,
        'invalid_target',
        'The ${CorsProxyProtocol.urlHeader} header was sent more than once. Send one address.',
      ));
      return;
    }
    final hostName = _hostOf(hostHeader)?.toLowerCase();
    final target = CorsProxyTargets.parse(
      targetHeaders?.firstOrNull,
      ownPort: ownPort,
      ownHosts: {..._ownHosts, ?hostName},
    );
    final refusal = target.refusal;
    if (refusal != null) {
      await refuse(refusal);
      return;
    }
    final uri = target.uri!;
    final (host, path) = _describe(uri);
    final hide = _single(request.headers, CorsProxyProtocol.redirectsHeader.toLowerCase())?.trim().toLowerCase() ==
        CorsProxyProtocol.redirectsManual;

    var committed = false;
    var status = HttpStatus.badGateway;
    String? error;
    HttpClientRequest? outgoing;
    Object? requestStreamError;
    try {
      outgoing = await client.openUrl(method, uri);
      final active = outgoing;
      _inFlight.add(active);
      // The page went away: do not keep the target busy for nobody.
      unawaited(response.done.then<void>((_) {}, onError: (Object _) {
        try {
          active.abort();
        } catch (_) {}
      }));
      outgoing
        ..followRedirects = false
        ..bufferOutput = false;
      _forwardRequestHeaders(request, outgoing);
      _frameRequest(request, outgoing);
      await outgoing.addStream(request.transform(StreamTransformer<Uint8List, Uint8List>.fromHandlers(
        handleError: (e, stackTrace, sink) {
          requestStreamError ??= e;
          sink.addError(e, stackTrace);
        },
      )));
      final upstream = await outgoing.close().timeout(config.timeout);

      final upstreamStatus = upstream.statusCode;
      final hidden = hide && CorsProxyProtocol.redirectStatuses.contains(upstreamStatus);
      status = hidden ? HttpStatus.ok : upstreamStatus;
      response
        ..statusCode = status
        ..reasonPhrase = hidden ? 'OK' : upstream.reasonPhrase
        ..bufferOutput = false;
      final exposed = <String>{};
      final cookies = <String>[];
      upstream.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower == 'set-cookie') cookies.addAll(values);
        if (RecorderHeaders.dropFromResponse(lower) || lower.startsWith('access-control-') || CorsProxyProtocol.isOwnHeader(lower)) return;
        if (_headerToken.hasMatch(lower) && lower != 'set-cookie' && lower != 'set-cookie2') exposed.add(lower);
        for (final value in values) {
          try {
            response.headers.add(name, value);
          } catch (_) {
            // A value Dart refuses (a stray control character) is dropped, not fatal.
          }
        }
      });
      if (cookies.isNotEmpty) {
        response.headers.set(CorsProxyProtocol.setCookieHeader, CorsProxyProtocol.encodeSetCookies(cookies));
        exposed.add(CorsProxyProtocol.setCookieHeader.toLowerCase());
      }
      if (hidden) {
        response.headers
          ..set(CorsProxyProtocol.statusHeader, '$upstreamStatus')
          ..set(CorsProxyProtocol.statusTextHeader, _oneLine(upstream.reasonPhrase));
        exposed
          ..add(CorsProxyProtocol.statusHeader.toLowerCase())
          ..add(CorsProxyProtocol.statusTextHeader.toLowerCase());
      }
      if (corsOrigin != null) _addCors(response.headers, corsOrigin, expose: exposed);
      final bodyless = method == 'HEAD' || upstreamStatus < 200 || upstreamStatus == HttpStatus.noContent || upstreamStatus == HttpStatus.notModified;
      // A known length is passed on as it is; an unknown one stays chunked, which Dart does by itself.
      if (upstream.contentLength >= 0 && (!bodyless || method == 'HEAD') && upstreamStatus >= 200) {
        response.contentLength = upstream.contentLength;
      }
      committed = true;
      if (bodyless) {
        await upstream.drain<void>();
      } else {
        await response.addStream(upstream.timeout(config.timeout));
      }
      await _closeQuietly(response);
    } catch (e) {
      final failure = requestStreamError != null
          ? const _Failure('request_interrupted', 'The page closed the connection before it finished sending the request.')
          : _describeFailure(e, uri, config);
      error = failure.code;
      if (!committed) {
        status = HttpStatus.badGateway;
        _answerItself(response, status, {
          'error': failure.code,
          'message': failure.message,
          'proxy': 'PostPilot CORS proxy',
        }, errorCode: failure.code, corsOrigin: corsOrigin);
        await _closeQuietly(response);
      }
      // Once the answer has begun nothing can change its status; Dart drops the connection after the broken body, which is
      // how the page learns it was cut short.
      try {
        outgoing?.abort();
      } catch (_) {}
    } finally {
      if (outgoing != null) _inFlight.remove(outgoing);
    }
    publish(host, path, status, error);
  }

  void _answerPreflight(HttpRequest request, String origin) {
    final response = request.response;
    final requestedHeaders = _single(request.headers, 'access-control-request-headers');
    final requestedMethod = _single(request.headers, 'access-control-request-method')?.trim().toUpperCase();
    final headers = [
      '*',
      // A wildcard never covers `Authorization`, so what the page asked for is listed as well.
      if (requestedHeaders != null)
        for (final name in requestedHeaders.split(','))
          if (_headerToken.hasMatch(name.trim())) name.trim(),
    ];
    final methods = {..._methods.split(', '), if (requestedMethod != null && _headerToken.hasMatch(requestedMethod)) requestedMethod};
    response
      ..statusCode = HttpStatus.noContent
      ..headers.set('access-control-allow-origin', origin)
      ..headers.add('vary', 'Origin')
      ..headers.add('vary', 'Access-Control-Request-Headers')
      ..headers.set('access-control-allow-methods', methods.join(', '))
      ..headers.set('access-control-allow-headers', headers.join(', '))
      ..headers.set('access-control-max-age', '600')
      // Chrome asks before a public page may reach a private address such as this computer.
      ..headers.set('access-control-allow-private-network', 'true')
      ..headers.set('x-postpilot-proxy', 'preflight');
  }

  static void _addCors(HttpHeaders headers, String origin, {Iterable<String> expose = const []}) {
    headers
      ..set('access-control-allow-origin', origin)
      ..add('vary', 'Origin')
      // The address the browser requests names only the proxy and the path of the real one; without this a cache would serve
      // `?page=1` for `?page=2`, or the staging answer for the same path on production.
      ..add('vary', CorsProxyProtocol.urlHeader)
      ..set('access-control-allow-headers', '*')
      ..set('access-control-allow-methods', _methods)
      // `*` is not understood everywhere, so the names are listed as well.
      ..set('access-control-expose-headers', ['*', ...expose].join(', '));
  }

  /// A JSON answer made by the proxy itself (never by a target), marked with `X-PostPilot-Proxy-Error` when it is an error.
  static void _answerItself(HttpResponse response, int status, Map<String, Object?> body, {String? errorCode, String? corsOrigin}) {
    final bytes = utf8.encode(jsonEncode(body));
    try {
      response
        ..statusCode = status
        ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
        ..headers.set('cache-control', 'no-store')
        ..contentLength = bytes.length;
      if (errorCode != null) response.headers.set(CorsProxyProtocol.errorHeader, errorCode);
      if (corsOrigin != null) {
        _addCors(response.headers, corsOrigin, expose: [CorsProxyProtocol.errorHeader.toLowerCase()]);
      }
      response.add(bytes);
    } catch (_) {
      // The answer had begun, or the page is gone.
    }
  }

  static Future<void> _closeQuietly(HttpResponse response) async {
    try {
      await response.close();
    } catch (_) {
      // The page went away before the answer was written.
    }
  }

  static void _forwardRequestHeaders(HttpRequest request, HttpClientRequest out) {
    // Dart's HttpClient adds `Accept-Encoding: gzip` to every request, even with autoUncompress off. The page decides what it
    // accepts: without this the target would compress for a page that never asked it to.
    out.headers.removeAll(HttpHeaders.acceptEncodingHeader);
    request.headers.forEach((name, values) {
      final lower = name.toLowerCase();
      // `Origin`, `Referer` and the `Sec-` headers describe the web page, not the call it makes for the person: a real API
      // client sends none of them, and a server that checks the origin would refuse the call.
      if (RecorderHeaders.dropFromRequest(lower) ||
          lower == 'origin' ||
          lower == 'referer' ||
          lower.startsWith('sec-') ||
          lower.startsWith('access-control-request-') ||
          CorsProxyProtocol.isOwnHeader(lower)) {
        return;
      }
      for (final value in values) {
        try {
          out.headers.add(name, value);
        } catch (_) {
          // A value Dart refuses (a stray control character) is dropped, not fatal.
        }
      }
    });
  }

  /// The body is streamed, so its length is passed on as the page announced it (or chunked, when it did not).
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

  /// `host[:port]` and the path with its query masked, for the log.
  static (String host, String path) _describe(Uri uri) {
    final clean = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path.isEmpty ? '/' : uri.path,
      query: uri.hasQuery ? uri.query : null,
    );
    final masked = SecretMasker.maskUrl(clean.toString());
    final rest = masked.substring(masked.indexOf('://') + 3);
    final slash = rest.indexOf('/');
    return slash < 0 ? (rest, '') : (rest.substring(0, slash), rest.substring(slash));
  }

  /// The path of a call the proxy refused before it knew its target, with the query masked.
  static String _safePath(Uri uri) => SecretMasker.maskUrl(uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);

  /// All values of a header as one text (`HttpHeaders.value` throws when a name is repeated).
  static String? _single(HttpHeaders headers, String name) => headers[name]?.join(', ');

  static String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// The host of a `Host` header (`localhost:8787`, `[::1]:8787`) without its port or brackets.
  static String? _hostOf(String? hostHeader) {
    final value = hostHeader?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('[')) {
      final end = value.indexOf(']');
      return end < 0 ? value : value.substring(1, end);
    }
    final colon = value.lastIndexOf(':');
    return colon < 0 ? value : value.substring(0, colon);
  }

  static bool _isLoopbackHost(String? host) {
    if (host == null) return true;
    final h = host.toLowerCase();
    return h == 'localhost' || h.endsWith('.localhost') || h == '::1' || RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(h);
  }

  static String _readable(Duration d) => d.inSeconds >= 1 ? '${d.inSeconds} seconds' : '${d.inMilliseconds} ms';

  static _Failure _describeFailure(Object e, Uri target, CorsProxyConfig config) {
    final where = RecorderHeaders.authorityOf(target);
    if (e is TimeoutException) {
      return _Failure('upstream_timeout', '$where did not answer within ${_readable(config.timeout)}. Is the server running and reachable from this computer?');
    }
    if (e is TlsException) {
      final osMessage = e.osError?.message ?? '';
      return _Failure(
        'upstream_tls',
        'Could not make a secure connection to $where: its certificate was rejected (${_oneLine(osMessage.isEmpty ? e.message : osMessage)}). '
            'If you trust this server (a test or self-signed one), restart the proxy with --insecure.',
      );
    }
    if (e is SocketException) {
      final os = e.osError;
      final text = '${e.message} ${os?.message ?? ''}'.toLowerCase();
      final code = os?.errorCode;
      if (text.contains('failed host lookup') || text.contains('no such host') || text.contains('nodename nor servname') || code == 11001) {
        return _Failure('upstream_unknown_host', 'Could not find the host of $where. Check the address and this computer\'s network connection.');
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
    return _Failure('proxy_error', 'The proxy failed while forwarding this call to $where (${e.runtimeType}).');
  }
}

final class _Failure {
  final String code;
  final String message;
  const _Failure(this.code, this.message);
}
