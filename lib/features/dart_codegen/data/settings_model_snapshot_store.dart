import '../../../core/database/daos/settings_dao.dart';
import '../domain/repositories/model_snapshot_store.dart';
import '../domain/services/model_schema_diff.dart';

/// Keeps one JSON value per source in the settings table (`setting_entries`).
final class SettingsModelSnapshotStore implements ModelSnapshotStore {
  static const keyPrefix = 'dart_studio.schema.';

  final SettingsDao _dao;

  SettingsModelSnapshotStore(this._dao);

  @override
  Future<SchemaSnapshot?> load(String source) async {
    try {
      return SchemaSnapshot.tryParse(await _dao.get('$keyPrefix$source'));
    } catch (_) {
      // A settings table that cannot be read means no baseline, not a failed generation.
      return null;
    }
  }

  @override
  Future<void> save(String source, SchemaSnapshot snapshot) => _dao.put('$keyPrefix$source', snapshot.toText());

  @override
  Future<void> forget(String source) => _dao.remove('$keyPrefix$source');
}
