final class ConsoleEntryEntity {
  final String method;
  final String url;
  final int headersCount;
  final int bodySize;
  final DateTime sentAt;
  final int? durationMs;
  final int? statusCode;
  final int? responseSize;
  final String? errorMessage;

  const ConsoleEntryEntity({
    required this.method,
    required this.url,
    required this.headersCount,
    required this.bodySize,
    required this.sentAt,
    required this.durationMs,
    required this.statusCode,
    required this.responseSize,
    required this.errorMessage,
  });

  bool get isSuccess => statusCode != null && statusCode! >= 200 && statusCode! < 300;

  /// Sent, with neither a reply nor a failure yet — [durationMs] is unknown.
  bool get isPending => statusCode == null && errorMessage == null;

  /// The console's "errors" filter answers "what went wrong?" — a 4xx/5xx
  /// reply is as much an answer as a dropped connection, so both count.
  bool get isError => errorMessage != null || (statusCode ?? 0) >= 400;
}
