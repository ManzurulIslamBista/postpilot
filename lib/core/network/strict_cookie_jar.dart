import 'package:cookie_jar/cookie_jar.dart';

/// [DefaultCookieJar] corrected to send only what RFC 6265 allows: the stock
/// jar still returns expired `Secure` cookies over https, and unexpired
/// `Secure` cookies over plain http.
final class StrictCookieJar extends DefaultCookieJar {
  @override
  Future<List<Cookie>> loadForRequest(Uri uri) async {
    purgeExpired();
    final cookies = await super.loadForRequest(uri);
    if (uri.scheme == 'https') return cookies;
    return [for (final cookie in cookies) if (!cookie.secure) cookie];
  }

  /// Removes expired cookies from the jar itself, not just from a listing, so
  /// what the cookies dialog shows is exactly what a request would carry.
  void purgeExpired() {
    if (ignoreExpires) return;
    for (final store in [hostCookies, domainCookies]) {
      for (final paths in store.values) {
        for (final cookies in paths.values) {
          cookies.removeWhere((_, stored) => stored.isExpired());
        }
      }
    }
  }
}
