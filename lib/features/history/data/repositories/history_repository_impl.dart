import 'package:drift/drift.dart' show Value;
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/history_dao.dart';
import '../../domain/entities/history_entry_entity.dart';
import '../../domain/repositories/history_repository.dart';

final class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryDao _dao;
  HistoryRepositoryImpl(this._dao);

  bool _oldHeadersForgotten = false;

  @override
  Stream<List<HistoryEntryEntity>> watchRecent() => _dao.watchRecent().map(
        (rows) => rows
            .map((r) => HistoryEntryEntity(
                  id: r.id,
                  method: r.method,
                  url: r.url,
                  statusCode: r.statusCode,
                  durationMs: r.durationMs,
                  sentAt: r.sentAt,
                ))
            .toList(),
      );

  /// [responseHeaders] is accepted for the sake of the interface but not
  /// stored: nothing reads it, and it holds `Set-Cookie` and token headers.
  /// The table is trimmed to [HistoryDao.maxRows] on every write.
  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) async {
    await _forgetOldHeaders();
    await _dao.record(HistoryEntriesCompanion.insert(
      method: method,
      url: url,
      statusCode: Value(statusCode),
      durationMs: Value(durationMs),
    ));
  }

  /// Once per run: rows written by older versions still carry their headers.
  Future<void> _forgetOldHeaders() async {
    if (_oldHeadersForgotten) return;
    try {
      await _dao.forgetStoredHeaders();
      _oldHeadersForgotten = true;
    } catch (_) {
      // Tidying must never stop a send from being recorded; tried again next time.
    }
  }

  @override
  Future<void> clear() => _dao.clear();
}
