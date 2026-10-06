import '../entities/history_entry_entity.dart';

abstract interface class HistoryRepository {
  Stream<List<HistoryEntryEntity>> watchRecent();

  /// Response bodies are deliberately not kept: nothing reads them back, and
  /// storing every payload would grow the database without bound. The same
  /// goes for [responseHeaders], which hold `Set-Cookie` and token headers:
  /// they are part of the signature for callers' sake and are not stored.
  /// Only the newest 1000 entries are kept.
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  });

  Future<void> clear();
}
