import 'dart:convert';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import 'json_path_resolver.dart';

/// Lazily-decoded view of a response shared by assertions and extractors:
/// body text, tolerant JSON parse, case-insensitive header lookup.
final class ResponseReader {
  final ApiResponseEntity response;
  ResponseReader(this.response);

  late final String bodyText = utf8.decode(response.bodyBytes, allowMalformed: true);
  late final ({bool valid, Object? value}) _json = _parseJson();

  bool get isJson => _json.valid;

  /// Value at [path] in the JSON body; `null` when the body isn't JSON or
  /// the path doesn't resolve.
  Object? jsonPath(String path) => _json.valid ? JsonPathResolver.resolve(_json.value, path) : null;

  String? header(String name) {
    final wanted = name.trim().toLowerCase();
    for (final entry in response.headers.entries) {
      if (entry.key.toLowerCase() == wanted) return entry.value;
    }
    return null;
  }

  ({bool valid, Object? value}) _parseJson() {
    try {
      return (valid: true, value: jsonDecode(bodyText));
    } on FormatException {
      return (valid: false, value: null);
    }
  }

  /// Scalars print bare (so `42` matches an expected "42"); containers as
  /// compact JSON. A whole-number double prints without `.0`: the VM decodes
  /// `100.0` as a double and would print `100.0`, while the web build prints `100`.
  static String stringify(Object? value) => switch (value) {
        null => 'null',
        String s => s,
        double d when d.isFinite && d == d.truncateToDouble() && d.abs() < 1e15 => d.toInt().toString(),
        num() || bool() => value.toString(),
        _ => jsonEncode(value),
      };
}
