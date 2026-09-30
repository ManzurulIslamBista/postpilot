import 'package:drift/drift.dart';
import 'collections_table.dart';

@TableIndex(name: 'collection_variables_collection_id', columns: {#collectionId})
class CollectionVariables extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get collectionId => integer().references(Collections, #id, onDelete: KeyAction.cascade)();
  TextColumn get key => text()();
  TextColumn get value => text().withDefault(const Constant(''))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
}
