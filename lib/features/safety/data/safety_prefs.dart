import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device safety choices: whether to ask before sending data-changing
/// requests in a production environment, which extra names count as
/// production, and which hosts are production whatever the environment is
/// called. Local on purpose: a teammate's laptop decides for itself.
class SafetyPrefs extends ChangeNotifier {
  static const _kConfirm = 'safety.confirmProductionWrites';
  static const _kWords = 'safety.productionWords';
  static const _kHosts = 'safety.productionHosts';
  static const _kKeepSecretsLocal = 'safety.keepSecretsLocal';

  SharedPreferences? _prefs;
  bool _confirmProductionWrites = true;
  bool _keepSecretsLocal = true;
  List<String> _extraWords = const [];
  List<String> _productionHosts = const [];

  /// Production environments or hosts the user chose "don't ask again" for.
  /// Held in memory only, so it ends with the app session, and it never
  /// covers a request that deletes data (see `ProductionGuard`).
  final Set<String> _silenced = {};

  bool get confirmProductionWrites => _confirmProductionWrites;

  /// Secret values stay in `workspace.local.json` on this device instead of the
  /// shared `workspace.json` that Git carries. On by default.
  bool get keepSecretsLocal => _keepSecretsLocal;
  List<String> get extraWords => _extraWords;

  /// Hosts that are production under any environment name (`api.acme.com`,
  /// `*.acme.com`, `acme.com:8443`); see `ProductionDetector.isProductionHost` for how they match.
  List<String> get productionHosts => _productionHosts;

  Future<void> load() async {
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      _confirmProductionWrites = prefs.getBool(_kConfirm) ?? true;
      _extraWords = prefs.getStringList(_kWords) ?? const [];
      _productionHosts = prefs.getStringList(_kHosts) ?? const [];
      _keepSecretsLocal = prefs.getBool(_kKeepSecretsLocal) ?? true;
      notifyListeners();
    } catch (_) {
      // Storage can be unavailable (private window, tests): the defaults apply.
    }
  }

  Future<void> setConfirmProductionWrites(bool value) async {
    _confirmProductionWrites = value;
    notifyListeners();
    try {
      await (_prefs ??= await SharedPreferences.getInstance()).setBool(_kConfirm, value);
    } catch (_) {}
  }

  Future<void> setKeepSecretsLocal(bool value) async {
    _keepSecretsLocal = value;
    notifyListeners();
    try {
      await (_prefs ??= await SharedPreferences.getInstance()).setBool(_kKeepSecretsLocal, value);
    } catch (_) {}
  }

  Future<void> setExtraWords(List<String> words) async {
    _extraWords = [for (final w in words) if (w.trim().isNotEmpty) w.trim()];
    notifyListeners();
    try {
      await (_prefs ??= await SharedPreferences.getInstance()).setStringList(_kWords, _extraWords);
    } catch (_) {}
  }

  Future<void> setProductionHosts(List<String> hosts) async {
    _productionHosts = [for (final h in hosts) if (h.trim().isNotEmpty) h.trim()];
    notifyListeners();
    try {
      await (_prefs ??= await SharedPreferences.getInstance()).setStringList(_kHosts, _productionHosts);
    } catch (_) {}
  }

  bool isSilenced(String environmentName) => _silenced.contains(environmentName);

  void silenceForSession(String environmentName) => _silenced.add(environmentName);

  /// Asks again about everything that was silenced.
  void clearSilenced() => _silenced.clear();
}
