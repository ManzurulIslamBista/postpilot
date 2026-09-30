import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/history_dao.dart';
import '../../domain/entities/history_entry_entity.dart';
import '../../domain/repositories/history_repository.dart';

final class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryDao _dao;
  const HistoryRepositoryImpl(this._dao);

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

  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) =>
      _dao.record(HistoryEntriesCompanion.insert(
        method: method,
        url: url,
        statusCode: Value(statusCode),
        durationMs: Value(durationMs),
        responseHeadersJson: Value(jsonEncode(responseHeaders)),
      ));

  @override
  Future<void> clear() => _dao.clear();
}
