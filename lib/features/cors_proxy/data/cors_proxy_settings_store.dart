import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/cors_proxy_protocol.dart';
import '../domain/cors_proxy_settings.dart';

/// Where the web app keeps its CORS proxy choices. On or off and the address are ordinary preferences of this browser; the
/// token is a secret and goes to the secure storage, never to the database, a workspace file or Git.
abstract interface class CorsProxySettingsStore {
  Future<CorsProxySettings> load();
  Future<void> saveEnabled(bool enabled);
  Future<void> saveUrl(String url);
  Future<void> saveToken(String token);
}

final class SecureCorsProxySettingsStore implements CorsProxySettingsStore {
  static const _enabledName = 'corsProxy.enabled';
  static const _urlName = 'corsProxy.url';
  static const _tokenName = 'cors_proxy_token';

  SecureCorsProxySettingsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));

  final FlutterSecureStorage _storage;

  /// Held for the session when the secure storage refuses (a browser without WebCrypto, a test).
  String? _unpersistedToken;

  @override
  Future<CorsProxySettings> load() async {
    var enabled = false;
    var url = CorsProxyProtocol.defaultUrl;
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(_enabledName) ?? false;
      url = prefs.getString(_urlName) ?? url;
    } catch (_) {
      // Storage can be unavailable (a private window, a test): the defaults apply.
    }
    return CorsProxySettings(enabled: enabled, url: url, token: await _readToken());
  }

  Future<String> _readToken() async {
    final inMemory = _unpersistedToken;
    if (inMemory != null) return inMemory;
    try {
      return await _storage.read(key: _tokenName) ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<void> saveEnabled(bool enabled) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_enabledName, enabled);
    } catch (_) {}
  }

  @override
  Future<void> saveUrl(String url) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_urlName, url);
    } catch (_) {}
  }

  @override
  Future<void> saveToken(String token) async {
    try {
      if (token.isEmpty) {
        _unpersistedToken = null;
        await _storage.delete(key: _tokenName);
      } else {
        await _storage.write(key: _tokenName, value: token);
        _unpersistedToken = null;
      }
    } catch (_) {
      _unpersistedToken = token.isEmpty ? null : token;
    }
  }
}
