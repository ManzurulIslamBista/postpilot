import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/collection_auth_table.dart';

part 'collection_auth_dao.g.dart';

@DriftAccessor(tables: [CollectionAuth])
class CollectionAuthDao extends DatabaseAccessor<AppDatabase> with _$CollectionAuthDaoMixin {
  CollectionAuthDao(super.db);

  Future<CollectionAuthData?> findByCollection(int collectionId) =>
      (select(collectionAuth)..where((t) => t.collectionId.equals(collectionId))).getSingleOrNull();

  Stream<CollectionAuthData?> watchByCollection(int collectionId) =>
      (select(collectionAuth)..where((t) => t.collectionId.equals(collectionId))).watchSingleOrNull();

  Future<void> upsert(int collectionId, String authJson) => into(collectionAuth).insertOnConflictUpdate(
        CollectionAuthCompanion.insert(collectionId: Value(collectionId), authJson: Value(authJson)),
      );

  /// Copies [fromCollectionId]'s default auth, if it has one, onto
  /// [toCollectionId]. Used to carry it along when a collection is duplicated.
  Future<void> duplicateAuth({required int fromCollectionId, required int toCollectionId}) async {
    final original = await findByCollection(fromCollectionId);
    if (original != null) await upsert(toCollectionId, original.authJson);
  }
}
