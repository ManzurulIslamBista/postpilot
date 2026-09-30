import 'cookie_entity.dart';

final class DomainCookiesEntity {
  final String domain;
  final List<CookieEntity> cookies;

  const DomainCookiesEntity({required this.domain, required this.cookies});
}
