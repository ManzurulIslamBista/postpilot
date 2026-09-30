import '../entities/cookie_entity.dart';
import '../entities/domain_cookies_entity.dart';

abstract interface class CookieRepository {
  Future<List<DomainCookiesEntity>> listByDomain();

  Future<void> delete(CookieEntity cookie);

  Future<void> clearDomain(String domain);

  Future<void> clearAll();
}
