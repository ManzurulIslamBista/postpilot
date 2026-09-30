import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/request_settings_table.dart';

part 'request_settings_dao.g.dart';

@DriftAccessor(tables: [RequestSettingEntries])
class RequestSettingsDao extends DatabaseAccessor<AppDatabase> with _$RequestSettingsDaoMixin {
  RequestSettingsDao(super.db);

  /// The settings JSON of [requestId], or null when it has none stored.
  Future<String?> get(int requestId) => (select(requestSettingEntries)..where((t) => t.requestId.equals(requestId)))
      .map((r) => r.settingsJson)
      .getSingleOrNull();

  Stream<String?> watch(int requestId) => (select(requestSettingEntries)..where((t) => t.requestId.equals(requestId)))
      .map((r) => r.settingsJson)
      .watchSingleOrNull();

  Future<void> put(int requestId, String settingsJson) => into(requestSettingEntries).insertOnConflictUpdate(
        RequestSettingEntriesCompanion.insert(requestId: Value(requestId), settingsJson: Value(settingsJson)),
      );

  Future<void> remove(int requestId) => (delete(requestSettingEntries)..where((t) => t.requestId.equals(requestId))).go();
}
