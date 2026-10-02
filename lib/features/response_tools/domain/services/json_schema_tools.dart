import 'dart:convert';

/// One place where a value does not fit a schema.
final class SchemaViolation {
  /// JSON path of the offending value; `$` is the whole document.
  final String path;
  final String message;
  const SchemaViolation(this.path, this.message);

  @override
  String toString() => '$path: $message';
}

/// Works out a JSON Schema from example responses, and checks a response
/// against one. The validator covers what OpenAPI response schemas actually
/// use (types, nullable, required, properties, items, enum, ranges, lengths,
/// pattern, formats, allOf/anyOf/oneOf, local `$ref`), not the whole standard.
abstract final class JsonSchemaTools {
  // --- inference ---------------------------------------------------------------

  /// A schema every sample satisfies. Fields missing from some samples are
  /// left out of `required`, and a type seen with null becomes a type list.
  static Map<String, dynamic> infer(List<Object?> samples) {
    Map<String, dynamic>? merged;
    for (final sample in samples) {
      final s = _schemaOf(sample);
      merged = merged == null ? s : _merge(merged, s);
    }
    return _finish(merged ?? <String, dynamic>{});
  }

  static final _dateTime = RegExp(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?$');
  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static Map<String, dynamic> _schemaOf(Object? v) {
    switch (v) {
      case null:
        return {'_types': <String>{'null'}};
      case bool _:
        return {'_types': <String>{'boolean'}};
      case int _:
        return {'_types': <String>{'integer'}};
      case double _:
        return {'_types': <String>{'number'}};
      case String s:
        return {
          '_types': <String>{'string'},
          if (_dateTime.hasMatch(s)) 'format': 'date-time' else if (_date.hasMatch(s)) 'format': 'date',
        };
      case List<dynamic> l:
        Map<String, dynamic>? items;
        for (final e in l) {
          final s = _schemaOf(e);
          items = items == null ? s : _merge(items, s);
        }
        return {'_types': <String>{'array'}, 'items': ?items};
      case Map<dynamic, dynamic> m:
        return {
          '_types': <String>{'object'},
          'properties': {for (final e in m.entries) '${e.key}': _schemaOf(e.value)},
          '_required': <String>{for (final k in m.keys) '$k'},
        };
      default:
        return {'_types': <String>{}};
    }
  }

  static Map<String, dynamic> _merge(Map<String, dynamic> a, Map<String, dynamic> b) {
    final types = {...(a['_types'] as Set<String>), ...(b['_types'] as Set<String>)};
    if (types.contains('integer') && types.contains('number')) types.remove('integer');
    final out = <String, dynamic>{'_types': types};
    if (a['format'] != null && a['format'] == b['format']) out['format'] = a['format'];
    final ia = a['items'] as Map<String, dynamic>?;
    final ib = b['items'] as Map<String, dynamic>?;
    if (ia != null || ib != null) out['items'] = ia == null ? ib : (ib == null ? ia : _merge(ia, ib));
    final pa = a['properties'] as Map<String, dynamic>?;
    final pb = b['properties'] as Map<String, dynamic>?;
    if (pa != null || pb != null) {
      final props = <String, dynamic>{};
      for (final k in {...?pa?.keys, ...?pb?.keys}) {
        final x = pa?[k] as Map<String, dynamic>?;
        final y = pb?[k] as Map<String, dynamic>?;
        props[k] = x == null ? y : (y == null ? x : _merge(x, y));
      }
      out['properties'] = props;
      final ra = a['_required'] as Set<String>?;
      final rb = b['_required'] as Set<String>?;
      out['_required'] = ra == null ? rb : (rb == null ? ra : ra.intersection(rb));
    }
    return out;
  }

  static Map<String, dynamic> _finish(Map<String, dynamic> s) {
    final types = [...(s['_types'] as Set<String>? ?? <String>{})]..sort();
    final out = <String, dynamic>{};
    if (types.length == 1) {
      out['type'] = types.single;
    } else if (types.length > 1) {
      out['type'] = types;
    }
    if (s['format'] != null) out['format'] = s['format'];
    final props = s['properties'] as Map<String, dynamic>?;
    if (props != null) {
      out['properties'] = {for (final e in props.entries) e.key: _finish(e.value as Map<String, dynamic>)};
      final required = [...(s['_required'] as Set<String>? ?? <String>{})]..sort();
      if (required.isNotEmpty) out['required'] = required;
    }
    final items = s['items'] as Map<String, dynamic>?;
    if (items != null) out['items'] = _finish(items);
    return out;
  }

  static String encode(Map<String, dynamic> schema) => const JsonEncoder.withIndent('  ').convert(schema);

  // --- validation --------------------------------------------------------------

  static List<SchemaViolation> validate(Map<String, dynamic> schema, Object? value, {int limit = 100}) {
    final out = <SchemaViolation>[];
    _check(schema, schema, value, r'$', out, limit, 0);
    return out;
  }

  static void _check(
    Map<String, dynamic> root,
    Map<String, dynamic> schema,
    Object? value,
    String path,
    List<SchemaViolation> out,
    int limit,
    int depth,
  ) {
    if (out.length >= limit || depth > 40) return;
    void fail(String message) {
      if (out.length < limit) out.add(SchemaViolation(path, message));
    }

    final ref = schema[r'$ref'];
    if (ref is String) {
      final target = _resolve(root, ref);
      if (target == null) {
        fail('Cannot resolve $ref');
      } else {
        _check(root, target, value, path, out, limit, depth + 1);
      }
      return;
    }

    for (final sub in (schema['allOf'] as List?)?.whereType<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[]) {
      _check(root, sub, value, path, out, limit, depth + 1);
    }
    final anyOf = (schema['anyOf'] as List?)?.whereType<Map<String, dynamic>>().toList();
    if (anyOf != null && anyOf.isNotEmpty) {
      final matches = anyOf.where((s) => _passes(root, s, value, depth)).length;
      if (matches == 0) fail('Does not match any of the ${anyOf.length} allowed shapes');
    }
    final oneOf = (schema['oneOf'] as List?)?.whereType<Map<String, dynamic>>().toList();
    if (oneOf != null && oneOf.isNotEmpty) {
      final matches = oneOf.where((s) => _passes(root, s, value, depth)).length;
      if (matches != 1) fail(matches == 0 ? 'Does not match any allowed shape' : 'Matches $matches shapes, expected exactly one');
    }

    final nullable = schema['nullable'] == true;
    if (value == null && nullable) return;

    final type = schema['type'];
    if (type != null) {
      final types = type is List ? type.cast<String>() : [type as String];
      if (!types.any((t) => _isType(t, value))) {
        fail('Expected ${types.join(' or ')}, got ${_describe(value)}');
        return;
      }
    }

    final enumValues = schema['enum'];
    if (enumValues is List && !enumValues.any((e) => _same(e, value))) {
      fail('Must be one of ${enumValues.join(', ')}, got ${_show(value)}');
    }
    if (schema.containsKey('const') && !_same(schema['const'], value)) {
      fail('Must equal ${_show(schema['const'])}, got ${_show(value)}');
    }

    if (value is num) {
      final min = schema['minimum'];
      final max = schema['maximum'];
      if (min is num && value < min) fail('$value is below the minimum $min');
      if (max is num && value > max) fail('$value is above the maximum $max');
    }

    if (value is String) {
      final min = schema['minLength'];
      final max = schema['maxLength'];
      if (min is int && value.length < min) fail('Shorter than $min characters');
      if (max is int && value.length > max) fail('Longer than $max characters');
      final pattern = schema['pattern'];
      if (pattern is String) {
        try {
          if (!RegExp(pattern).hasMatch(value)) fail('Does not match the pattern $pattern');
        } catch (_) {}
      }
      final format = schema['format'];
      if (format is String && !_formatOk(format, value)) fail('Not a valid $format: ${_show(value)}');
    }

    if (value is List) {
      final min = schema['minItems'];
      final max = schema['maxItems'];
      if (min is int && value.length < min) fail('Fewer than $min items');
      if (max is int && value.length > max) fail('More than $max items');
      final items = schema['items'];
      if (items is Map<String, dynamic>) {
        for (var i = 0; i < value.length && out.length < limit; i++) {
          _check(root, items, value[i], '$path[$i]', out, limit, depth + 1);
        }
      }
    }

    if (value is Map) {
      final props = schema['properties'];
      for (final r in (schema['required'] as List?)?.cast<String>() ?? const <String>[]) {
        if (!value.containsKey(r)) fail('Missing required "$r"');
      }
      if (props is Map<String, dynamic>) {
        for (final e in props.entries) {
          if (value.containsKey(e.key) && e.value is Map<String, dynamic>) {
            _check(root, e.value as Map<String, dynamic>, value[e.key], '$path.${e.key}', out, limit, depth + 1);
          }
        }
        if (schema['additionalProperties'] == false) {
          for (final k in value.keys) {
            if (!props.containsKey(k)) fail('Unexpected property "$k"');
          }
        }
      }
    }
  }

  static bool _passes(Map<String, dynamic> root, Map<String, dynamic> schema, Object? value, int depth) {
    final tmp = <SchemaViolation>[];
    _check(root, schema, value, r'$', tmp, 1, depth + 1);
    return tmp.isEmpty;
  }

  static Map<String, dynamic>? _resolve(Map<String, dynamic> root, String ref) {
    if (!ref.startsWith('#/')) return null;
    Object? node = root;
    for (final part in ref.substring(2).split('/')) {
      if (node is Map<String, dynamic>) {
        node = node[part.replaceAll('~1', '/').replaceAll('~0', '~')];
      } else {
        return null;
      }
    }
    return node is Map<String, dynamic> ? node : null;
  }

  static bool _isType(String t, Object? v) => switch (t) {
        'string' => v is String,
        'integer' => v is int || (v is double && v == v.truncateToDouble()),
        'number' => v is num,
        'boolean' => v is bool,
        'array' => v is List,
        'object' => v is Map,
        'null' => v == null,
        _ => true,
      };

  static String _describe(Object? v) => switch (v) {
        null => 'null',
        bool _ => 'boolean',
        int _ => 'integer',
        num _ => 'number',
        String _ => 'string',
        List<dynamic> _ => 'array',
        Map<dynamic, dynamic> _ => 'object',
        _ => '${v.runtimeType}',
      };

  static bool _same(Object? a, Object? b) => a == b || (a is num && b is num && a == b);

  static String _show(Object? v) {
    final s = jsonEncode(v);
    return s.length > 60 ? '${s.substring(0, 60)}…' : s;
  }

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  static bool _formatOk(String format, String v) => switch (format) {
        'date-time' => _dateTime.hasMatch(v) && DateTime.tryParse(v) != null,
        'date' => _date.hasMatch(v) && DateTime.tryParse(v) != null,
        'email' => _email.hasMatch(v),
        'uuid' => _uuid.hasMatch(v),
        'uri' || 'url' => (Uri.tryParse(v)?.hasScheme ?? false),
        _ => true,
      };
}
