import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import '../../../../core/database/app_database.dart';
import '../../../import_export/domain/repositories/git_state_store.dart';
import '../../../import_export/domain/services/backup_codec.dart';
import '../../domain/entities/git_link.dart';
import '../../domain/entities/sync_doc.dart';

/// [GitStateStore] over the link, base-entry and uid tables.
final class DriftGitStateStore implements GitStateStore {
  final AppDatabase _db;
  const DriftGitStateStore(this._db);

  @override
  Future<BackupGitState?> read(
    int collectionId, {
    required Iterable<int> folderIds,
    required Iterable<int> requestIds,
  }) async {
    final link = await _db.gitLinksDao.findByCollection(collectionId);
    if (link == null) return null;

    final base = await _db.gitLinksDao.baseEntries(link.id);
    final folderUids = await _db.entityUidsDao.uidsByLocalId(SyncKind.folder.name);
    final requestUids = await _db.entityUidsDao.uidsByLocalId(SyncKind.request.name);
    return BackupGitState(
      git: BackupGit(
        provider: link.provider,
        owner: link.owner,
        repo: link.repo,
        branch: link.branch,
        basePath: link.basePath,
        lastSyncedSha: link.lastSyncedSha,
        lastSyncedAt: link.lastSyncedAt,
        includeSecrets: link.includeSecrets,
        base: [for (final b in base) BackupGitBase(uid: b.uid, path: b.path, blobSha: b.blobSha, doc: b.docJson)],
      ),
      collectionUid: await _db.entityUidsDao.uidOf(SyncKind.collection.name, collectionId),
      folderUids: {for (final id in folderIds) id: ?folderUids[id]},
      requestUids: {for (final id in requestIds) id: ?requestUids[id]},
    );
  }

  @override
  Future<void> restore(int collectionId, BackupGitState state) async {
    final git = state.git;
    // A provider this app does not know could not be read back later (the link
    // reader would throw), so such a link is not recreated.
    if (!GitProvider.values.any((p) => p.name == git.provider)) return;

    final bindings = <(String, int, String)>[
      if (state.collectionUid != null) (SyncKind.collection.name, collectionId, state.collectionUid!),
      for (final e in state.folderUids.entries) (SyncKind.folder.name, e.key, e.value),
      for (final e in state.requestUids.entries) (SyncKind.request.name, e.key, e.value),
    ];

    await _db.transaction(() async {
      for (final (kind, localId, uid) in bindings) {
        final holder = await _db.entityUidsDao.localIdOf(kind, uid);
        if (holder != null && holder != localId) {
          debugPrint('PostPilot: not re-linking collection $collectionId: uid $uid already belongs to another entity.');
          return;
        }
      }

      final linkId = await _db.gitLinksDao.insertLink(GitLinksCompanion.insert(
        collectionId: collectionId,
        provider: git.provider,
        owner: git.owner,
        repo: git.repo,
        branch: git.branch,
        basePath: Value(git.basePath),
        lastSyncedSha: Value(git.lastSyncedSha),
        lastSyncedAt: Value(git.lastSyncedAt),
        includeSecrets: Value(git.includeSecrets),
      ));
      await _db.gitLinksDao.replaceBase(linkId, [
        for (final b in git.base)
          GitBaseEntriesCompanion.insert(linkId: linkId, uid: b.uid, path: b.path, blobSha: b.blobSha, docJson: b.doc),
      ]);
      for (final (kind, localId, uid) in bindings) {
        await _db.entityUidsDao.put(kind, localId, uid);
      }
    });
  }
}
