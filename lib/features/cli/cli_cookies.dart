// Pure Dart (no Flutter): this runs from `bin/postpilot.dart` in a terminal or a CI job.
import 'workspace_runner.dart';

/// The cookies of one run of the command line, kept in memory like the app's cookie jar: a request that logs in
/// (Odoo's `/web/session/authenticate` answers with a `session_id` cookie) is followed by requests that send it. Cookies
/// are kept per origin (scheme, host and port), so a session is never sent to another server, and nothing is written
/// to disk.
final class CliCookieJar {
  final Map<String, Map<String, String>> _byOrigin = {};

  /// [send] with this jar around it: the cookies kept for the request's origin are added (unless the request has a
  /// `Cookie` header of its own, which is sent as written), and the cookies of the answer are kept.
  CliSend wrap(CliSend send) => (request) async {
        final cookie = request.headers.keys.any((name) => name.toLowerCase() == 'cookie') ? null : cookieHeader(request.url);
        final response = await send(cookie == null ? request : request.withHeaders({...request.headers, 'Cookie': cookie}));
        store(request.url, response.headers);
        return response;
      };

  /// `name=value; name=value` of the cookies kept for [url]'s origin; null when there are none.
  String? cookieHeader(String url) {
    final kept = _byOrigin[_originOf(url)];
    if (kept == null || kept.isEmpty) return null;
    return kept.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Keeps the cookies a response sets. [headers] holds `Set-Cookie` with the cookies joined by `, ` (an `Expires`
  /// date holds a comma too, which is why a cookie starts only where a `name=` follows the comma). An empty value or
  /// a `Max-Age` of zero or less deletes the cookie, which is how a server ends a session.
  void store(String url, Map<String, String> headers) {
    final joined = headers.entries.where((e) => e.key.toLowerCase() == 'set-cookie').map((e) => e.value).join(', ');
    if (joined.isEmpty) return;
    final origin = _originOf(url);
    final kept = _byOrigin.putIfAbsent(origin, () => {});
    for (final cookie in joined.split(RegExp(r"""[,]\s*(?=[A-Za-z0-9!#$%&'*+.^_`|~-]+=)"""))) {
      final parts = cookie.split(';');
      final pair = parts.first.trim();
      final equals = pair.indexOf('=');
      if (equals <= 0) continue;
      final name = pair.substring(0, equals);
      final value = pair.substring(equals + 1);
      final maxAge = parts
          .skip(1)
          .map((p) => RegExp(r'^\s*max-age\s*=\s*(-?\d+)\s*$', caseSensitive: false).firstMatch(p))
          .whereType<RegExpMatch>()
          .map((m) => int.parse(m[1]!))
          .firstOrNull;
      if (value.isEmpty || (maxAge != null && maxAge <= 0)) {
        kept.remove(name);
      } else {
        kept[name] = value;
      }
    }
  }

  static String _originOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}:${uri.hasPort ? uri.port : (uri.scheme.toLowerCase() == 'https' ? 443 : 80)}';
  }
}
