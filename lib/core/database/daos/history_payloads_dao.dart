import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/history_payloads_table.dart';

part 'history_payloads_dao.g.dart';

@DriftAccessor(tables: [HistoryPayloads])
class HistoryPayloadsDao extends DatabaseAccessor<AppDatabase> with _$HistoryPayloadsDaoMixin {
  HistoryPayloadsDao(super.db);

  Future<HistoryPayload?> findByHistory(int historyId) =>
      (select(historyPayloads)..where((t) => t.historyId.equals(historyId))).getSingleOrNull();

  Future<void> upsert(HistoryPayloadsCompanion row) => into(historyPayloads).insertOnConflictUpdate(row);

  /// History ids whose [HistoryPayload.searchText] contains [needle] (already lower-cased).
  Future<List<int>> idsMatching(String needle) async {
    final escaped = needle.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    final rows = await (select(historyPayloads)..where((t) => t.searchText.like('%$escaped%', escapeChar: r'\'))).get();
    return [for (final row in rows) row.historyId];
  }
}
