import 'package:drift/drift.dart';
import '../../../features/collections/domain/entities/move_receipt.dart';
import '../../../features/collections/domain/services/collection_order.dart';
import '../../errors/app_exception.dart';
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

  /// Equal `order_index` values (every row of a workspace made before ordering existed) list by id, the order
  /// the rows were created in, so the list never depends on how SQLite happens to scan.
  Stream<List<Folder>> watchFolders(int collectionId) =>
      (select(folders)
            ..where((t) => t.collectionId.equals(collectionId))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex), (t) => OrderingTerm.asc(t.id)]))
          .watch();

  /// Appends: the folder goes after everything already in [parentFolderId] (folders and requests share one
  /// order), not at 0 where it would tie with its siblings.
  Future<int> createFolder({required int collectionId, int? parentFolderId, required String name}) => transaction(() async {
        final next = await nextOrderIndex(collectionId, parentFolderId);
        return into(folders).insert(
          FoldersCompanion.insert(
            collectionId: collectionId,
            parentFolderId: Value(parentFolderId),
            name: name,
            orderIndex: Value(next),
          ),
        );
      });

  /// The `order_index` that puts a new folder or request after everything in [parentFolderId] (null = the
  /// collection's top level): one more than the highest, 0 for an empty level.
  Future<int> nextOrderIndex(int collectionId, int? parentFolderId) async {
    final folderMax = folders.orderIndex.max();
    final folderTop = await (selectOnly(folders)
          ..addColumns([folderMax])
          ..where(_inFolder(folders.collectionId, folders.parentFolderId, collectionId, parentFolderId)))
        .map((row) => row.read(folderMax))
        .getSingle();
    final requests = attachedDatabase.requests;
    final requestMax = requests.orderIndex.max();
    final requestTop = await (selectOnly(requests)
          ..addColumns([requestMax])
          ..where(_inFolder(requests.collectionId, requests.folderId, collectionId, parentFolderId)))
        .map((row) => row.read(requestMax))
        .getSingle();
    final top = [?folderTop, ?requestTop];
    return top.isEmpty ? 0 : top.reduce((a, b) => a > b ? a : b) + 1;
  }

  Expression<bool> _inFolder(GeneratedColumn<int> collection, GeneratedColumn<int> parent, int collectionId, int? parentId) =>
      collection.equals(collectionId) & (parentId == null ? parent.isNull() : parent.equals(parentId));

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

  // ---- order and moves ----

  /// The folders and requests that sit directly in [parentFolderId] (null = top level) of [collectionId], with
  /// their stored indexes, in no particular order.
  Future<List<LevelItem>> levelItems(int collectionId, int? parentFolderId) async {
    final folderRows = await (select(folders)..where((t) => _sameParent(t, collectionId, parentFolderId))).get();
    final requests = attachedDatabase.requests;
    final requestRows = await (select(requests)
          ..where((t) => _inFolder(t.collectionId, t.folderId, collectionId, parentFolderId)))
        .get();
    return [
      for (final f in folderRows) (ref: OrderRef.folder(f.id), orderIndex: f.orderIndex),
      for (final r in requestRows) (ref: OrderRef.request(r.id), orderIndex: r.orderIndex),
    ];
  }

  /// Puts [copy] (just inserted with the same index as [original]) directly behind [original] and renumbers the
  /// level densely, so a duplicate neither ties with its siblings nor lands at the end.
  Future<void> placeAfter({
    required OrderRef original,
    required OrderRef copy,
    required int collectionId,
    required int? parentId,
  }) async {
    final items = await levelItems(collectionId, parentId);
    final siblings = [for (final item in CollectionOrder.sortLevel(items)) if (item.ref != copy) item.ref];
    final at = siblings.indexOf(original);
    final before = at >= 0 && at + 1 < siblings.length ? siblings[at + 1] : null;
    final ordered = CollectionOrder.placed(items, copy, before: before);
    final current = {for (final item in items) item.ref: item.orderIndex};
    for (final (i, ref) in ordered.indexed) {
      if (current[ref] != i) {
        await _writePlace(Placement(ref: ref, collectionId: collectionId, parentId: parentId, orderIndex: i));
      }
    }
  }

  /// Gives every level of [collectionId] whose siblings share an `order_index` distinct, dense indexes in the
  /// canonical order (folders before requests, then by id), which is the order such a level is already shown in.
  /// A level with distinct indexes is left alone. Returns how many rows were written.
  Future<int> normalizeOrder(int collectionId) => transaction(() async {
        final levels = <int?, List<LevelItem>>{};
        final folderRows = await (select(folders)..where((t) => t.collectionId.equals(collectionId))).get();
        final requestRows =
            await (select(attachedDatabase.requests)..where((t) => t.collectionId.equals(collectionId))).get();
        for (final f in folderRows) {
          (levels[f.parentFolderId] ??= []).add((ref: OrderRef.folder(f.id), orderIndex: f.orderIndex));
        }
        for (final r in requestRows) {
          (levels[r.folderId] ??= []).add((ref: OrderRef.request(r.id), orderIndex: r.orderIndex));
        }
        var written = 0;
        for (final level in levels.entries) {
          if (!CollectionOrder.hasTies(level.value)) continue;
          for (final (i, item) in CollectionOrder.sortLevel(level.value).indexed) {
            if (item.orderIndex == i) continue;
            await _writeOrder(item.ref, i);
            written++;
          }
        }
        return written;
      });

  /// Moves a request into [folderId] of [collectionId] (null = that collection's top level), immediately before
  /// [before] among the folders and requests there (at the end when null). Both levels it touches are renumbered
  /// densely; only rows whose place changes are written. Everything happens in one transaction, so a failure
  /// leaves the tree as it was. Returns the placements it replaced (empty when nothing changed).
  Future<List<Placement>> moveRequest(
    int requestId, {
    required int collectionId,
    int? folderId,
    OrderRef? before,
  }) => transaction(() async {
        final requests = attachedDatabase.requests;
        final request = await (select(requests)..where((t) => t.id.equals(requestId))).getSingleOrNull();
        if (request == null) throw const NotFoundException('That request no longer exists.');
        await _requireDestination(collectionId, folderId);
        final replaced = await _applyMove(
          OrderRef.request(requestId),
          fromCollection: request.collectionId,
          fromParent: request.folderId,
          toCollection: collectionId,
          toParent: folderId,
          before: before,
        );
        if (request.collectionId != collectionId) await _forgetUids('request', [requestId]);
        return replaced;
      });

  /// Moves a folder with everything inside it, under [parentFolderId] of [collectionId] (null = top level); see
  /// [moveRequest]. A folder cannot go into itself or one of its own sub-folders ([MoveRefusedException]). Ids stay
  /// the same; when the collection changes, the sub-folders and every request below move along, keeping their
  /// nesting and order.
  Future<List<Placement>> moveFolder(
    int folderId, {
    required int collectionId,
    int? parentFolderId,
    OrderRef? before,
  }) => transaction(() async {
        final folder = await (select(folders)..where((t) => t.id.equals(folderId))).getSingleOrNull();
        if (folder == null) throw const NotFoundException('That folder no longer exists.');
        final subtree = await _folderSubtreeIds(folderId);
        if (parentFolderId != null && subtree.contains(parentFolderId)) {
          throw const MoveRefusedException('A folder cannot be moved into itself or one of its own sub-folders.');
        }
        await _requireDestination(collectionId, parentFolderId);

        final replaced = <Placement>[];
        if (folder.collectionId != collectionId) replaced.addAll(await _moveSubtreeTo(collectionId, subtree, folderId));
        replaced.addAll(
          await _applyMove(
            OrderRef.folder(folderId),
            fromCollection: folder.collectionId,
            fromParent: folder.parentFolderId,
            toCollection: collectionId,
            toParent: parentFolderId,
            before: before,
          ),
        );
        return replaced;
      });

  /// Puts back what [placements] (from a move's receipt) replaced. A row that was deleted since is skipped; a
  /// folder that is gone sends what was in it to the top level of its collection.
  Future<void> restorePlacements(List<Placement> placements) => transaction(() async {
        for (final p in placements) {
          final parent = p.parentId;
          final parentExists = parent == null || await _folderExists(parent);
          final restored = Placement(
            ref: p.ref,
            collectionId: p.collectionId,
            parentId: parentExists ? parent : null,
            orderIndex: p.orderIndex,
          );
          if (await _exists(p.ref)) await _writePlace(restored);
        }
      });

  /// Moves the sub-folders of [subtree] (all but [rootId], which the caller places) and every request directly in
  /// one of [subtree]'s folders into [collectionId]; returns what they were before.
  Future<List<Placement>> _moveSubtreeTo(int collectionId, List<int> subtree, int rootId) async {
    final requests = attachedDatabase.requests;
    final replaced = <Placement>[];
    final descendants = [for (final id in subtree) if (id != rootId) id];
    final requestIds = <int>[];
    for (final chunk in _chunks(descendants)) {
      for (final f in await (select(folders)..where((t) => t.id.isIn(chunk))).get()) {
        replaced.add(Placement(
          ref: OrderRef.folder(f.id),
          collectionId: f.collectionId,
          parentId: f.parentFolderId,
          orderIndex: f.orderIndex,
        ));
      }
      await (update(folders)..where((t) => t.id.isIn(chunk))).write(FoldersCompanion(collectionId: Value(collectionId)));
    }
    for (final chunk in _chunks(subtree)) {
      for (final r in await (select(requests)..where((t) => t.folderId.isIn(chunk))).get()) {
        requestIds.add(r.id);
        replaced.add(Placement(
          ref: OrderRef.request(r.id),
          collectionId: r.collectionId,
          parentId: r.folderId,
          orderIndex: r.orderIndex,
        ));
      }
      await (update(requests)..where((t) => t.folderId.isIn(chunk)))
          .write(RequestsCompanion(collectionId: Value(collectionId)));
    }
    await _forgetUids('folder', subtree);
    await _forgetUids('request', requestIds);
    return replaced;
  }

  /// Takes [moved] out of its level and puts it before [before] in the destination level; renumbers both levels
  /// densely and writes only the rows whose place changed.
  Future<List<Placement>> _applyMove(
    OrderRef moved, {
    required int fromCollection,
    required int? fromParent,
    required int toCollection,
    required int? toParent,
    required OrderRef? before,
  }) async {
    final sameLevel = fromCollection == toCollection && fromParent == toParent;
    final source = await levelItems(fromCollection, fromParent);
    final target = sameLevel ? source : await levelItems(toCollection, toParent);

    final previous = <OrderRef, Placement>{
      for (final item in source)
        item.ref: Placement(ref: item.ref, collectionId: fromCollection, parentId: fromParent, orderIndex: item.orderIndex),
      if (!sameLevel)
        for (final item in target)
          item.ref: Placement(ref: item.ref, collectionId: toCollection, parentId: toParent, orderIndex: item.orderIndex),
    };
    final next = <OrderRef, Placement>{};
    if (!sameLevel) {
      var i = 0;
      for (final item in CollectionOrder.sortLevel(source)) {
        if (item.ref == moved) continue;
        next[item.ref] = Placement(ref: item.ref, collectionId: fromCollection, parentId: fromParent, orderIndex: i++);
      }
    }
    for (final (i, ref) in CollectionOrder.placed(target, moved, before: before).indexed) {
      next[ref] = Placement(ref: ref, collectionId: toCollection, parentId: toParent, orderIndex: i);
    }

    final replaced = <Placement>[];
    for (final entry in next.entries) {
      final was = previous[entry.key]!;
      if (was.sameAs(entry.value)) continue;
      await _writePlace(entry.value);
      replaced.add(was);
    }
    return replaced;
  }

  Future<void> _requireDestination(int collectionId, int? folderId) async {
    final collection = await (select(collections)..where((t) => t.id.equals(collectionId))).getSingleOrNull();
    if (collection == null) throw const MoveRefusedException('That collection no longer exists.');
    if (folderId == null) return;
    final folder = await (select(folders)..where((t) => t.id.equals(folderId))).getSingleOrNull();
    if (folder == null || folder.collectionId != collectionId) {
      throw const MoveRefusedException('That folder is no longer in the collection you picked.');
    }
  }

  Future<bool> _folderExists(int id) async =>
      (await (select(folders)..where((t) => t.id.equals(id))).getSingleOrNull()) != null;

  Future<bool> _exists(OrderRef ref) async {
    if (ref.isFolder) return _folderExists(ref.id);
    final requests = attachedDatabase.requests;
    return (await (select(requests)..where((t) => t.id.equals(ref.id))).getSingleOrNull()) != null;
  }

  Future<void> _writePlace(Placement p) {
    if (p.ref.isFolder) {
      return (update(folders)..where((t) => t.id.equals(p.ref.id))).write(
        FoldersCompanion(
          collectionId: Value(p.collectionId),
          parentFolderId: Value(p.parentId),
          orderIndex: Value(p.orderIndex),
        ),
      );
    }
    final requests = attachedDatabase.requests;
    return (update(requests)..where((t) => t.id.equals(p.ref.id))).write(
      RequestsCompanion(collectionId: Value(p.collectionId), folderId: Value(p.parentId), orderIndex: Value(p.orderIndex)),
    );
  }

  Future<void> _writeOrder(OrderRef ref, int index) {
    if (ref.isFolder) {
      return (update(folders)..where((t) => t.id.equals(ref.id))).write(FoldersCompanion(orderIndex: Value(index)));
    }
    final requests = attachedDatabase.requests;
    return (update(requests)..where((t) => t.id.equals(ref.id))).write(RequestsCompanion(orderIndex: Value(index)));
  }

  /// A moved entity belongs to another collection now. Dropping its Git uid makes the next sync of that
  /// collection treat it as new; keeping it would make a pull of the old collection (which still lists the uid)
  /// think the repository is cloned here already. Its description and tags are keyed by id and stay.
  Future<void> _forgetUids(String kind, List<int> localIds) async {
    final db = attachedDatabase;
    for (final chunk in _chunks(localIds)) {
      await (db.delete(db.entityUids)..where((t) => t.kind.equals(kind) & t.localId.isIn(chunk))).go();
    }
  }

  static Iterable<List<int>> _chunks(List<int> ids) sync* {
    const size = 400;
    for (var i = 0; i < ids.length; i += size) {
      yield ids.sublist(i, i + size > ids.length ? ids.length : i + size);
    }
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
      await attachedDatabase.collectionDefaultsDao.duplicateDefaults(fromCollectionId: id, toCollectionId: newId);
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
      await placeAfter(
        original: OrderRef.folder(original.id),
        copy: OrderRef.folder(newId),
        collectionId: original.collectionId,
        parentId: original.parentFolderId,
      );
      await copyEntityNotes(attachedDatabase, 'folder', fromId: original.id, toId: newId);
      await attachedDatabase.folderDefaultsDao.duplicateDefaults(fromFolderId: original.id, toFolderId: newId);
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
      await attachedDatabase.folderDefaultsDao.duplicateDefaults(fromFolderId: folder.id, toFolderId: newFolderId);
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
