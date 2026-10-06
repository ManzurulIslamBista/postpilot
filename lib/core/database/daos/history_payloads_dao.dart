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

  /// `request_json` of the given entries, by history id: what the list reads to learn where each
  /// entry came from. Entries without a payload row are simply absent.
  Future<Map<int, String>> requestJsonFor(Iterable<int> historyIds) async {
    final ids = historyIds.toList();
    final out = <int, String>{};
    // SQLite caps the number of bound variables of one statement.
    for (var start = 0; start < ids.length; start += 400) {
      final chunk = ids.sublist(start, start + 400 > ids.length ? ids.length : start + 400);
      final query = selectOnly(historyPayloads)
        ..addColumns([historyPayloads.historyId, historyPayloads.requestJson])
        ..where(historyPayloads.historyId.isIn(chunk));
      for (final row in await query.get()) {
        out[row.read(historyPayloads.historyId)!] = row.read(historyPayloads.requestJson)!;
      }
    }
    return out;
  }

  Future<void> deleteAll() => delete(historyPayloads).go();

  /// History ids whose [HistoryPayload.searchText] contains [needle] (already lower-cased).
  Future<List<int>> idsMatching(String needle) async {
    final escaped = needle.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    final rows = await (select(historyPayloads)..where((t) => t.searchText.like('%$escaped%', escapeChar: r'\'))).get();
    return [for (final row in rows) row.historyId];
  }
}
