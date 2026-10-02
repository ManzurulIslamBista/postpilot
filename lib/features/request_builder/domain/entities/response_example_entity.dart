final class ResponseExampleEntity {
  final int id;
  final int requestId;
  final String name;
  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final DateTime savedAt;

  const ResponseExampleEntity({
    required this.id,
    required this.requestId,
    required this.name,
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.savedAt,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// Marks, among [headers], an example saved from a response that was cut off
  /// at the size limit: the examples table has no column for it, and the header
  /// keeps the fact with the example through backups and restores.
  static const truncatedHeader = 'x-postpilot-truncated';

  /// True when [body] is only the first part of what the server sent.
  bool get truncated => headers.keys.any((name) => name.toLowerCase() == truncatedHeader);
}
