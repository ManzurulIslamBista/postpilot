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
      // `sent_at` only has the resolution of a second; the id breaks the tie between sends within one.
      ..orderBy([OrderingTerm.desc(historyEntries.sentAt), OrderingTerm.desc(historyEntries.id)])
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

  /// Rows kept on disk. The list shows the newest [watchRecent] 200; the rest is
  /// headroom for a longer view, so the table cannot grow for ever.
  static const maxRows = 1000;

  /// Adds [entry] and drops whatever falls out of the newest [keep] (the
  /// history settings' "max entries"), in one transaction so the watchers see a
  /// single change.
  Future<int> record(HistoryEntriesCompanion entry, {int keep = maxRows}) => transaction(() async {
        final id = await into(historyEntries).insert(entry);
        await prune(keep: keep);
        return id;
      });

  /// Deletes every row sent before [cutoff] (the history settings' retention in days).
  Future<int> pruneOlderThan(DateTime cutoff) =>
      (delete(historyEntries)..where((row) => row.sentAt.isSmallerThanValue(cutoff))).go();

  /// Deletes every row but the [keep] newest. Newest by send time, then by id
  /// because `sent_at` only has the resolution of a second.
  Future<void> prune({int keep = maxRows}) {
    final newest = selectOnly(historyEntries)
      ..addColumns([historyEntries.id])
      ..orderBy([OrderingTerm.desc(historyEntries.sentAt), OrderingTerm.desc(historyEntries.id)])
      ..limit(keep);
    return (delete(historyEntries)..where((row) => row.id.isNotInQuery(newest))).go();
  }

  /// Empties the response headers older versions stored with every row: they
  /// held `Set-Cookie` and token headers, and nothing ever read them back.
  Future<int> forgetStoredHeaders() => (update(historyEntries)..where((row) => row.responseHeadersJson.isNotValue('{}')))
      .write(const HistoryEntriesCompanion(responseHeadersJson: Value('{}')));

  Future<void> clear() => delete(historyEntries).go();
}
