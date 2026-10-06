import 'package:drift/drift.dart';
import 'collections_table.dart';

/// Defaults a folder passes down to every request below it (and to its
/// sub-folders): headers, variables, auth and tests. All raw JSON so the shape
/// can grow without a schema change. One row per folder, only when it has any.
class FolderDefaults extends Table {
  IntColumn get folderId => integer().references(Folders, #id, onDelete: KeyAction.cascade)();
  TextColumn get headersJson => text().withDefault(const Constant('[]'))();
  TextColumn get variablesJson => text().withDefault(const Constant('[]'))();
  TextColumn get authJson => text().withDefault(const Constant('{}'))();
  TextColumn get scriptsJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {folderId};
}
