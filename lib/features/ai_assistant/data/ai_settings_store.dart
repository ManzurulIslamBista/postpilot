import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the person's own Anthropic API key and chosen model live. The key
/// goes to the platform keychain, never to the database, a workspace file or
/// Git; the model name is an ordinary preference.
abstract interface class AiSettingsStore {
  Future<String?> apiKey();
  Future<void> saveApiKey(String key);
  Future<void> clearApiKey();
  Future<String> model();
  Future<void> saveModel(String model);
}

final class SecureAiSettingsStore implements AiSettingsStore {
  static const defaultModel = 'claude-sonnet-5-5';
  static const _keyName = 'ai_anthropic_api_key';
  static const _modelName = 'ai.model';

  SecureAiSettingsStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));

  final FlutterSecureStorage _storage;

  /// Held for the session when the keychain refuses (a browser without WebCrypto, a test).
  String? _unpersisted;

  @override
  Future<String?> apiKey() async {
    final inMemory = _unpersisted;
    if (inMemory != null) return inMemory;
    try {
      final key = await _storage.read(key: _keyName);
      return key == null || key.isEmpty ? null : key;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveApiKey(String key) async {
    try {
      await _storage.write(key: _keyName, value: key);
      _unpersisted = null;
    } catch (_) {
      _unpersisted = key;
    }
  }

  @override
  Future<void> clearApiKey() async {
    _unpersisted = null;
    try {
      await _storage.delete(key: _keyName);
    } catch (_) {}
  }

  @override
  Future<String> model() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_modelName) ?? defaultModel;
    } catch (_) {
      return defaultModel;
    }
  }

  @override
  Future<void> saveModel(String model) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_modelName, model.trim().isEmpty ? defaultModel : model.trim());
    } catch (_) {}
  }
}
