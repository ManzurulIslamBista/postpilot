import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

/// A [CookieManager] whose cookie handling can never fail a request. The
/// stock one rejects the whole call, discarding the real response, when
/// Dart's strict cookie parser refuses a single `Set-Cookie` — or the user's
/// own `Cookie` header, which it re-parses. `ignoreInvalidCookies` is no fix:
/// it only covers `HttpException`, while the parser also throws
/// `FormatException`.
final class LenientCookieManager extends CookieManager {
  LenientCookieManager(super.cookieJar);

  /// The request's own `Cookie` header, forwarded as typed and never parsed,
  /// followed by the jar's cookies for its URL.
  @override
  Future<String> loadCookies(RequestOptions options) async {
    final own = '${options.headers['cookie'] ?? ''}'.trim().replaceFirst(RegExp(r'[;\s]+$'), '');
    var stored = '';
    try {
      stored = CookieManager.getCookies(await cookieJar.loadForRequest(options.uri));
    } catch (_) {
      // The jar is best-effort; the request still goes out with its own header.
    }
    return [own, stored].where((part) => part.isNotEmpty).join('; ');
  }

  /// Saves every `Set-Cookie` the parser accepts and skips the rest, the way
  /// Postman ignores a cookie it can't store.
  @override
  Future<void> saveCookies(Response response) async {
    final cookies = <Cookie>[];
    for (final value in response.headers['set-cookie'] ?? const <String>[]) {
      try {
        cookies.add(Cookie.fromSetCookieValue(value));
      } catch (_) {
        // Unparsable cookie: dropped, the others and the response still count.
      }
    }
    if (cookies.isEmpty) return;
    try {
      await cookieJar.saveFromResponse(response.requestOptions.uri, cookies);
    } catch (_) {
      // Same best-effort rule as loading.
    }
  }
}
