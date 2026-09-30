import 'package:drift/drift.dart';
import 'requests_table.dart';

/// Per-request declarative test assertions and response->variable extractors,
/// stored as raw JSON so their shape can evolve without schema changes.
class RequestScripts extends Table {
  IntColumn get requestId => integer().references(Requests, #id, onDelete: KeyAction.cascade)();
  TextColumn get assertionsJson => text().withDefault(const Constant('[]'))();
  TextColumn get extractorsJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {requestId};
}
