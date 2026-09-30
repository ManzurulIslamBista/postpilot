import '../entities/collection_variable_entity.dart';

abstract interface class CollectionVariableRepository {
  Stream<List<CollectionVariableEntity>> watchByCollection(int collectionId);

  /// Inserts when [variable.id] is 0, otherwise updates that row.
  Future<void> upsert(CollectionVariableEntity variable);
  Future<void> delete(int id);

  /// Flat, enabled-only key/value map for one collection — sits between
  /// globals and the active environment when resolving `{{variable}}` tokens.
  Future<Map<String, String>> getEnabledMap(int collectionId);
}
