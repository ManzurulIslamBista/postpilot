import 'dart:async';
import 'package:flutter/foundation.dart' show listEquals;
import '../constants/app_constants.dart';

final class ApiHttpResponse {
  final int statusCode;
  final String statusMessage;
  final Map<String, String> headers;
  final List<int> bodyBytes;
  final Duration duration;

  /// True when the body was cut off at [ApiRequestOptions.maxResponseBytes];
  /// [bodyBytes] then holds only the first part.
  final bool truncated;

  const ApiHttpResponse({
    required this.statusCode,
    required this.statusMessage,
    required this.headers,
    required this.bodyBytes,
    required this.duration,
    this.truncated = false,
  });

  int get sizeBytes => bodyBytes.length;
  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Lets a caller abandon a request that is still in flight: the [ApiClient]
/// aborts it and throws a `NetworkException` of kind `cancelled`.
final class ApiCancelToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

enum ProxyMode { none, system, custom }

/// Where a request is routed. [ProxyMode.system] is the proxy the process
/// environment names (`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`), which is also
/// what a plain `dart:io` client does, so it is the default.
final class ProxyConfig {
  static const none = ProxyConfig(mode: ProxyMode.none);
  static const system = ProxyConfig();

  final ProxyMode mode;
  final String host;
  final int port;
  final String username;
  final String password;

  /// Hosts that skip a custom proxy: `example.com` (and its subdomains),
  /// `*.example.com`, `localhost:3000` (one port), or `*` (everything).
  final List<String> bypass;

  const ProxyConfig({
    this.mode = ProxyMode.system,
    this.host = '',
    this.port = 0,
    this.username = '',
    this.password = '',
    this.bypass = const [],
  });

  /// A custom proxy that has somewhere to connect to; without a host and a
  /// valid port there is nothing to route through, so requests go direct.
  bool get isUsableCustom => mode == ProxyMode.custom && host.isNotEmpty && port > 0 && port <= 65535;

  bool bypasses(Uri uri) {
    final host = uri.host.toLowerCase();
    for (final entry in bypass) {
      var pattern = entry.trim().toLowerCase();
      if (pattern.isEmpty) continue;
      final colon = pattern.indexOf(':');
      final port = colon != -1 && colon == pattern.lastIndexOf(':') ? int.tryParse(pattern.substring(colon + 1)) : null;
      if (port != null) {
        if (port != uri.port) continue;
        pattern = pattern.substring(0, colon);
      }
      if (pattern == '*') return true;
      final domain = pattern.startsWith('*.')
          ? pattern.substring(2)
          : pattern.startsWith('.')
              ? pattern.substring(1)
              : pattern;
      if (host == domain || host.endsWith('.$domain')) return true;
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is ProxyConfig &&
      other.mode == mode &&
      other.host == host &&
      other.port == port &&
      other.username == username &&
      other.password == password &&
      listEquals(other.bypass, bypass);

  @override
  int get hashCode => Object.hash(mode, host, port, username, password, Object.hashAll(bypass));
}

/// How the client sends one request. The defaults are the behaviour before
/// these became settings: a 30 second timeout, redirects followed up to 10
/// hops, certificates verified, the environment's proxy, no size cap.
///
/// On the web the browser owns redirects, TLS and proxying, so only
/// [timeout] and [maxResponseBytes] take effect there.
final class ApiRequestOptions {
  /// Null waits forever.
  final Duration? timeout;
  final bool followRedirects;
  final int maxRedirects;
  final bool verifySsl;
  final ProxyConfig proxy;

  /// Null keeps the whole body; otherwise anything past this many bytes is
  /// dropped and the response is marked [ApiHttpResponse.truncated].
  final int? maxResponseBytes;

  const ApiRequestOptions({
    this.timeout = AppConstants.requestTimeout,
    this.followRedirects = true,
    this.maxRedirects = 10,
    this.verifySsl = true,
    this.proxy = ProxyConfig.system,
    this.maxResponseBytes,
  });
}

final class ApiRequestSpec {
  final String method;
  final String url;
  final Map<String, String> headers;
  final Object? body;
  final ApiCancelToken? cancelToken;
  final ApiRequestOptions options;

  const ApiRequestSpec({
    required this.method,
    required this.url,
    this.headers = const {},
    this.body,
    this.cancelToken,
    this.options = const ApiRequestOptions(),
  });
}
