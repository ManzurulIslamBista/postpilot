import 'package:drift/drift.dart';
import 'requests_table.dart';

/// Per-request behaviour toggles (raw JSON so the set can grow without schema
/// changes). One row per request.
class RequestSettingEntries extends Table {
  IntColumn get requestId => integer().references(Requests, #id, onDelete: KeyAction.cascade)();
  TextColumn get settingsJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {requestId};
}
