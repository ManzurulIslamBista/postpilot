import '../entities/app_settings.dart';

abstract interface class SettingsRepository {
  /// The settings in force. Synchronous so a send never waits on storage; it
  /// holds the defaults until [load] has run.
  AppSettings get current;

  /// Reads the stored settings once, at startup. Missing or unreadable data
  /// leaves the defaults in place instead of failing.
  Future<void> load();

  /// The current settings first, then each later change.
  Stream<AppSettings> watch();

  /// Makes [settings] the current ones immediately, then persists them.
  Future<void> save(AppSettings settings);

  /// Back to the defaults, and forgets what was stored.
  Future<void> reset();
}
