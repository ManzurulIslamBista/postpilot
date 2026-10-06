import 'dart:convert';
import '../../../import_export/domain/services/openapi_parser.dart';

/// Reads the schemas of an OpenAPI 3 / Swagger 2 document the way the test generator needs them, on top of the
/// importer's own `$ref` and `allOf` handling ([OpenApiDocumentView]):
///
///  * [inline] gives a self-contained JSON Schema (what an assertion stores), with every `$ref` followed, and the
///    `required` lists of all the members of an `allOf` joined (the importer's flattening keeps only the first one);
///  * [conform] and [valueFor] give values that satisfy a schema (the importer's placeholders ignore ranges and lengths).
final class OpenApiSchemas {
  static const _maxChars = 65536;
  static const _scalarKeys = ['type', 'format', 'enum', 'const', 'minimum', 'maximum', 'minLength', 'maxLength', 'pattern', 'minItems', 'maxItems', 'exclusiveMinimum', 'exclusiveMaximum'];

  final OpenApiDocumentView _view;
  const OpenApiSchemas(this._view);

  // --- inlining ------------------------------------------------------------------

  /// [node] as a self-contained JSON Schema. A schema that contains itself is cut where it repeats (anything goes
  /// there). [forRequest] drops `readOnly` properties (a client never sends them), otherwise `writeOnly` ones (a
  /// response never holds them). A result too big for an assertion is cut to fewer levels.
  Map<String, dynamic> inline(Map<String, dynamic> node, {required bool forRequest}) {
    var depth = 12;
    var schema = _inline(node, <String>{}, 0, depth, forRequest);
    while (jsonEncode(schema).length > _maxChars && depth > 2) {
      depth -= 3;
      schema = _inline(node, <String>{}, 0, depth, forRequest);
    }
    return schema;
  }

  Map<String, dynamic> _inline(Map<String, dynamic> node, Set<String> visiting, int depth, int maxDepth, bool forRequest) {
    if (depth >= maxDepth) return const {};
    final ref = node[r'$ref'];
    if (ref is String && !visiting.add(ref)) return const {};
    try {
      final flat = _view.flatten(node);
      // A reference to another reference: follow it too.
      if (flat[r'$ref'] is String) return _inline(flat, visiting, depth + 1, maxDepth, forRequest);
      final out = <String, dynamic>{};
      for (final key in _scalarKeys) {
        if (flat.containsKey(key)) out[key] = flat[key];
      }
      if (flat['nullable'] == true || flat['x-nullable'] == true) out['nullable'] = true;
      if (flat['additionalProperties'] == false) out['additionalProperties'] = false;

      final props = flat['properties'];
      final kept = <String>{};
      if (props is Map) {
        final properties = <String, dynamic>{};
        for (final e in props.entries) {
          final child = e.value is Map ? (e.value as Map).cast<String, dynamic>() : const <String, dynamic>{};
          final resolved = _view.flatten(child);
          final dropped = forRequest ? resolved['readOnly'] == true : resolved['writeOnly'] == true;
          if (dropped) continue;
          kept.add('${e.key}');
          properties['${e.key}'] = _inline(child, visiting, depth + 1, maxDepth, forRequest);
        }
        out['properties'] = properties;
      }
      final required = _required(node, <String>{}).where((name) => props is! Map || kept.contains(name) || !props.containsKey(name)).toList();
      if (required.isNotEmpty) out['required'] = required;

      final items = flat['items'];
      if (items is Map) out['items'] = _inline(items.cast<String, dynamic>(), visiting, depth + 1, maxDepth, forRequest);
      for (final key in const ['oneOf', 'anyOf']) {
        final options = flat[key];
        if (options is List && options.isNotEmpty) {
          out[key] = [for (final o in options) if (o is Map) _inline(o.cast<String, dynamic>(), visiting, depth + 1, maxDepth, forRequest)];
        }
      }
      return out;
    } finally {
      if (ref is String) visiting.remove(ref);
    }
  }

  /// The required properties of [node]: its own list and that of every member of its `allOf`, in the order met.
  List<String> _required(Map<String, dynamic> node, Set<String> seen) {
    final ref = node[r'$ref'];
    if (ref is String && !seen.add(ref)) return const [];
    final resolved = _view.resolve(node);
    final out = <String>[];
    void add(String name) {
      if (!out.contains(name)) out.add(name);
    }

    if (resolved[r'$ref'] is String) {
      for (final name in _required(resolved, seen)) {
        add(name);
      }
    }
    final own = resolved['required'];
    if (own is List) {
      for (final name in own.whereType<String>()) {
        add(name);
      }
    }
    final members = resolved['allOf'];
    if (members is List) {
      for (final member in members) {
        if (member is! Map) continue;
        for (final name in _required(member.cast<String, dynamic>(), seen)) {
          add(name);
        }
      }
    }
    return out;
  }

  // --- values --------------------------------------------------------------------

  /// A value that satisfies [schema]: the first enum member, numbers inside their range, strings long enough,
  /// arrays with enough items, objects with their required properties.
  Object? valueFor(Map<String, dynamic> schema, {int depth = 0}) => conform(null, schema, depth: depth);

  /// [value] changed as little as possible so that it satisfies [schema]: a placeholder that is out of range moves
  /// to the nearest allowed value, a missing required property is added, a wrong kind of value is replaced.
  Object? conform(Object? value, Map<String, dynamic> schema, {int depth = 0}) {
    if (depth > 8) return value;
    final enumValues = schema['enum'];
    if (enumValues is List && enumValues.isNotEmpty) {
      return enumValues.any((e) => e == value) ? value : enumValues.first;
    }
    final type = _typeOf(schema);
    switch (type) {
      case 'integer':
      case 'number':
        var n = value is num ? value : (_num(schema['minimum']) ?? 0);
        final min = _num(schema['minimum']);
        final max = _num(schema['maximum']);
        if (min != null) {
          final lower = schema['exclusiveMinimum'] == true ? min + 1 : min;
          if (n < lower) n = lower;
        }
        if (max != null) {
          final upper = schema['exclusiveMaximum'] == true ? max - 1 : max;
          if (n > upper) n = upper;
        }
        return type == 'integer' ? n.round() : n;
      case 'string':
        var s = value is String ? value : _stringFor(schema);
        final minLength = schema['minLength'];
        final maxLength = schema['maxLength'];
        if (minLength is int && s.length < minLength) s = s.padRight(minLength, 'x');
        if (maxLength is int && s.length > maxLength) s = s.substring(0, maxLength);
        return s;
      case 'boolean':
        return value is bool ? value : true;
      case 'array':
        final items = schema['items'] is Map ? (schema['items'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
        final list = [
          if (value is List)
            for (final v in value) conform(v, items, depth: depth + 1),
        ];
        final minItems = schema['minItems'];
        final maxItems = schema['maxItems'];
        while (minItems is int && list.length < minItems && list.length < 100) {
          list.add(conform(null, items, depth: depth + 1));
        }
        if (maxItems is int && list.length > maxItems) list.removeRange(maxItems, list.length);
        return list;
      case 'object':
        final props = schema['properties'] is Map ? (schema['properties'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
        final out = <String, dynamic>{if (value is Map) ...value.cast<String, dynamic>()};
        for (final e in props.entries) {
          final child = e.value is Map ? (e.value as Map).cast<String, dynamic>() : const <String, dynamic>{};
          if (out.containsKey(e.key)) {
            out[e.key] = conform(out[e.key], child, depth: depth + 1);
          }
        }
        final required = schema['required'];
        if (required is List) {
          for (final name in required.whereType<String>()) {
            if (!out.containsKey(name)) {
              final child = props[name] is Map ? (props[name] as Map).cast<String, dynamic>() : const <String, dynamic>{};
              out[name] = conform(null, child, depth: depth + 1);
            }
          }
        }
        return out;
      default:
        return value;
    }
  }

  static String? _typeOf(Map<String, dynamic> schema) {
    final type = schema['type'];
    if (type is String) return type;
    if (type is List) return type.whereType<String>().where((t) => t != 'null').firstOrNull;
    if (schema['properties'] is Map) return 'object';
    if (schema['items'] is Map) return 'array';
    return null;
  }

  static num? _num(Object? v) => v is num ? v : null;

  static String _stringFor(Map<String, dynamic> schema) => switch (schema['format']) {
        'date' => '2024-01-01',
        'date-time' => '2024-01-01T00:00:00Z',
        'email' => 'user@example.com',
        'uuid' => '00000000-0000-0000-0000-000000000000',
        'uri' || 'url' => 'https://example.com',
        _ => 'string',
      };
}
