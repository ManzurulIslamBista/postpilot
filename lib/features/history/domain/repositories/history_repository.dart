import '../entities/history_entry_entity.dart';

abstract interface class HistoryRepository {
  Stream<List<HistoryEntryEntity>> watchRecent();

  /// Response bodies are deliberately not kept: nothing reads them back, and
  /// storing every payload would grow the database without bound.
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  });

  Future<void> clear();
}
