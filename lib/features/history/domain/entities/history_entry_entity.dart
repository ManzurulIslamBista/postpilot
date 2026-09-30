final class HistoryEntryEntity {
  final int id;
  final String method;
  final String url;
  final int? statusCode;
  final int? durationMs;
  final DateTime sentAt;

  const HistoryEntryEntity({
    required this.id,
    required this.method,
    required this.url,
    required this.statusCode,
    required this.durationMs,
    required this.sentAt,
  });

  bool get isSuccess => statusCode != null && statusCode! >= 200 && statusCode! < 300;
}
