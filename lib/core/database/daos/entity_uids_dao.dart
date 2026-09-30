import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/entity_uids_table.dart';

part 'entity_uids_dao.g.dart';

@DriftAccessor(tables: [EntityUids])
class EntityUidsDao extends DatabaseAccessor<AppDatabase> with _$EntityUidsDaoMixin {
  EntityUidsDao(super.db);

  Future<String?> uidOf(String kind, int localId) =>
      (select(entityUids)..where((t) => t.kind.equals(kind) & t.localId.equals(localId)))
          .map((r) => r.uid)
          .getSingleOrNull();

  Future<int?> localIdOf(String kind, String uid) =>
      (select(entityUids)..where((t) => t.kind.equals(kind) & t.uid.equals(uid)))
          .map((r) => r.localId)
          .getSingleOrNull();

  /// Binds [uid] to the entity, replacing its previous uid. Fails if another
  /// entity already holds [uid].
  Future<void> put(String kind, int localId, String uid) =>
      into(entityUids).insertOnConflictUpdate(EntityUidsCompanion.insert(kind: kind, localId: localId, uid: uid));

  /// Binds [uid] only if the entity has none yet, so a concurrent binding wins
  /// instead of being overwritten.
  Future<void> putIfAbsent(String kind, int localId, String uid) => into(entityUids).insert(
        EntityUidsCompanion.insert(kind: kind, localId: localId, uid: uid),
        mode: InsertMode.insertOrIgnore,
      );

  Future<Map<int, String>> uidsByLocalId(String kind) async {
    final rows = await (select(entityUids)..where((t) => t.kind.equals(kind))).get();
    return {for (final r in rows) r.localId: r.uid};
  }

  Future<Map<String, int>> localIdsByUid(String kind) async {
    final rows = await (select(entityUids)..where((t) => t.kind.equals(kind))).get();
    return {for (final r in rows) r.uid: r.localId};
  }
}
