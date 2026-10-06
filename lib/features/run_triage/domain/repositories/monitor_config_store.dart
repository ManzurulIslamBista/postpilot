import '../entities/monitor_config.dart';

/// Where the monitor remembers which collections it watches, so the choice survives a restart. Per device: a
/// teammate's laptop decides for itself, and nothing here goes into `workspace.json`.
abstract interface class MonitorConfigStore {
  /// The saved configuration by collection id; empty when there is none or it cannot be read.
  Future<Map<int, MonitorConfig>> load();

  Future<void> save(Map<int, MonitorConfig> configs);
}
