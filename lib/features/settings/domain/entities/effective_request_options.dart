import '../../../../core/network/api_http_response.dart';
import 'app_settings.dart';
import 'request_settings.dart';

/// The values one request is actually sent with: the request's own override
/// where it has one, the global setting otherwise.
final class EffectiveRequestOptions {
  /// Null waits forever.
  final Duration? timeout;
  final bool followRedirects;
  final int maxRedirects;
  final bool verifySsl;
  final bool sendNoCache;

  /// Null keeps the whole body.
  final int? maxResponseBytes;
  final bool trimKeysAndValues;
  final ProxyConfig proxy;

  /// Null sends any size of upload.
  final int? maxUploadBytes;

  const EffectiveRequestOptions({
    required this.timeout,
    required this.followRedirects,
    required this.maxRedirects,
    required this.verifySsl,
    required this.sendNoCache,
    required this.maxResponseBytes,
    required this.trimKeysAndValues,
    required this.proxy,
    this.maxUploadBytes,
  });

  factory EffectiveRequestOptions.resolve(AppSettings app, RequestSettings? request) {
    final timeoutSeconds = request?.timeoutSeconds ?? app.requestTimeoutSeconds;
    return EffectiveRequestOptions(
      timeout: timeoutSeconds > 0 ? Duration(seconds: timeoutSeconds) : null,
      followRedirects: request?.followRedirects ?? app.followRedirects,
      maxRedirects: app.maxRedirects,
      verifySsl: request?.verifySsl ?? app.verifySsl,
      sendNoCache: request?.sendNoCacheHeader ?? app.sendNoCacheHeader,
      maxResponseBytes: app.maxResponseSizeMb > 0 ? app.maxResponseSizeMb * 1024 * 1024 : null,
      trimKeysAndValues: app.trimKeysAndValues,
      proxy: app.proxy.toConfig(),
      maxUploadBytes: app.maxUploadSizeMb > 0 ? app.maxUploadSizeMb * 1024 * 1024 : null,
    );
  }

  ApiRequestOptions toApiOptions() => ApiRequestOptions(
        timeout: timeout,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        verifySsl: verifySsl,
        proxy: proxy,
        maxResponseBytes: maxResponseBytes,
        maxUploadBytes: maxUploadBytes,
      );
}
