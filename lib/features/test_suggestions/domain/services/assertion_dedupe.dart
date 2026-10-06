import 'dart:convert';
import '../../../scripting/domain/entities/assertion_entity.dart';
import 'field_path.dart';

/// Decides whether two checks say the same thing, so adding suggested tests never doubles one the request has.
///
/// Two checks match when they have the same type and the same subject (path, header name) and expect the same
/// value; blanks, a leading `$.`, header-name case and the key order or spacing of a JSON Schema do not matter.
abstract final class AssertionDedupe {
  /// A string equal for every spelling of [assertion].
  static String keyOf(AssertionEntity assertion) {
    final type = assertion.type;
    final subject = switch (type) {
      AssertionType.headerEquals || AssertionType.headerExists => assertion.path.trim().toLowerCase(),
      AssertionType.jsonPathEquals || AssertionType.jsonPathExists || AssertionType.jsonSchema => FieldPath.normalize(assertion.path),
      _ => '',
    };
    final expected = switch (type) {
      AssertionType.statusIn2xx || AssertionType.jsonPathExists || AssertionType.headerExists => '',
      AssertionType.jsonSchema => _canonicalJson(assertion.expected),
      _ => assertion.expected.trim(),
    };
    return '${type.name}\u0000$subject\u0000$expected';
  }

  static bool same(AssertionEntity a, AssertionEntity b) => keyOf(a) == keyOf(b);

  /// [fresh] without what [existing] already has and without repeats inside [fresh] itself; the order is kept.
  static List<AssertionEntity> newOnly(Iterable<AssertionEntity> existing, Iterable<AssertionEntity> fresh) {
    final seen = {for (final e in existing) keyOf(e)};
    return [
      for (final f in fresh)
        if (seen.add(keyOf(f))) f,
    ];
  }

  /// A JSON document as one canonical text: keys sorted, no spacing. Text that is not JSON is compared as written.
  static String _canonicalJson(String text) {
    final trimmed = text.trim();
    try {
      return jsonEncode(_sorted(jsonDecode(trimmed)));
    } on FormatException {
      return trimmed;
    }
  }

  static Object? _sorted(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _sorted(value[k])};
    }
    if (value is List) return [for (final v in value) _sorted(v)];
    return value;
  }
}
