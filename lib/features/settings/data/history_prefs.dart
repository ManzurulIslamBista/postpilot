import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../history/domain/services/history_policy.dart';

/// Per-device choices about what History keeps (Settings > History): whether
/// request and response bodies are stored with each entry, how many entries,
/// for how many days, and how much of a body. Local on purpose, like the safety
/// choices: History holds what this person sent from this machine.
///
/// Loads itself the first time it is read, so History honours the saved values
/// from the very first send without the app having to load them at start-up.
class HistoryPrefs extends ChangeNotifier implements HistoryPolicy {
  static const _kKeepBodies = 'history.keepBodies';
  static const _kMaxEntries = 'history.maxEntries';
  static const _kRetentionDays = 'history.retentionDays';
  static const _kMaxBodyKb = 'history.maxBodyKb';

  /// The longest retention that can be set, in days.
  static const maxRetentionDays = 3650;

  SharedPreferences? _prefs;
  Future<void>? _loading;
  bool _keepBodies = true;
  int _maxEntries = HistoryLimits.defaultMaxEntries;
  int _retentionDays = 0;
  int _maxBodyKb = HistoryLimits.defaultMaxBodyBytes ~/ 1024;

  bool get keepBodies => _keepBodies;
  int get maxEntries => _maxEntries;

  /// 0 keeps entries until the count limit pushes them out.
  int get retentionDays => _retentionDays;
  int get maxBodyKb => _maxBodyKb;

  /// Reads the stored values once; later calls return the same future.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      _keepBodies = prefs.getBool(_kKeepBodies) ?? true;
      _maxEntries = (prefs.getInt(_kMaxEntries) ?? HistoryLimits.defaultMaxEntries)
          .clamp(HistoryLimits.minMaxEntries, HistoryLimits.maxMaxEntries);
      _retentionDays = (prefs.getInt(_kRetentionDays) ?? 0).clamp(0, maxRetentionDays);
      _maxBodyKb = (prefs.getInt(_kMaxBodyKb) ?? HistoryLimits.defaultMaxBodyBytes ~/ 1024)
          .clamp(HistoryLimits.minMaxBodyBytes ~/ 1024, HistoryLimits.maxMaxBodyBytes ~/ 1024);
      notifyListeners();
    } catch (_) {
      // Storage can be unavailable (private window, tests): the defaults apply.
    }
  }

  @override
  Future<HistoryLimits> limits() async {
    await load();
    return HistoryLimits(
      keepBodies: _keepBodies,
      maxEntries: _maxEntries,
      retentionDays: _retentionDays > 0 ? _retentionDays : null,
      maxBodyBytes: _maxBodyKb * 1024,
    );
  }

  Future<void> setKeepBodies(bool value) async {
    await load();
    _keepBodies = value;
    notifyListeners();
    await _save((p) => p.setBool(_kKeepBodies, value));
  }

  Future<void> setMaxEntries(int value) async {
    await load();
    _maxEntries = value.clamp(HistoryLimits.minMaxEntries, HistoryLimits.maxMaxEntries);
    notifyListeners();
    await _save((p) => p.setInt(_kMaxEntries, _maxEntries));
  }

  Future<void> setRetentionDays(int value) async {
    await load();
    _retentionDays = value.clamp(0, maxRetentionDays);
    notifyListeners();
    await _save((p) => p.setInt(_kRetentionDays, _retentionDays));
  }

  Future<void> setMaxBodyKb(int value) async {
    await load();
    _maxBodyKb = value.clamp(HistoryLimits.minMaxBodyBytes ~/ 1024, HistoryLimits.maxMaxBodyBytes ~/ 1024);
    notifyListeners();
    await _save((p) => p.setInt(_kMaxBodyKb, _maxBodyKb));
  }

  Future<void> _save(Future<bool> Function(SharedPreferences prefs) write) async {
    try {
      await write(_prefs ??= await SharedPreferences.getInstance());
    } catch (_) {}
  }
}
