import 'mock_faker.dart';

/// One thing wrong with a request, with where it is: `$.address.city` in a body, `query.limit`, `header.x-tenant`.
final class MockViolation {
  final String field;
  final String message;
  const MockViolation(this.field, this.message);

  @override
  String toString() => '$field: $message';
}

/// Checks a request against the schemas of an OpenAPI document, as far as is cheap and useful for a mock: required
/// fields, types, `enum`, the limits (`minimum`, `maxLength`, `minItems`...) and `pattern`. It is not a validator for
/// every keyword (`oneOf` is not checked), because a mock that rejects what the real API accepts is worse than one that
/// lets something odd through.
final class MockSchemaValidator {
  final MockSchemaResolver resolver;
  const MockSchemaValidator([this.resolver = MockSchemaResolver.identity]);

  static const _maxDepth = 8;

  /// Problems with the JSON [value] against [schema]. With [partial] a missing required property is fine (PATCH).
  List<MockViolation> validate(Map<String, dynamic> schema, Object? value, {String path = r'$', bool partial = false}) {
    final problems = <MockViolation>[];
    _check(schema, value, path, partial, problems, 0);
    return problems;
  }

  /// A query, header or path value arrives as text: check it against the parameter's schema.
  List<MockViolation> validateText(Map<String, dynamic> schema, String text, String field) {
    final node = resolver.flatten(schema);
    final type = MockFaker.typeOf(node);
    final problems = <MockViolation>[];
    Object? typed = text;
    if (type == 'integer') {
      typed = int.tryParse(text);
      if (typed == null) return [MockViolation(field, 'must be an integer, got "$text"')];
    } else if (type == 'number') {
      typed = num.tryParse(text);
      if (typed == null) return [MockViolation(field, 'must be a number, got "$text"')];
    } else if (type == 'boolean') {
      if (text != 'true' && text != 'false') return [MockViolation(field, 'must be true or false, got "$text"')];
      typed = text == 'true';
    } else if (type == 'array') {
      // `?tag=a&tag=b` or `?tag=a,b`: each element against the item schema.
      final items = node['items'];
      if (items is Map) {
        for (final part in text.split(',')) {
          problems.addAll(validateText(items.cast<String, dynamic>(), part.trim(), field));
        }
      }
      return problems;
    }
    _check(node, typed, field, false, problems, 0);
    return problems;
  }

  void _check(Map<String, dynamic> schema, Object? value, String path, bool partial, List<MockViolation> out, int depth) {
    if (depth > _maxDepth || out.length >= 20) return;
    final node = resolver.flatten(schema);
    if (value == null) {
      if (!MockFaker.isNullable(node) && MockFaker.typeOf(node) != null && depth > 0 && !partial) {
        out.add(MockViolation(path, 'must not be null'));
      }
      return;
    }
    final enumValues = node['enum'];
    if (enumValues is List && enumValues.isNotEmpty && !enumValues.any((e) => '$e' == '$value')) {
      out.add(MockViolation(path, 'must be one of ${enumValues.join(', ')}'));
      return;
    }
    switch (MockFaker.typeOf(node)) {
      case 'object':
        if (value is! Map) {
          out.add(MockViolation(path, 'must be an object'));
          return;
        }
        final required = node['required'] is List ? (node['required'] as List).map((e) => '$e').toList() : const <String>[];
        final properties = node['properties'] is Map ? (node['properties'] as Map) : const {};
        if (!partial) {
          for (final name in required) {
            final property = properties[name];
            final flat = property is Map ? resolver.flatten(property.cast<String, dynamic>()) : const <String, dynamic>{};
            // The server assigns a read-only property: a client is not asked to send it.
            if (flat['readOnly'] == true) continue;
            if (!value.containsKey(name)) out.add(MockViolation('$path.$name', 'is required'));
          }
        }
        for (final entry in value.entries) {
          final property = properties['${entry.key}'];
          if (property is Map) {
            _check(property.cast<String, dynamic>(), entry.value, '$path.${entry.key}', partial, out, depth + 1);
          } else if (node['additionalProperties'] == false) {
            out.add(MockViolation('$path.${entry.key}', 'is not allowed'));
          }
        }
      case 'array':
        if (value is! List) {
          out.add(MockViolation(path, 'must be an array'));
          return;
        }
        final minItems = (node['minItems'] as num?)?.toInt();
        final maxItems = (node['maxItems'] as num?)?.toInt();
        if (minItems != null && value.length < minItems) out.add(MockViolation(path, 'must have at least $minItems items'));
        if (maxItems != null && value.length > maxItems) out.add(MockViolation(path, 'must have at most $maxItems items'));
        final items = node['items'];
        if (items is Map) {
          for (var i = 0; i < value.length && i < 50; i++) {
            _check(items.cast<String, dynamic>(), value[i], '$path[$i]', partial, out, depth + 1);
          }
        }
      case 'string':
        if (value is! String) {
          out.add(MockViolation(path, 'must be a string'));
          return;
        }
        final minLength = (node['minLength'] as num?)?.toInt();
        final maxLength = (node['maxLength'] as num?)?.toInt();
        if (minLength != null && value.length < minLength) out.add(MockViolation(path, 'must be at least $minLength characters'));
        if (maxLength != null && value.length > maxLength) out.add(MockViolation(path, 'must be at most $maxLength characters'));
        final pattern = node['pattern'];
        if (pattern is String) {
          try {
            if (!RegExp(pattern).hasMatch(value)) out.add(MockViolation(path, 'must match $pattern'));
          } catch (_) {
            // A pattern Dart cannot read is not held against the caller.
          }
        }
      case 'integer':
        if (value is! num || value != value.truncate()) {
          out.add(MockViolation(path, 'must be an integer'));
          return;
        }
        _range(node, value, path, out);
      case 'number':
        if (value is! num) {
          out.add(MockViolation(path, 'must be a number'));
          return;
        }
        _range(node, value, path, out);
      case 'boolean':
        if (value is! bool) out.add(MockViolation(path, 'must be true or false'));
    }
  }

  void _range(Map<String, dynamic> node, num value, String path, List<MockViolation> out) {
    final minimum = node['minimum'];
    final maximum = node['maximum'];
    final exclusiveMin = node['exclusiveMinimum'];
    final exclusiveMax = node['exclusiveMaximum'];
    if (minimum is num && value < minimum) out.add(MockViolation(path, 'must be at least $minimum'));
    if (maximum is num && value > maximum) out.add(MockViolation(path, 'must be at most $maximum'));
    if (exclusiveMin is num && value <= exclusiveMin) out.add(MockViolation(path, 'must be greater than $exclusiveMin'));
    if (exclusiveMax is num && value >= exclusiveMax) out.add(MockViolation(path, 'must be less than $exclusiveMax'));
  }
}
