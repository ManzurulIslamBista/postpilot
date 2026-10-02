import 'dart:convert';
import '../../../../core/utils/variable_resolver.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../response_tools/domain/services/json_schema_tools.dart';
import '../entities/assertion_entity.dart';
import '../entities/assertion_result.dart';
import 'response_reader.dart';

final class AssertionEvaluator {
  const AssertionEvaluator();

  static const _noJsonPath = 'Enter a JSON path';

  /// `{{variables}}` in each assertion's expected value, JSON path and header
  /// name are resolved through [resolver] first, so a check can compare against
  /// a value an earlier request extracted. A result keeps the unresolved text
  /// in its name.
  List<AssertionResult> evaluate(
    ApiResponseEntity response,
    List<AssertionEntity> assertions, [
    VariableResolver resolver = const VariableResolver.layered([]),
  ]) {
    final reader = ResponseReader(response);
    return [for (final assertion in assertions) _evaluate(reader, assertion, resolver)];
  }

  AssertionResult _evaluate(ResponseReader reader, AssertionEntity raw, VariableResolver resolver) {
    final assertion = raw.copyWith(path: resolver.resolve(raw.path), expected: resolver.resolve(raw.expected));
    final expected = assertion.expected.trim();
    final status = reader.response.statusCode.toString();
    final (passed, actual) = switch (assertion.type) {
      AssertionType.statusEquals => (status == expected, status),
      AssertionType.statusIn2xx => (reader.response.isSuccess, status),
      AssertionType.bodyContains => _bodyContains(reader, expected),
      AssertionType.jsonPathEquals => _jsonPathEquals(reader, assertion.path, expected),
      AssertionType.jsonPathExists => _jsonPathExists(reader, assertion.path),
      AssertionType.headerEquals => _headerEquals(reader, assertion.path, expected),
      AssertionType.headerExists => _headerExists(reader, assertion.path),
      AssertionType.responseTimeBelowMs => _responseTimeBelow(reader, expected),
      AssertionType.jsonSchema => _matchesSchema(reader, assertion.path, expected),
    };
    // Named after what the user wrote, not the resolved values: a failed
    // check's name is shown in the runner and exported, and `{{token}}` must
    // not turn into the token there.
    return AssertionResult(name: raw.name, passed: passed, actual: actual);
  }

  (bool, String) _bodyContains(ResponseReader reader, String expected) {
    if (expected.isEmpty) return (false, 'No text to search for');
    final found = reader.bodyText.contains(expected);
    return (found, found ? 'Found in body' : 'Not found in body');
  }

  (bool, String) _jsonPathEquals(ResponseReader reader, String path, String expected) {
    if (path.trim().isEmpty) return (false, _noJsonPath);
    if (!reader.isJson) return (false, 'Body is not valid JSON');
    final value = reader.jsonPath(path);
    return (_jsonEquals(value, expected), ResponseReader.stringify(value));
  }

  /// Containers also match [expected] read as JSON, so key order and spacing
  /// in what the user typed don't have to mirror the compact response text.
  bool _jsonEquals(Object? value, String expected) {
    if (ResponseReader.stringify(value) == expected) return true;
    if (value is! Map && value is! List) return false;
    try {
      return _deepEquals(value, jsonDecode(expected));
    } on FormatException {
      return false;
    }
  }

  (bool, String) _jsonPathExists(ResponseReader reader, String path) {
    if (path.trim().isEmpty) return (false, _noJsonPath);
    if (!reader.isJson) return (false, 'Body is not valid JSON');
    final value = reader.jsonPath(path);
    return (value != null, value == null ? 'Missing' : ResponseReader.stringify(value));
  }

  (bool, String) _headerEquals(ResponseReader reader, String name, String expected) {
    final value = reader.header(name);
    return (value != null && value.trim() == expected, value ?? 'Missing');
  }

  (bool, String) _headerExists(ResponseReader reader, String name) {
    final value = reader.header(name);
    return (value != null, value ?? 'Missing');
  }

  /// [expected] is a JSON Schema document; [path] narrows the check to part of
  /// the body (blank = the whole body). The first few violations are the "actual".
  (bool, String) _matchesSchema(ResponseReader reader, String path, String expected) {
    if (expected.isEmpty) return (false, 'No schema');
    if (!reader.isJson) return (false, 'Body is not valid JSON');
    final Object? schema;
    try {
      schema = jsonDecode(expected);
    } on FormatException {
      return (false, 'The schema is not valid JSON');
    }
    if (schema is! Map<String, dynamic>) return (false, 'The schema must be a JSON object');
    final value = path.trim().isEmpty ? reader.jsonPath(r'$') : reader.jsonPath(path);
    final violations = JsonSchemaTools.validate(schema, value, limit: 5);
    return (violations.isEmpty, violations.isEmpty ? 'Matches' : violations.join('; '));
  }

  (bool, String) _responseTimeBelow(ResponseReader reader, String expected) {
    final limit = int.tryParse(expected);
    if (limit == null) return (false, 'Invalid limit "$expected"');
    final ms = reader.response.duration.inMilliseconds;
    return (ms < limit, '$ms ms');
  }
}

/// Structural equality for decoded JSON: map key order is irrelevant and `1`
/// equals `1.0`.
bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length && a.keys.every((key) => b.containsKey(key) && _deepEquals(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length && Iterable<int>.generate(a.length).every((i) => _deepEquals(a[i], b[i]));
  }
  return a == b;
}
