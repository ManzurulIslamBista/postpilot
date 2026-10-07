import '../entities/recorded_exchange.dart';

/// Why a recorded call is left out of a collection.
enum NoiseReason {
  /// The recorder answered it itself (upstream failure, refused WebSocket): not a call of the app's API.
  notForwarded('not forwarded'),
  staticAsset('static files'),
  analytics('analytics'),
  preflight('CORS preflights'),

  /// PostPilot cannot send a request with this method.
  unsupportedMethod('unsupported methods');

  const NoiseReason(this.label);

  final String label;
}

/// Tells the calls worth keeping from the ones every app makes on the side.
abstract final class NoiseFilter {
  static const staticExtensions = {
    'js', 'mjs', 'css', 'map', 'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'ico', 'bmp', 'avif', 'woff', 'woff2', 'ttf', 'otf',
    'eot', 'mp3', 'mp4', 'webm', 'ogg', 'wav', 'm4a', 'wasm',
  };

  /// A call to one of these hosts (or a subdomain) is telemetry, not the app's API.
  static const analyticsHosts = [
    'google-analytics.com',
    'analytics.google.com',
    'googletagmanager.com',
    'doubleclick.net',
    'googlesyndication.com',
    'app-measurement.com',
    'firebaselogging-pa.googleapis.com',
    'firebase-settings.crashlytics.com',
    'crashlytics.com',
    'segment.io',
    'segment.com',
    'mixpanel.com',
    'amplitude.com',
    'sentry.io',
    'bugsnag.com',
    'hotjar.com',
    'fullstory.com',
    'clarity.ms',
    'appsflyer.com',
    'adjust.com',
    'branch.io',
    'datadoghq.com',
    'newrelic.com',
    'nr-data.net',
    'logrocket.com',
    'posthog.com',
    'connect.facebook.net',
  ];

  /// The reason [exchange] is noise, null when it is worth keeping. A call the recorder did not forward is always noise; the
  /// others only when their switch is on.
  static NoiseReason? reasonFor(
    RecordedExchange exchange, {
    bool skipAssets = true,
    bool skipAnalytics = true,
    bool skipPreflights = true,
  }) {
    if (exchange.kind != RecordedKind.proxied) return NoiseReason.notForwarded;
    if (skipPreflights && isPreflight(exchange)) return NoiseReason.preflight;
    if (skipAssets && isStaticAsset(exchange.path)) return NoiseReason.staticAsset;
    if (skipAnalytics && isAnalyticsHost(exchange.host)) return NoiseReason.analytics;
    return null;
  }

  /// A browser's CORS preflight: an `OPTIONS` that asks which method the real call may use.
  static bool isPreflight(RecordedExchange e) =>
      e.method == 'OPTIONS' && e.requestHeader('access-control-request-method') != null;

  static bool isStaticAsset(String pathWithQuery) {
    final path = pathWithQuery.split('?').first;
    final lastSegment = path.split('/').last;
    final dot = lastSegment.lastIndexOf('.');
    if (dot <= 0 || dot == lastSegment.length - 1) return false;
    return staticExtensions.contains(lastSegment.substring(dot + 1).toLowerCase());
  }

  static bool isAnalyticsHost(String host) {
    final h = host.toLowerCase();
    return analyticsHosts.any((a) => h == a || h.endsWith('.$a'));
  }
}
