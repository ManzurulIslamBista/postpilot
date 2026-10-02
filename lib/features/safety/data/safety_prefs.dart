import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device safety choices: whether to ask before sending data-changing
/// requests in a production environment, and which extra names count as
/// production. Local on purpose: a teammate's laptop decides for itself.
class SafetyPrefs extends ChangeNotifier {
  static const _kConfirm = 'safety.confirmProductionWrites';
  static const _kWords = 'safety.productionWords';
  static const _kKeepSecretsLocal = 'safety.keepSecretsLocal';

  SharedPreferences? _prefs;
  bool _confirmProductionWrites = true;
  bool _keepSecretsLocal = true;
  List<String> _extraWords = const [];

  /// Production environments the user chose "don't ask again" for, this session only.
  final Set<String> _silenced = {};

  bool get confirmProductionWrites => _confirmProductionWrites;

  /// Secret values stay in `workspace.local.json` on this device instead of the
  /// shared `workspace.json` that Git carries. On by default.
  bool get keepSecretsLocal => _keepSecretsLocal;
  List<String> get extraWords => _extraWords;

  Future<void> load() async {
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      _confirmProductionWrites = prefs.getBool(_kConfirm) ?? true;
      _extraWords = prefs.getStringList(_kWords) ?? const [];
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

  bool isSilenced(String environmentName) => _silenced.contains(environmentName);

  void silenceForSession(String environmentName) => _silenced.add(environmentName);
}
