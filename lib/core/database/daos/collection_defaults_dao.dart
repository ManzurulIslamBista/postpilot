import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/collection_defaults_table.dart';

part 'collection_defaults_dao.g.dart';

@DriftAccessor(tables: [CollectionDefaults])
class CollectionDefaultsDao extends DatabaseAccessor<AppDatabase> with _$CollectionDefaultsDaoMixin {
  CollectionDefaultsDao(super.db);

  Future<CollectionDefault?> findByCollection(int collectionId) =>
      (select(collectionDefaults)..where((t) => t.collectionId.equals(collectionId))).getSingleOrNull();

  Stream<CollectionDefault?> watchByCollection(int collectionId) =>
      (select(collectionDefaults)..where((t) => t.collectionId.equals(collectionId))).watchSingleOrNull();

  Future<void> upsert(CollectionDefaultsCompanion row) => into(collectionDefaults).insertOnConflictUpdate(row);

  Future<void> deleteForCollection(int collectionId) =>
      (delete(collectionDefaults)..where((t) => t.collectionId.equals(collectionId))).go();

  /// Copies [fromCollectionId]'s defaults, if it has any, onto [toCollectionId]. Used to carry
  /// them along when a collection is duplicated.
  Future<void> duplicateDefaults({required int fromCollectionId, required int toCollectionId}) async {
    final original = await findByCollection(fromCollectionId);
    if (original != null) await upsert(original.toCompanion(true).copyWith(collectionId: Value(toCollectionId)));
  }
}
