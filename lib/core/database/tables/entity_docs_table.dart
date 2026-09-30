import 'package:drift/drift.dart';

/// Markdown description of a collection, folder or request.
class EntityDocs extends Table {
  TextColumn get kind => text()();
  IntColumn get localId => integer()();
  TextColumn get markdown => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {kind, localId};
}
