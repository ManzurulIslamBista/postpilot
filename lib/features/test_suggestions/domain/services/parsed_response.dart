import 'dart:convert';
import '../../../request_builder/domain/entities/api_response_entity.dart';

/// A response read once for the test-intelligence engine: the body as text and, when it is JSON, decoded; headers
/// looked up without regard to case.
final class ParsedResponse {
  final ApiResponseEntity response;
  final String text;
  final bool isJson;

  /// The decoded body; only meaningful when [isJson].
  final Object? json;

  const ParsedResponse._(this.response, this.text, this.isJson, this.json);

  factory ParsedResponse.of(ApiResponseEntity response) {
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    // A body cut off at the size limit is not a document: whatever parses from it would be a different shape.
    if (response.truncated || text.trim().isEmpty) return ParsedResponse._(response, text, false, null);
    try {
      return ParsedResponse._(response, text, true, jsonDecode(text));
    } on FormatException {
      return ParsedResponse._(response, text, false, null);
    }
  }

  int get status => response.statusCode;

  int get timeMs => response.duration.inMilliseconds;

  bool get isEmpty => text.trim().isEmpty;

  /// The value of header [name], or null.
  String? header(String name) {
    final wanted = name.toLowerCase();
    for (final entry in response.headers.entries) {
      if (entry.key.toLowerCase() == wanted) return entry.value;
    }
    return null;
  }

  /// The header names in lower case, each with its value.
  Map<String, String> get lowerCaseHeaders => {
        for (final entry in response.headers.entries) entry.key.toLowerCase(): entry.value,
      };
}
