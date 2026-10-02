import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/repositories/proxy_password_store.dart';

/// Keeps the proxy password in the platform keychain / keystore.
///
/// Secure storage can throw where the platform cannot provide it (web without
/// WebCrypto, a Linux desktop without a keyring). A password it refuses to
/// persist is then held in memory for the current session only, so the proxy
/// still works but the password has to be entered again after a restart.
final class SecureProxyPasswordStore implements ProxyPasswordStore {
  /// macOS uses the legacy keychain: the data-protection one needs the
  /// keychain-access-groups entitlement and a provisioning profile.
  SecureProxyPasswordStore({
    this._storage = const FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false)),
  });

  static const _key = 'proxy_password';

  final FlutterSecureStorage _storage;
  String? _unpersisted;

  @override
  Future<String> read() async {
    final inMemory = _unpersisted;
    if (inMemory != null) return inMemory;
    try {
      return await _storage.read(key: _key) ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<bool> write(String password) async {
    try {
      await _storage.write(key: _key, value: password);
      _unpersisted = null;
      return true;
    } catch (_) {
      _unpersisted = password;
      return false;
    }
  }

  @override
  Future<void> delete() async {
    _unpersisted = null;
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing was persisted if the storage is unusable, so there is nothing left to delete.
    }
  }
}
