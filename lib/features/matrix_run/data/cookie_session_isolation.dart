import 'package:cookie_jar/cookie_jar.dart';
import '../domain/services/matrix_session_isolation.dart';

/// Runs a column with an empty cookie jar and gives the person's cookies back afterwards. It works on the app's cookie
/// jar when that keeps its cookies in the two buckets of a [DefaultCookieJar] (the desktop and mobile builds); a jar that
/// does not (the browser owns the cookies of the web build) is left alone, and the body just runs.
final class CookieSessionIsolation implements MatrixSessionIsolation {
  final CookieJar _jar;

  const CookieSessionIsolation(this._jar);

  @override
  Future<T> isolated<T>(Future<T> Function() body) async {
    final jar = _jar;
    if (jar is! DefaultCookieJar) return body();
    final host = _copy(jar.hostCookies);
    final domain = _copy(jar.domainCookies);
    jar.hostCookies.clear();
    jar.domainCookies.clear();
    try {
      return await body();
    } finally {
      jar.hostCookies
        ..clear()
        ..addAll(host);
      jar.domainCookies
        ..clear()
        ..addAll(domain);
    }
  }

  /// A copy that does not share the inner maps with the jar, which goes on mutating them.
  static Map<String, Map<String, Map<String, SerializableCookie>>> _copy(Map<String, Map<String, Map<String, SerializableCookie>>> store) => {
        for (final domain in store.entries)
          domain.key: {
            for (final path in domain.value.entries) path.key: {...path.value},
          },
      };
}
