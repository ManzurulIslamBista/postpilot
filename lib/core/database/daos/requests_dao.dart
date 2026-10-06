import 'package:drift/drift.dart';
import '../../../features/collections/domain/services/collection_order.dart';
import '../app_database.dart';
import '../tables/requests_table.dart';
import 'entity_notes_copy.dart';

part 'requests_dao.g.dart';

@DriftAccessor(tables: [Requests])
class RequestsDao extends DatabaseAccessor<AppDatabase> with _$RequestsDaoMixin {
  RequestsDao(super.db);

  /// Equal `order_index` values (every row of a workspace made before ordering existed) list by id, the order
  /// the rows were created in, so the list never depends on how SQLite happens to scan.
  Stream<List<Request>> watchByCollection(int collectionId) =>
      (select(requests)
            ..where((t) => t.collectionId.equals(collectionId))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex), (t) => OrderingTerm.asc(t.id)]))
          .watch();

  Stream<Request?> watchById(int id) =>
      (select(requests)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<Request?> findById(int id) => (select(requests)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Appends unless the entry carries an index: the request goes after everything already in its folder
  /// (folders and requests share one order), not at 0 where it would tie with its siblings.
  Future<int> createRequest(RequestsCompanion entry) {
    if (entry.orderIndex.present || !entry.collectionId.present) return into(requests).insert(entry);
    return transaction(() async {
      final next = await attachedDatabase.collectionsDao.nextOrderIndex(
        entry.collectionId.value,
        entry.folderId.present ? entry.folderId.value : null,
      );
      return into(requests).insert(entry.copyWith(orderIndex: Value(next)));
    });
  }

  Future<void> updateRequest(int id, RequestsCompanion entry) =>
      (update(requests)..where((t) => t.id.equals(id))).write(entry);

  Future<void> deleteRequest(int id) => (delete(requests)..where((t) => t.id.equals(id))).go();

  /// Deletes every request that sits directly in one of [folderIds]. `folder_id`
  /// is ON DELETE SET NULL, so deleting a folder alone would move its requests
  /// to the collection root instead of removing them.
  Future<void> deleteInFolders(Iterable<int> folderIds) =>
      (delete(requests)..where((t) => t.folderId.isIn(folderIds))).go();

  Future<int> duplicateRequest(int id) => transaction(() async {
        final original = await (select(requests)..where((t) => t.id.equals(id))).getSingle();
        final siblingNames =
            await (select(requests)..where((t) => _sameParent(t, original.collectionId, original.folderId)))
                .map((r) => r.name)
                .get();
        final name = _uniqueCopyName(original.name, siblingNames);
        final newId = await into(requests).insert(
          original
              .toCompanion(true)
              .copyWith(id: const Value.absent(), name: Value(name), updatedAt: const Value.absent()),
        );
        await attachedDatabase.collectionsDao.placeAfter(
          original: OrderRef.request(id),
          copy: OrderRef.request(newId),
          collectionId: original.collectionId,
          parentId: original.folderId,
        );
        await _copyExtras(fromRequestId: id, toRequestId: newId);
        return newId;
      });

  /// Copies every request directly under [folderId] in [collectionId] into
  /// [newFolderId] in [newCollectionId], keeping original names. Used to
  /// carry a collection's/folder's requests along when it is duplicated.
  Future<void> duplicateRequestsIn({
    required int collectionId,
    required int? folderId,
    required int newCollectionId,
    required int? newFolderId,
  }) async {
    final rows = await (select(requests)..where((t) => _sameParent(t, collectionId, folderId))).get();
    for (final row in rows) {
      final newId = await into(requests).insert(
        row.toCompanion(true).copyWith(
              id: const Value.absent(),
              collectionId: Value(newCollectionId),
              folderId: Value(newFolderId),
              updatedAt: const Value.absent(),
            ),
      );
      await _copyExtras(fromRequestId: row.id, toRequestId: newId);
    }
  }

  /// Carries the rows that hang off a request (its Tests, saved response
  /// examples, settings, description and tags) over to its copy.
  Future<void> _copyExtras({required int fromRequestId, required int toRequestId}) async {
    final scripts = await (select(attachedDatabase.requestScripts)..where((t) => t.requestId.equals(fromRequestId)))
        .getSingleOrNull();
    if (scripts != null) {
      await into(attachedDatabase.requestScripts)
          .insertOnConflictUpdate(scripts.toCompanion(true).copyWith(requestId: Value(toRequestId)));
    }
    final examples =
        await (select(attachedDatabase.responseExamples)..where((t) => t.requestId.equals(fromRequestId))).get();
    for (final example in examples) {
      await into(attachedDatabase.responseExamples).insert(
        example.toCompanion(true).copyWith(id: const Value.absent(), requestId: Value(toRequestId)),
      );
    }
    final settingsJson = await attachedDatabase.requestSettingsDao.get(fromRequestId);
    if (settingsJson != null) await attachedDatabase.requestSettingsDao.put(toRequestId, settingsJson);
    await copyEntityNotes(attachedDatabase, 'request', fromId: fromRequestId, toId: toRequestId);
  }

  Expression<bool> _sameParent($RequestsTable t, int collectionId, int? folderId) =>
      t.collectionId.equals(collectionId) & (folderId == null ? t.folderId.isNull() : t.folderId.equals(folderId));
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
