import 'package:uuid/uuid.dart';
import '../../../../core/database/daos/entity_uids_dao.dart';
import '../../domain/entities/sync_doc.dart';

/// Gives every local collection, folder and request the uid that identifies it
/// in a Git repository. A uid belongs to exactly one local entity.
final class EntityUidRegistry {
  static const _uuid = Uuid();

  final EntityUidsDao _dao;
  const EntityUidRegistry(this._dao);

  /// The entity's uid, creating and storing a new v4 uuid the first time.
  /// Concurrent first calls agree on one uid: the insert is ignored when the
  /// entity already has one, and the stored value is what gets returned.
  Future<String> uidFor(SyncKind kind, int localId) async {
    final existing = await _dao.uidOf(kind.name, localId);
    if (existing != null) return existing;
    await _dao.putIfAbsent(kind.name, localId, _uuid.v4());
    return (await _dao.uidOf(kind.name, localId))!;
  }

  Future<int?> localIdFor(SyncKind kind, String uid) => _dao.localIdOf(kind.name, uid);

  /// Binds an existing local entity to a uid that came from the remote,
  /// replacing the uid it had. Throws if [uid] already belongs to another
  /// local entity.
  Future<void> adopt(SyncKind kind, int localId, String uid) => _dao.put(kind.name, localId, uid);

  /// Uids by local id for the entities of [kind] that already have one.
  Future<Map<int, String>> uidsFor(SyncKind kind) => _dao.uidsByLocalId(kind.name);
}
