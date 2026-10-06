import 'dart:async';
import 'dart:typed_data';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../features/git_sync/domain/services/secret_names.dart';
import '../errors/app_exception.dart';
import 'api_client.dart';
import 'api_http_response.dart';
import 'http_adapter_config.dart';
import 'lenient_cookie_manager.dart';
import 'network_failure.dart';

typedef NetworkAdapterFactory = HttpClientAdapter Function({required bool verifySsl, required ProxyConfig proxy});

final class DioApiClient implements ApiClient {
  static const _redirectStatuses = {301, 302, 303, 307, 308};

  final Dio _dio;
  final CookieJar cookieJar;

  // dio_cookie_manager asserts against use on web — the browser owns cookie
  // handling for XHR/fetch requests there, so a manual CookieJar doesn't apply.
  DioApiClient({CookieJar? cookieJar, NetworkAdapterFactory adapterFactory = createNetworkAdapter})
      : cookieJar = cookieJar ?? CookieJar(),
        _dio = Dio(BaseOptions(
          // The body is read by hand so a size cap can stop the download.
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
          // Followed by hand, see _sendFollowingRedirects.
          followRedirects: false,
        )) {
    _dio.httpClientAdapter = _ConfiguredAdapter(adapterFactory);
    if (!kIsWeb) {
      _dio.interceptors.add(LenientCookieManager(this.cookieJar));
    }
  }

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await _sendFollowingRedirects(spec, stopwatch);
    } on DioException catch (e) {
      // Dio leaves `message` null when it merely wraps a foreign error (bad
      // scheme or host, TLS handshake failure); the cause lives in `error`.
      final proxy = spec.options.proxy;
      final message = _withoutProxyCredentials(e.message ?? e.error?.toString() ?? 'Network request failed.', proxy);
      throw NetworkException(
        NetworkFailure.isCertificateProblem(e) ? '$message\n\n${NetworkFailure.certificateHint}' : message,
        kind: _kindOf(e.type),
        summary: _withoutProxyCredentials(NetworkFailure.summarize(e, spec.options), proxy),
      );
    }
  }

  /// `dart:io` quotes a proxy directive it cannot use, `user:password@` part
  /// included; the message ends up in the error banner and the Console log.
  String _withoutProxyCredentials(String message, ProxyConfig proxy) {
    if (proxy.username.isEmpty || proxy.password.isEmpty) return message;
    return message.replaceAll('${proxy.username}:${proxy.password}@', '${proxy.username}:***@');
  }

  /// Follows redirects hop by hop instead of letting dart:io do it inside one
  /// request, so each hop's `Set-Cookie` reaches the cookie manager and each
  /// hop carries the cookies stored for its own host.
  Future<ApiHttpResponse> _sendFollowingRedirects(ApiRequestSpec spec, Stopwatch stopwatch) async {
    final options = spec.options;
    var method = spec.method.toUpperCase();
    var url = spec.url;
    var body = spec.body;
    final headers = {...spec.headers};
    final timeout = options.timeout ?? Duration.zero;

    for (var followed = 0;; followed++) {
      // One token per hop: cancelling it is also how the rest of a body that
      // is not wanted (a redirect's, or what lies past the size cap) is
      // dropped without downloading it.
      final hopToken = CancelToken();
      unawaited(spec.cancelToken?.whenCancelled.then((_) => hopToken.cancel()));
      final response = await _dio.request<ResponseBody>(
        url,
        data: body,
        options: Options(
          method: method,
          headers: headers,
          connectTimeout: timeout,
          receiveTimeout: timeout,
          extra: {_ConfiguredAdapter.networkKey: (verifySsl: options.verifySsl, proxy: options.proxy)},
        ),
        cancelToken: hopToken,
      );

      final target = options.followRedirects ? _redirectTarget(response) : null;
      if (target == null) {
        final read = await _readBody(response, options.maxResponseBytes, hopToken);
        stopwatch.stop();
        return ApiHttpResponse(
          statusCode: response.statusCode ?? 0,
          statusMessage: response.statusMessage ?? '',
          headers: {
            for (final entry in response.headers.map.entries) entry.key: entry.value.join(', '),
          },
          bodyBytes: read.bytes,
          duration: stopwatch.elapsed,
          truncated: read.truncated,
          setCookies: List.unmodifiable(response.headers['set-cookie'] ?? const <String>[]),
        );
      }
      hopToken.cancel();
      if (followed >= options.maxRedirects) {
        throw NetworkException('Too many redirects (limit ${options.maxRedirects}).');
      }

      if (_redirectsAsGet(response.statusCode, method)) {
        method = 'GET';
        body = null;
        headers.removeWhere((name, _) => name.toLowerCase().startsWith('content-'));
      }
      final keepsCredentials = _keepsCredentials(response.requestOptions.uri, target);
      headers.removeWhere((name, _) => name.toLowerCase() == 'host' || (!keepsCredentials && _carriesCredential(name)));
      url = target.toString();
    }
  }

  Future<({Uint8List bytes, bool truncated})> _readBody(
    Response<ResponseBody> response,
    int? limit,
    CancelToken hopToken,
  ) async {
    final builder = BytesBuilder(copy: false);
    var truncated = false;
    try {
      await for (final chunk in response.data?.stream ?? const Stream<Uint8List>.empty()) {
        if (limit != null && builder.length + chunk.length > limit) {
          builder.add(Uint8List.sublistView(chunk, 0, limit - builder.length));
          truncated = true;
          break;
        }
        builder.add(chunk);
      }
    } on DioException {
      rethrow;
    } catch (e, stackTrace) {
      // What the transformer used to do when the connection drops mid-body.
      throw DioException(requestOptions: response.requestOptions, error: e, stackTrace: stackTrace);
    }
    if (truncated) hopToken.cancel();
    return (bytes: builder.takeBytes(), truncated: truncated);
  }

  /// Where [response] sends the client next, or null when it is not a
  /// redirect to follow: another status, no usable `Location`, or a non-http
  /// scheme (an app deep link), which the user should see instead.
  Uri? _redirectTarget(Response<ResponseBody> response) {
    if (!_redirectStatuses.contains(response.statusCode)) return null;
    final location = response.headers['location']?.firstOrNull;
    if (location == null || location.isEmpty) return null;
    final target = Uri.tryParse(location);
    if (target == null) return null;
    final resolved = response.requestOptions.uri.resolveUri(target);
    return resolved.scheme == 'http' || resolved.scheme == 'https' ? resolved : null;
  }

  /// RFC 9110 §15.4: 303 turns anything but HEAD into a GET, and 301/302
  /// turn a POST into one; 307/308 replay the method and body untouched.
  bool _redirectsAsGet(int? status, String method) => switch (status) {
        303 => method != 'GET' && method != 'HEAD',
        301 || 302 => method == 'POST',
        _ => false,
      };

  /// dart:io's own rule for a followed redirect: `Authorization` and `Cookie`
  /// only travel to the same scheme and port on the same host or a subdomain.
  /// A header the user added to carry a credential (`X-API-Key`,
  /// `Proxy-Authorization`, `X-Auth-Token`, ...) is held to the same rule: it
  /// would otherwise be handed to whatever host the redirect names.
  bool _keepsCredentials(Uri from, Uri to) =>
      to.scheme == from.scheme && to.port == from.port && (to.host == from.host || to.host.endsWith('.${from.host}'));

  bool _carriesCredential(String header) {
    final lower = header.toLowerCase();
    return lower == 'authorization' || lower == 'cookie' || SecretNames.isSecretHeader(header);
  }

  NetworkErrorKind _kindOf(DioExceptionType type) => switch (type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          NetworkErrorKind.timeout,
        DioExceptionType.connectionError => NetworkErrorKind.connectionError,
        DioExceptionType.badResponse => NetworkErrorKind.badResponse,
        DioExceptionType.cancel => NetworkErrorKind.cancelled,
        _ => NetworkErrorKind.other,
      };
}

typedef _NetworkKey = ({bool verifySsl, ProxyConfig proxy});

/// The one adapter [Dio] holds. Every request names the TLS and proxy setup
/// it needs in its own options, and this adapter hands it to the adapter built
/// for that setup, building it on first use. Swapping `Dio.httpClientAdapter`
/// per send instead would be racy: a second send can swap it again before the
/// first reaches the adapter, and a request that asked for verified TLS would
/// go out on an unverified connection.
///
/// Only the setup used last is kept. An adapter for an older one is closed
/// once nothing is using it: closing sooner cancels the connection attempts of
/// requests still starting on it.
final class _ConfiguredAdapter implements HttpClientAdapter {
  static const networkKey = 'postpilot.network';
  static const _defaultKey = (verifySsl: true, proxy: ProxyConfig.system);

  final NetworkAdapterFactory _factory;
  final Map<_NetworkKey, _Slot> _slots = {};
  _NetworkKey? _latest;

  _ConfiguredAdapter(this._factory);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    // The browser applies neither option, so there is never a reason to
    // rebuild its adapter.
    final key = kIsWeb ? _defaultKey : options.extra[networkKey] as _NetworkKey? ?? _defaultKey;
    final slot = _slots[key] ??= _Slot(_factory(verifySsl: key.verifySsl, proxy: key.proxy));
    _latest = key;
    slot.inFlight++;
    _retireIdle();
    return Future.sync(() => slot.adapter.fetch(options, requestStream, cancelFuture)).whenComplete(() {
      slot.inFlight--;
      _retireIdle();
    });
  }

  void _retireIdle() {
    _slots.removeWhere((key, slot) {
      final retire = slot.inFlight == 0 && key != _latest;
      // Not forced: a response body still streaming from it keeps its connection.
      if (retire) slot.adapter.close();
      return retire;
    });
  }

  @override
  void close({bool force = false}) {
    for (final slot in _slots.values) {
      slot.adapter.close(force: force);
    }
    _slots.clear();
    _latest = null;
  }
}

final class _Slot {
  final HttpClientAdapter adapter;

  /// Requests that have reached [adapter] and not yet got their response headers.
  int inFlight = 0;

  _Slot(this.adapter);
}
