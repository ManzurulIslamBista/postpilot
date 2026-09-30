import 'package:drift/drift.dart';
import 'collections_table.dart';

/// Collection-level default auth (raw JSON) that requests with
/// `AuthType.inherit` fall back to. One row per collection.
class CollectionAuth extends Table {
  IntColumn get collectionId => integer().references(Collections, #id, onDelete: KeyAction.cascade)();
  TextColumn get authJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {collectionId};
}
