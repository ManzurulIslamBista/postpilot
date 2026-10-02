import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where a workplace's GitHub token lives. Never in the registry file or in
/// `workspace.json`: those are readable by any process (and, on the web, by any
/// script on the page), while the platform keychain is not.
abstract interface class WorkplaceTokenStore {
  Future<String?> read(String workplaceId);
  Future<void> write(String workplaceId, String token);
  Future<void> delete(String workplaceId);
}

/// Keeps tokens in the platform keychain / keystore (the same store the
/// collection-level Git sync uses).
///
/// Secure storage can throw where the platform cannot provide it (web without
/// WebCrypto, a test without plugins). A token it refuses to persist is then
/// held in memory for the session, so Git sync still works but the token has to
/// be entered again after a restart.
final class SecureWorkplaceTokenStore implements WorkplaceTokenStore {
  /// macOS uses the legacy keychain: the data-protection one needs the
  /// keychain-access-groups entitlement and a provisioning profile.
  SecureWorkplaceTokenStore({
    this._storage = const FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false)),
  });

  final FlutterSecureStorage _storage;
  final Map<String, String> _unpersisted = {};

  static String _key(String workplaceId) => 'workplace_git_token_$workplaceId';

  @override
  Future<String?> read(String workplaceId) async {
    final key = _key(workplaceId);
    final inMemory = _unpersisted[key];
    if (inMemory != null) return inMemory;
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String workplaceId, String token) async {
    final key = _key(workplaceId);
    try {
      await _storage.write(key: key, value: token);
      _unpersisted.remove(key);
    } catch (_) {
      _unpersisted[key] = token;
    }
  }

  @override
  Future<void> delete(String workplaceId) async {
    final key = _key(workplaceId);
    _unpersisted.remove(key);
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Nothing was persisted if the storage is unusable, so there is nothing left to delete.
    }
  }
}
