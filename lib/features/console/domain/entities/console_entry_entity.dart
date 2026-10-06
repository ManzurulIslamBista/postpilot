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

  /// A line the flow around a send added instead of a request (`attempt 2/3 after 1.2 s`, `page 3`): it explains
  /// the request listed just above it. Such an entry has no URL, status or size and is never an error.
  final String? note;

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
    this.note,
  });

  bool get isNote => note != null;

  bool get isSuccess => statusCode != null && statusCode! >= 200 && statusCode! < 300;

  /// Sent, with neither a reply nor a failure yet — [durationMs] is unknown.
  bool get isPending => note == null && statusCode == null && errorMessage == null;

  /// The console's "errors" filter answers "what went wrong?" — a 4xx/5xx
  /// reply is as much an answer as a dropped connection, so both count.
  bool get isError => errorMessage != null || (statusCode ?? 0) >= 400;
}
