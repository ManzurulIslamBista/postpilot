import 'dart:convert';
import '../../domain/entities/assertion_entity.dart';
import '../../domain/entities/extractor_entity.dart';

/// Encodes/decodes the `assertionsJson` / `extractorsJson` columns of
/// `request_scripts` — a storage detail, not a domain type.
abstract final class ScriptsJsonCodec {
  static String encodeAssertions(List<AssertionEntity> items) => jsonEncode([
        for (final a in items) {'type': a.type.name, 'path': a.path, 'expected': a.expected},
      ]);

  static List<AssertionEntity> decodeAssertions(String json) => [
        for (final e in _items(json))
          AssertionEntity(
            type: AssertionType.values.firstWhere((t) => t.name == e['type'], orElse: () => AssertionType.statusIn2xx),
            path: e['path'] as String? ?? '',
            expected: e['expected'] as String? ?? '',
          ),
      ];

  static String encodeExtractors(List<ExtractorEntity> items) => jsonEncode([
        for (final x in items) {'source': x.source.name, 'path': x.path, 'scope': x.scope.name, 'key': x.variableKey},
      ]);

  static List<ExtractorEntity> decodeExtractors(String json) => [
        for (final e in _items(json))
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
  static Iterable<Map<String, dynamic>> _items(String json) {
    try {
      final decoded = jsonDecode(json);
      return decoded is List ? decoded.whereType<Map<String, dynamic>>() : const [];
    } on FormatException {
      return const [];
    }
  }
}
