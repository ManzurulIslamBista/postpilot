import 'package:drift/drift.dart';
import 'collections_table.dart';

/// JSON-encoded columns (headers/query params/auth config) keep the schema
/// stable while the shape of those key-value lists evolves.
class Requests extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get collectionId => integer().references(Collections, #id, onDelete: KeyAction.cascade)();
  IntColumn get folderId => integer().nullable().references(Folders, #id, onDelete: KeyAction.setNull)();
  TextColumn get name => text()();
  TextColumn get method => text().withDefault(const Constant('get'))();
  TextColumn get url => text().withDefault(const Constant(''))();
  TextColumn get headersJson => text().withDefault(const Constant('[]'))();
  TextColumn get queryParamsJson => text().withDefault(const Constant('[]'))();
  TextColumn get bodyType => text().withDefault(const Constant('none'))();
  TextColumn get rawContentType => text().withDefault(const Constant('json'))();
  TextColumn get bodyText => text().withDefault(const Constant(''))();
  TextColumn get formFieldsJson => text().withDefault(const Constant('[]'))();
  TextColumn get urlEncodedFieldsJson => text().withDefault(const Constant('[]'))();
  TextColumn get graphqlQuery => text().withDefault(const Constant(''))();
  TextColumn get graphqlVariables => text().withDefault(const Constant('{}'))();
  TextColumn get authType => text().withDefault(const Constant('inherit'))();
  TextColumn get authConfigJson => text().withDefault(const Constant('{}'))();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
