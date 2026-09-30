import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/entities/git_link.dart';
import '../domain/repositories/git_credentials_store.dart';

/// Keeps each host's personal access token in the platform keychain / keystore.
///
/// Secure storage can throw where the platform cannot provide it (web without
/// WebCrypto, e.g. on a plain-http origin). A token it refuses to persist is
/// then held in memory for the current session only, so Git sync still works
/// but the token has to be entered again after a restart.
final class SecureGitCredentialsStore implements GitCredentialsStore {
  /// macOS uses the legacy keychain: the data-protection one needs the
  /// keychain-access-groups entitlement and a provisioning profile.
  SecureGitCredentialsStore({
    this._storage = const FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false)),
  });

  final FlutterSecureStorage _storage;
  final Map<String, String> _unpersisted = {};

  static String _key(GitProvider provider) => 'git_token_${provider.name}';

  @override
  Future<String?> readToken(GitProvider provider) async {
    final key = _key(provider);
    final inMemory = _unpersisted[key];
    if (inMemory != null) return inMemory;
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveToken(GitProvider provider, String token) async {
    final key = _key(provider);
    try {
      await _storage.write(key: key, value: token);
      _unpersisted.remove(key);
    } catch (_) {
      _unpersisted[key] = token;
    }
  }

  @override
  Future<void> deleteToken(GitProvider provider) async {
    final key = _key(provider);
    _unpersisted.remove(key);
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Nothing was persisted if the storage is unusable, so there is nothing left to delete.
    }
  }
}
