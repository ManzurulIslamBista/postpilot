import 'package:flutter/foundation.dart';
import '../../domain/entities/cookie_entity.dart';
import '../../domain/entities/domain_cookies_entity.dart';
import '../../domain/repositories/cookie_repository.dart';

final class CookiesViewModel with ChangeNotifier {
  final CookieRepository _repository;
  CookiesViewModel(this._repository);

  List<DomainCookiesEntity> domains = [];

  Future<void> load() async {
    domains = await _repository.listByDomain();
    notifyListeners();
  }

  Future<void> deleteCookie(CookieEntity cookie) async {
    await _repository.delete(cookie);
    await load();
  }

  Future<void> clearDomain(String domain) async {
    await _repository.clearDomain(domain);
    await load();
  }

  Future<void> clearAll() async {
    await _repository.clearAll();
    await load();
  }
}
