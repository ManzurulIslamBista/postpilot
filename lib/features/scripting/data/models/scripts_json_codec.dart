import 'dart:convert';
import '../../domain/entities/assertion_entity.dart';
import '../../domain/entities/extractor_entity.dart';

/// Encodes/decodes the `assertionsJson` / `extractorsJson` columns of
/// `request_scripts` — a storage detail, not a domain type. The same item
/// shapes are used wherever tests are stored as data (the defaults of a folder
/// or collection, a workspace file, a Git doc): [assertionsToJson] and
/// [assertionsFromJson] are the list forms of the text columns.
abstract final class ScriptsJsonCodec {
  static String encodeAssertions(List<AssertionEntity> items) => jsonEncode(assertionsToJson(items));

  static List<Map<String, Object?>> assertionsToJson(List<AssertionEntity> items) => [
        for (final a in items) {'type': a.type.name, 'path': a.path, 'expected': a.expected},
      ];

  static List<AssertionEntity> decodeAssertions(String json) => assertionsFromJson(_decoded(json));

  /// Items that are not maps are skipped; an unknown type reads as "status is 2xx".
  static List<AssertionEntity> assertionsFromJson(Object? list) => [
        for (final e in _maps(list))
          AssertionEntity(
            type: AssertionType.values.firstWhere((t) => t.name == e['type'], orElse: () => AssertionType.statusIn2xx),
            path: e['path'] as String? ?? '',
            expected: e['expected'] as String? ?? '',
          ),
      ];

  static String encodeExtractors(List<ExtractorEntity> items) => jsonEncode(extractorsToJson(items));

  static List<Map<String, Object?>> extractorsToJson(List<ExtractorEntity> items) => [
        for (final x in items) {'source': x.source.name, 'path': x.path, 'scope': x.scope.name, 'key': x.variableKey},
      ];

  static List<ExtractorEntity> decodeExtractors(String json) => extractorsFromJson(_decoded(json));

  static List<ExtractorEntity> extractorsFromJson(Object? list) => [
        for (final e in _maps(list))
          ExtractorEntity(
            source: ExtractorSource.values
                .firstWhere((s) => s.name == e['source'], orElse: () => ExtractorSource.jsonPath),
            path: e['path'] as String? ?? '',
            scope: ExtractorScope.values
                .firstWhere((s) => s.name == e['scope'], orElse: () => ExtractorScope.environment),
            variableKey: e['key'] as String? ?? '',
          ),
      ];

  /// A corrupt column decodes as empty rather than throwing: this runs in
  /// the send path, and a bad row must not turn a successful request into a
  /// "send failed" error.
  static Object? _decoded(String json) {
    try {
      return jsonDecode(json);
    } on FormatException {
      return null;
    }
  }

  static Iterable<Map<String, dynamic>> _maps(Object? decoded) =>
      decoded is List ? decoded.whereType<Map<String, dynamic>>() : const [];
}
