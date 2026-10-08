import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../features/cors_proxy/domain/cors_proxy_protocol.dart';
import '../../features/cors_proxy/domain/cors_proxy_settings.dart';
import '../errors/app_exception.dart';

/// The proxy to use right now; null sends the call straight to its server. Asked for every call, so switching the proxy on or
/// off takes effect at once (and may wait for the saved settings to load).
typedef CorsProxyRouteProvider = FutureOr<CorsProxyRoute?> Function();

/// Why a call through the CORS proxy failed, told in words that name the proxy and what to do about it. Never holds the URL
/// of the call or a header: only the proxy's own address and the sentence the proxy sent.
final class CorsProxyFailure implements Exception {
  final String code;
  final String message;

  /// The proxy could not be reached at all (not running, or the browser blocked its answer), as against one that answered
  /// with a refusal.
  final bool unreachable;

  const CorsProxyFailure(this.code, this.message, {this.unreachable = false});

  factory CorsProxyFailure.unreachable(CorsProxyRoute route) => CorsProxyFailure(
        'proxy_unreachable',
        'The CORS proxy at ${route.authority} did not answer, or the browser blocked its answer. Check that it is running '
            '("${CorsProxyProtocol.command}") and press Test connection in Settings > CORS proxy.',
        unreachable: true,
      );

  NetworkHelp get help => NetworkHelp.corsProxy;

  @override
  String toString() => message;
}

/// Sends the calls of a web page through the CORS proxy: the page asks the proxy, which asks the real server and adds the CORS
/// headers the server lacks. Wraps the platform's adapter; a call the proxy does not carry (not http(s), or addressed to the
/// proxy itself) and every call while no route is set go straight to [_inner].
///
/// What the browser hides from a page is brought back: `Set-Cookie` lines arrive in one header of their own, and a redirect
/// arrives as a 200 that names its real status, because a browser follows a 3xx by itself and never shows it to the page.
/// The redirect handling of `DioApiClient` then works as it does on a desktop.
final class CorsProxyAdapter implements HttpClientAdapter {
  final HttpClientAdapter _inner;
  final CorsProxyRouteProvider _route;

  CorsProxyAdapter(this._inner, this._route);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final route = await _route();
    if (route == null || !route.proxies(options.uri)) return _inner.fetch(options, requestStream, cancelFuture);
    final ResponseBody body;
    try {
      body = await _inner.fetch(proxiedOptions(options, route), requestStream, cancelFuture);
    } on DioException catch (e) {
      // The browser reports a proxy that is down, and one whose answer it blocked, as the same opaque error. Anything else
      // (a timeout, a cancel) is told as it is, about the call the person made: the rewritten options name the proxy as the
      // server and hold its token.
      if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.unknown) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: CorsProxyFailure.unreachable(route),
          message: CorsProxyFailure.unreachable(route).message,
        );
      }
      throw e.copyWith(requestOptions: options);
    }
    return restoreResponse(body, options);
  }

  /// [options] rewritten to ask the proxy for the same call: the proxy's address, the real address, the token and the request
  /// to hide redirects. Everything else (method, body, other headers, timeouts) is kept.
  static RequestOptions proxiedOptions(RequestOptions options, CorsProxyRoute route) {
    final target = options.uri;
    final ours = {
      CorsProxyProtocol.urlHeader.toLowerCase(),
      CorsProxyProtocol.tokenHeader.toLowerCase(),
      CorsProxyProtocol.redirectsHeader.toLowerCase(),
    };
    final headers = <String, dynamic>{
      for (final e in options.headers.entries)
        if (!ours.contains(e.key.toLowerCase())) e.key: e.value,
      CorsProxyProtocol.urlHeader: _ascii(target.toString()),
      if (route.token.isNotEmpty) CorsProxyProtocol.tokenHeader: route.token,
      CorsProxyProtocol.redirectsHeader: CorsProxyProtocol.redirectsManual,
    };
    return options.copyWith(
      baseUrl: '',
      path: route.endpointFor(target).toString(),
      queryParameters: <String, dynamic>{},
      headers: headers,
    );
  }

  /// [body] as the real server sent it: the real status of a hidden redirect, the `Set-Cookie` lines, none of the proxy's own
  /// headers. An answer the proxy made itself (a refusal, a server it could not reach) is thrown as a [CorsProxyFailure]
  /// instead, so it is not mistaken for the server's own answer.
  static Future<ResponseBody> restoreResponse(ResponseBody body, RequestOptions original) async {
    final headers = <String, List<String>>{};
    body.headers.forEach((name, values) => headers.putIfAbsent(name.toLowerCase(), () => []).addAll(values));

    final proxyError = headers[CorsProxyProtocol.errorHeader.toLowerCase()]?.firstOrNull;
    if (proxyError != null) {
      final failure = await _failureOf(body, proxyError);
      throw DioException(requestOptions: original, type: DioExceptionType.connectionError, error: failure, message: failure.message);
    }

    var status = body.statusCode;
    var statusMessage = body.statusMessage;
    final realStatus = int.tryParse(headers.remove(CorsProxyProtocol.statusHeader.toLowerCase())?.firstOrNull ?? '');
    final realText = headers.remove(CorsProxyProtocol.statusTextHeader.toLowerCase())?.firstOrNull;
    if (realStatus != null && CorsProxyProtocol.redirectStatuses.contains(realStatus)) {
      status = realStatus;
      statusMessage = realText ?? statusMessage;
    }
    final cookies = headers.remove(CorsProxyProtocol.setCookieHeader.toLowerCase());
    if (cookies != null) {
      headers['set-cookie'] = [for (final value in cookies) ...CorsProxyProtocol.decodeSetCookies(value)];
    }
    headers.removeWhere((name, _) => CorsProxyProtocol.isOwnHeader(name));
    // Changed in place: the adapter's own clean-up (`close`) and extras stay attached to the body.
    return body
      ..statusCode = status
      ..statusMessage = statusMessage
      ..headers = headers;
  }

  static Future<CorsProxyFailure> _failureOf(ResponseBody body, String code) async {
    var text = '';
    try {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in body.stream) {
        bytes.add(chunk);
        if (bytes.length > 16 * 1024) break;
      }
      final json = jsonDecode(utf8.decode(bytes.takeBytes(), allowMalformed: true));
      if (json is Map && json['message'] is String) text = (json['message'] as String).trim();
    } catch (_) {
      // A body that is not the proxy's JSON still has its code.
    }
    if (text.isEmpty) text = 'The proxy refused the call ($code).';
    final forwarding = code.startsWith('upstream_') || code == 'proxy_error' || code == 'request_interrupted';
    return CorsProxyFailure(code, forwarding ? 'The CORS proxy could not forward the call. $text' : text);
  }

  /// A header value is ASCII; a URL with characters beyond it is percent-encoded.
  static String _ascii(String url) => url.codeUnits.any((u) => u > 0x7e || u < 0x20) ? Uri.encodeFull(url) : url;

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
