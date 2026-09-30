import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/history_table.dart';

part 'history_dao.g.dart';

typedef HistoryListRow = ({int id, String method, String url, int? statusCode, int? durationMs, DateTime sentAt});

@DriftAccessor(tables: [HistoryEntries])
class HistoryDao extends DatabaseAccessor<AppDatabase> with _$HistoryDaoMixin {
  HistoryDao(super.db);

  /// Newest first, list columns only: this stream re-runs after every send, and
  /// selecting whole rows would re-read every stored response each time.
  Stream<List<HistoryListRow>> watchRecent({int limit = 200}) {
    final query = selectOnly(historyEntries)
      ..addColumns([
        historyEntries.id,
        historyEntries.method,
        historyEntries.url,
        historyEntries.statusCode,
        historyEntries.durationMs,
        historyEntries.sentAt,
      ])
      ..orderBy([OrderingTerm.desc(historyEntries.sentAt)])
      ..limit(limit);
    return query
        .map((row) => (
              id: row.read(historyEntries.id)!,
              method: row.read(historyEntries.method)!,
              url: row.read(historyEntries.url)!,
              statusCode: row.read(historyEntries.statusCode),
              durationMs: row.read(historyEntries.durationMs),
              sentAt: row.read(historyEntries.sentAt)!,
            ))
        .watch();
  }

  Future<int> record(HistoryEntriesCompanion entry) => into(historyEntries).insert(entry);

  Future<void> clear() => delete(historyEntries).go();
}
