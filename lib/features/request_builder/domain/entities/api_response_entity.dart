import 'dart:typed_data';

final class ApiResponseEntity {
  final int statusCode;
  final String statusMessage;
  final Map<String, String> headers;
  final Uint8List bodyBytes;
  final Duration duration;

  /// True when the body was cut off at the max response size setting, so
  /// [bodyBytes] is only the first part of what the server sent.
  final bool truncated;

  const ApiResponseEntity({
    required this.statusCode,
    required this.statusMessage,
    required this.headers,
    required this.bodyBytes,
    required this.duration,
    this.truncated = false,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
  int get sizeBytes => bodyBytes.length;
}
