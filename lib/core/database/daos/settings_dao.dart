import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/setting_entries_table.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [SettingEntries])
class SettingsDao extends DatabaseAccessor<AppDatabase> with _$SettingsDaoMixin {
  SettingsDao(super.db);

  Future<String?> get(String key) =>
      (select(settingEntries)..where((t) => t.key.equals(key))).map((r) => r.value).getSingleOrNull();

  Stream<String?> watch(String key) =>
      (select(settingEntries)..where((t) => t.key.equals(key))).map((r) => r.value).watchSingleOrNull();

  Future<void> put(String key, String value) =>
      into(settingEntries).insertOnConflictUpdate(SettingEntriesCompanion.insert(key: key, value: value));

  Future<void> remove(String key) => (delete(settingEntries)..where((t) => t.key.equals(key))).go();
}
