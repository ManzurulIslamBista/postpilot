import 'package:drift/drift.dart';

/// Maps a local entity (`kind` + autoincrement id) to the uid that identifies it
/// in a Git repository. A uid belongs to at most one local entity.
@TableIndex(name: 'entity_uids_uid', columns: {#uid}, unique: true)
class EntityUids extends Table {
  TextColumn get kind => text()();
  IntColumn get localId => integer()();
  TextColumn get uid => text()();

  @override
  Set<Column> get primaryKey => {kind, localId};
}
