import 'package:drift/drift.dart';
import 'collections_table.dart';

/// Collection-level defaults that have no table of their own yet: headers every
/// request inherits and the collection's tests. (Default auth lives in
/// `collection_auth`, variables in `collection_variables`.) Raw JSON, one row
/// per collection.
class CollectionDefaults extends Table {
  IntColumn get collectionId => integer().references(Collections, #id, onDelete: KeyAction.cascade)();
  TextColumn get headersJson => text().withDefault(const Constant('[]'))();
  TextColumn get scriptsJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {collectionId};
}
