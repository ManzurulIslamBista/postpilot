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
}
