import 'dart:convert';
import '../../../core/database/daos/settings_dao.dart';
import '../domain/entities/monitor_config.dart';
import '../domain/repositories/monitor_config_store.dart';

/// Keeps the monitor's choices as one JSON value in the settings table (`setting_entries`).
final class SettingsMonitorConfigStore implements MonitorConfigStore {
  static const storageKey = 'monitor.configs';

  final SettingsDao _dao;

  SettingsMonitorConfigStore(this._dao);

  @override
  Future<Map<int, MonitorConfig>> load() async {
    try {
      final text = await _dao.get(storageKey);
      if (text == null) return const {};
      final decoded = jsonDecode(text);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (int.tryParse('${entry.key}') != null && entry.value is Map)
            int.parse('${entry.key}'): MonitorConfig.fromJson(Map<String, Object?>.from(entry.value as Map)),
      };
    } catch (_) {
      // A damaged value means no monitors, not a crash at start-up.
      return const {};
    }
  }

  @override
  Future<void> save(Map<int, MonitorConfig> configs) => _dao.put(
        storageKey,
        jsonEncode({for (final e in configs.entries) '${e.key}': e.value.toJson()}),
      );
}
