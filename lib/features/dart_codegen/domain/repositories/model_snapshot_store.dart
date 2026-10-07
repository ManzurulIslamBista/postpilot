import '../services/model_schema_diff.dart';

/// Remembers the model classes Dart Studio generated last for a source (a collection, or a set of pasted samples), so the
/// next generation can show what changed. Only the shape is kept (class and field names, types, nullability), never a
/// value from a response.
abstract interface class ModelSnapshotStore {
  /// The snapshot kept for [source], or null when there is none (or it cannot be read).
  Future<SchemaSnapshot?> load(String source);

  Future<void> save(String source, SchemaSnapshot snapshot);

  Future<void> forget(String source);

  /// `collection:12`, the key an API layer of a collection is kept under.
  static String collectionSource(int collectionId) => 'collection:$collectionId';

  /// `samples:UserResponse`, the key of a set of pasted samples: the class name they are generated under.
  static String samplesSource(String className) => 'samples:${className.trim().toLowerCase()}';
}
