final class CookieEntity {
  final String name;
  final String value;
  final String domain;
  final String path;
  final DateTime? expires;
  final bool secure;
  final bool httpOnly;

  /// True for cookies set without a `Domain` attribute. The jar keeps those
  /// in a separate host-keyed bucket from domain-shared ones, so deleting a
  /// single cookie has to know which bucket it lives in.
  final bool hostOnly;

  const CookieEntity({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.expires,
    required this.secure,
    required this.httpOnly,
    required this.hostOnly,
  });
}
