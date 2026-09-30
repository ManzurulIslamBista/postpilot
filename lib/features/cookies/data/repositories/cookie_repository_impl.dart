import 'dart:math' show min;
import 'package:cookie_jar/cookie_jar.dart';
import '../../../../core/network/strict_cookie_jar.dart';
import '../../domain/entities/cookie_entity.dart';
import '../../domain/entities/domain_cookies_entity.dart';
import '../../domain/repositories/cookie_repository.dart';

typedef _CookieStore = Map<String, Map<String, Map<String, SerializableCookie>>>;

/// Reads [StrictCookieJar]'s in-memory buckets directly: the [CookieJar]
/// interface only answers "cookies for this URI", which can't enumerate
/// everything stored. Any other jar (e.g. the no-op web one) lists as empty.
final class CookieRepositoryImpl implements CookieRepository {
  // Seconds. Keeps whatever Max-Age a server sends inside DateTime's range
  // (±8.64e15 ms), which would otherwise throw.
  static const _maxAgeCap = 8000000000000;

  final CookieJar _jar;
  const CookieRepositoryImpl(this._jar);

  @override
  Future<List<DomainCookiesEntity>> listByDomain() async {
    final jar = _jar;
    if (jar is! StrictCookieJar) return const [];
    jar.purgeExpired();

    final byDomain = <String, List<CookieEntity>>{};
    void collect(_CookieStore store, {required bool hostOnly}) {
      store.forEach((domain, paths) {
        paths.forEach((path, cookies) {
          for (final stored in cookies.values) {
            byDomain
                .putIfAbsent(domain, () => [])
                .add(_toEntity(stored, domain: domain, path: path, hostOnly: hostOnly));
          }
        });
      });
    }

    collect(jar.hostCookies, hostOnly: true);
    collect(jar.domainCookies, hostOnly: false);

    final domains = byDomain.keys.toList()..sort();
    return [
      for (final domain in domains) DomainCookiesEntity(domain: domain, cookies: byDomain[domain]!..sort(_byPathThenName)),
    ];
  }

  @override
  Future<void> delete(CookieEntity cookie) async {
    final jar = _jar;
    if (jar is! StrictCookieJar) return;
    final store = cookie.hostOnly ? jar.hostCookies : jar.domainCookies;
    final paths = store[cookie.domain];
    final names = paths?[cookie.path];
    if (paths == null || names == null) return;
    names.remove(cookie.name);
    if (names.isEmpty) paths.remove(cookie.path);
    if (paths.isEmpty) store.remove(cookie.domain);
  }

  @override
  Future<void> clearDomain(String domain) async {
    final jar = _jar;
    if (jar is! StrictCookieJar) return;
    jar.hostCookies.remove(domain);
    jar.domainCookies.remove(domain);
  }

  @override
  Future<void> clearAll() => _jar.deleteAll();

  static int _byPathThenName(CookieEntity a, CookieEntity b) {
    final byPath = a.path.compareTo(b.path);
    return byPath != 0 ? byPath : a.name.compareTo(b.name);
  }

  // The jar's map keys are the canonical domain (leading dot stripped) and
  // path (defaulted when absent) — the raw Cookie's own fields may be null or
  // dotted, and deletion has to match the keys.
  CookieEntity _toEntity(SerializableCookie stored, {required String domain, required String path, required bool hostOnly}) =>
      CookieEntity(
        name: stored.cookie.name,
        value: stored.cookie.value,
        domain: domain,
        path: path,
        expires: _expiryOf(stored),
        secure: stored.cookie.secure,
        httpOnly: stored.cookie.httpOnly,
        hostOnly: hostOnly,
      );

  // Max-Age outranks Expires (RFC 6265 §5.3) and counts from the moment the
  // jar stored the cookie, so a Max-Age-only cookie still has a real expiry.
  DateTime? _expiryOf(SerializableCookie stored) {
    final maxAge = stored.cookie.maxAge;
    if (maxAge == null) return stored.cookie.expires;
    final seconds = min(maxAge, _maxAgeCap);
    return DateTime.fromMillisecondsSinceEpoch((stored.createTimeStamp + seconds) * 1000);
  }
}
