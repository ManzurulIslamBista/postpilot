import 'dart:async';
import 'dart:convert';
import '../../../../core/database/daos/settings_dao.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/settings_json.dart';
import '../../domain/repositories/proxy_password_store.dart';
import '../../domain/repositories/settings_repository.dart';

/// Settings are one JSON value in the database, except the proxy password: it
/// lives in the [ProxyPasswordStore] and the JSON only says that it does
/// (`proxy.passwordInSecureStorage`), so the password never lands in the
/// database file. A password an earlier version left in the JSON is moved into
/// the store on the next [load].
final class SettingsRepositoryImpl implements SettingsRepository {
  static const storageKey = 'app_settings';
  static const _securePasswordFlag = 'passwordInSecureStorage';

  final SettingsDao _dao;
  final ProxyPasswordStore _passwordStore;
  final StreamController<AppSettings> _changes = StreamController<AppSettings>.broadcast();
  AppSettings _current = const AppSettings();

  /// What the password store is known to hold; null when nothing, so a user who
  /// never set a proxy password never touches the platform keychain.
  String? _storedPassword;

  SettingsRepositoryImpl(this._dao, this._passwordStore);

  @override
  AppSettings get current => _current;

  @override
  Future<void> load() async {
    try {
      _current = await _read(await _dao.get(storageKey));
    } catch (_) {
      _current = const AppSettings();
    }
    _changes.add(_current);
  }

  Future<AppSettings> _read(String? stored) async {
    final settings = AppSettings.decode(stored);
    final proxyJson = SettingsJson.objectOf(SettingsJson.decodeObject(stored)['proxy']);
    if (proxyJson[_securePasswordFlag] == true) {
      final password = await _passwordStore.read();
      _storedPassword = password.isEmpty ? null : password;
      return settings.copyWith(proxy: settings.proxy.copyWith(password: password));
    }
    _storedPassword = null;
    final legacy = settings.proxy.password;
    if (legacy.isNotEmpty && await _passwordStore.write(legacy)) {
      _storedPassword = legacy;
      try {
        await _dao.put(storageKey, _encodeForStorage(settings, passwordInSecureStorage: true));
      } catch (_) {
        // The plaintext copy stays until the next start moves it again.
      }
    }
    return settings;
  }

  @override
  Stream<AppSettings> watch() => Stream.multi((controller) {
        controller.add(_current);
        final subscription = _changes.stream.listen(controller.add);
        controller.onCancel = subscription.cancel;
      }, isBroadcast: true);

  @override
  Future<void> save(AppSettings settings) async {
    _current = settings;
    _changes.add(settings);
    final inSecureStorage = await _storePassword(settings.proxy.password);
    await _dao.put(storageKey, _encodeForStorage(settings, passwordInSecureStorage: inSecureStorage));
  }

  @override
  Future<void> reset() async {
    _current = const AppSettings();
    _changes.add(_current);
    await _dao.remove(storageKey);
    _storedPassword = null;
    await _passwordStore.delete();
  }

  /// True when [password] is now in the store.
  Future<bool> _storePassword(String password) async {
    if (password.isEmpty) {
      if (_storedPassword != null) {
        _storedPassword = null;
        await _passwordStore.delete();
      }
      return false;
    }
    if (password == _storedPassword) return true;
    final stored = await _passwordStore.write(password);
    if (stored) _storedPassword = password;
    return stored;
  }

  String _encodeForStorage(AppSettings settings, {required bool passwordInSecureStorage}) {
    final json = settings.toJson();
    final proxy = {...SettingsJson.objectOf(json['proxy'])}..remove('password');
    if (passwordInSecureStorage) proxy[_securePasswordFlag] = true;
    return jsonEncode({...json, 'proxy': proxy});
  }
}
