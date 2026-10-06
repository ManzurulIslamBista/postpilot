import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/collections_table.dart';
import 'entity_notes_copy.dart';

part 'collections_dao.g.dart';

@DriftAccessor(tables: [Collections, Folders])
class CollectionsDao extends DatabaseAccessor<AppDatabase> with _$CollectionsDaoMixin {
  CollectionsDao(super.db);

  Stream<List<Collection>> watchAllCollections() => select(collections).watch();

  Future<int> createCollection(String name) => into(collections).insert(CollectionsCompanion.insert(name: name));

  Future<void> renameCollection(int id, String name) =>
      (update(collections)..where((t) => t.id.equals(id))).write(CollectionsCompanion(name: Value(name)));

  Future<void> deleteCollection(int id) => (delete(collections)..where((t) => t.id.equals(id))).go();

  Stream<List<Folder>> watchFolders(int collectionId) =>
      (select(folders)
            ..where((t) => t.collectionId.equals(collectionId))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
          .watch();

  Future<int> createFolder({required int collectionId, int? parentFolderId, required String name}) => into(folders)
      .insert(FoldersCompanion.insert(collectionId: collectionId, parentFolderId: Value(parentFolderId), name: name));

  Future<void> renameFolder(int id, String name) =>
      (update(folders)..where((t) => t.id.equals(id))).write(FoldersCompanion(name: Value(name)));

  Future<void> deleteFolder(int id) => transaction(() async {
        final subtree = await _folderSubtreeIds(id);
        await attachedDatabase.requestsDao.deleteInFolders(subtree);
        await (delete(folders)..where((t) => t.id.isIn(subtree))).go();
      });

  /// [rootId] plus the id of every folder nested under it, at any depth.
  Future<List<int>> _folderSubtreeIds(int rootId) async {
    final ids = [rootId];
    for (var i = 0; i < ids.length; i++) {
      ids.addAll(await (select(folders)..where((t) => t.parentFolderId.equals(ids[i]))).map((f) => f.id).get());
    }
    return ids;
  }

  Future<int> duplicateCollection(int id) async {
    final original = await (select(collections)..where((t) => t.id.equals(id))).getSingle();
    final siblingNames = await select(collections).map((r) => r.name).get();
    final name = _uniqueCopyName(original.name, siblingNames);
    return transaction(() async {
      final newId = await into(collections).insert(
        original.toCompanion(true).copyWith(id: const Value.absent(), name: Value(name), createdAt: const Value.absent()),
      );
      await copyEntityNotes(attachedDatabase, 'collection', fromId: id, toId: newId);
      await attachedDatabase.requestsDao.duplicateRequestsIn(
        collectionId: id,
        folderId: null,
        newCollectionId: newId,
        newFolderId: null,
      );
      await _duplicateFolderTree(collectionId: id, newCollectionId: newId, parentFolderId: null, newParentFolderId: null);
      await attachedDatabase.collectionVariablesDao.duplicateVariables(fromCollectionId: id, toCollectionId: newId);
      await attachedDatabase.collectionAuthDao.duplicateAuth(fromCollectionId: id, toCollectionId: newId);
      return newId;
    });
  }

  Future<int> duplicateFolder(int id) async {
    final original = await (select(folders)..where((t) => t.id.equals(id))).getSingle();
    final siblingNames = await (select(folders)..where((t) => _sameParent(t, original.collectionId, original.parentFolderId)))
        .map((r) => r.name)
        .get();
    final name = _uniqueCopyName(original.name, siblingNames);
    return transaction(() async {
      final newId = await into(folders).insert(original.toCompanion(true).copyWith(id: const Value.absent(), name: Value(name)));
      await copyEntityNotes(attachedDatabase, 'folder', fromId: original.id, toId: newId);
      await attachedDatabase.requestsDao.duplicateRequestsIn(
        collectionId: original.collectionId,
        folderId: original.id,
        newCollectionId: original.collectionId,
        newFolderId: newId,
      );
      await _duplicateFolderTree(
        collectionId: original.collectionId,
        newCollectionId: original.collectionId,
        parentFolderId: original.id,
        newParentFolderId: newId,
      );
      return newId;
    });
  }

  Future<int> duplicateRequest(int id) => attachedDatabase.requestsDao.duplicateRequest(id);

  /// Copies every folder under [parentFolderId] (and its requests, and its own
  /// sub-folders recursively) from [collectionId] into [newCollectionId] under
  /// [newParentFolderId], keeping original names.
  Future<void> _duplicateFolderTree({
    required int collectionId,
    required int newCollectionId,
    required int? parentFolderId,
    required int? newParentFolderId,
  }) async {
    final children = await (select(folders)..where((t) => _sameParent(t, collectionId, parentFolderId))).get();
    for (final folder in children) {
      final newFolderId = await into(folders).insert(
        folder.toCompanion(true).copyWith(
              id: const Value.absent(),
              collectionId: Value(newCollectionId),
              parentFolderId: Value(newParentFolderId),
            ),
      );
      await copyEntityNotes(attachedDatabase, 'folder', fromId: folder.id, toId: newFolderId);
      await attachedDatabase.requestsDao.duplicateRequestsIn(
        collectionId: collectionId,
        folderId: folder.id,
        newCollectionId: newCollectionId,
        newFolderId: newFolderId,
      );
      await _duplicateFolderTree(
        collectionId: collectionId,
        newCollectionId: newCollectionId,
        parentFolderId: folder.id,
        newParentFolderId: newFolderId,
      );
    }
  }

  Expression<bool> _sameParent($FoldersTable t, int collectionId, int? parentFolderId) =>
      t.collectionId.equals(collectionId) & (parentFolderId == null ? t.parentFolderId.isNull() : t.parentFolderId.equals(parentFolderId));
}

/// Appends " copy" (or " copy 2", " copy 3", ... if that's already taken) to
/// [original], checked case-sensitively against [taken].
String _uniqueCopyName(String original, Iterable<String> taken) {
  final takenSet = taken.toSet();
  final baseName = '$original copy';
  if (!takenSet.contains(baseName)) return baseName;
  var suffix = 2;
  while (takenSet.contains('$baseName $suffix')) {
    suffix++;
  }
  return '$baseName $suffix';
}
