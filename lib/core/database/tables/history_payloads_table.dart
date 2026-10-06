import 'package:drift/drift.dart';
import 'history_table.dart';

/// What a history entry needs to be searched, opened again and re-sent: the
/// request as saved (templates, never resolved secrets) and a bounded, masked
/// copy of the response text. Kept beside `history_entries` instead of widening
/// it, because the web database worker cannot ALTER a table. One row per entry.
class HistoryPayloads extends Table {
  IntColumn get historyId => integer().references(HistoryEntries, #id, onDelete: KeyAction.cascade)();

  /// The request snapshot (method, url, headers, params, body, auth type, name, collection).
  TextColumn get requestJson => text().withDefault(const Constant('{}'))();
  TextColumn get responseText => text().nullable()();
  TextColumn get responseContentType => text().nullable()();

  /// The response was longer than what is kept.
  BoolColumn get responseTruncated => boolean().withDefault(const Constant(false))();

  /// Lower-cased method, url, name, status and a body excerpt: what the search box matches.
  TextColumn get searchText => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {historyId};
}
