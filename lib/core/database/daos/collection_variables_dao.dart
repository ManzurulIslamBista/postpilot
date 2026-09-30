import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/collection_variables_table.dart';

part 'collection_variables_dao.g.dart';

@DriftAccessor(tables: [CollectionVariables])
class CollectionVariablesDao extends DatabaseAccessor<AppDatabase> with _$CollectionVariablesDaoMixin {
  CollectionVariablesDao(super.db);

  Stream<List<CollectionVariable>> watchByCollection(int collectionId) =>
      (select(collectionVariables)
            ..where((t) => t.collectionId.equals(collectionId))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .watch();

  Future<List<CollectionVariable>> getEnabledByCollection(int collectionId) =>
      (select(collectionVariables)..where((t) => t.collectionId.equals(collectionId) & t.enabled.equals(true))).get();

  Future<int> addVariable(CollectionVariablesCompanion entry) => into(collectionVariables).insert(entry);

  Future<void> updateVariable(int id, CollectionVariablesCompanion entry) =>
      (update(collectionVariables)..where((t) => t.id.equals(id))).write(entry);

  Future<void> deleteVariable(int id) => (delete(collectionVariables)..where((t) => t.id.equals(id))).go();

  /// Copies every variable (disabled ones included) of [fromCollectionId] onto
  /// [toCollectionId], keeping their order. Used to carry a collection's
  /// variables along when it is duplicated.
  Future<void> duplicateVariables({required int fromCollectionId, required int toCollectionId}) async {
    final rows = await (select(collectionVariables)
          ..where((t) => t.collectionId.equals(fromCollectionId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    for (final row in rows) {
      await into(collectionVariables).insert(
        row.toCompanion(true).copyWith(id: const Value.absent(), collectionId: Value(toCollectionId)),
      );
    }
  }
}
