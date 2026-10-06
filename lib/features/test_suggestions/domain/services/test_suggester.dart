import 'dart:convert';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../response_tools/domain/services/json_schema_tools.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';
import '../../../scripting/domain/evaluator/json_path_resolver.dart';
import '../../../scripting/domain/evaluator/response_reader.dart';
import '../entities/test_suggestion.dart';
import 'body_shape.dart';
import 'enum_rules.dart';
import 'field_path.dart';
import 'parsed_response.dart';
import 'response_time_bound.dart';
import 'stability_probe.dart';
import 'value_formats.dart';
import 'volatility.dart';

/// Proposes the checks a developer would otherwise write one by one, from a real response (and, after the
/// stability probe, from two of them). Deterministic: no network, no model.
///
/// What is proposed, and the rule behind each:
///  * status and `Content-Type`: exactly as seen.
///  * response time: three times what was measured, rounded up, never under 500 ms.
///  * the body's JSON Schema, inferred with [JsonSchemaTools.infer]; from two responses a field missing from one
///    is optional.
///  * required fields, non-empty arrays and the shape of their elements.
///  * small value sets (a field that repeats a few values), and ids, UUIDs, emails, URLs and dates as pattern checks.
///  * exact values, only for scalars outside arrays that do not look like ids, timestamps, tokens or counters and,
///    when a second response exists, did not change between the two.
///
/// Only the status, the content type and the whole-body schema are ticked to start with: they hold on any healthy
/// answer. Everything else is the person's call.
final class TestSuggester {
  const TestSuggester();

  static const maxFieldRows = 20;
  static const maxArrayRows = 8;
  static const maxEnumRows = 8;
  static const maxFormatRows = 12;
  static const maxExactRows = 15;

  /// A schema longer than this (as compact JSON) is cut to fewer levels: a huge assertion is unreadable in the editor.
  static const maxSchemaChars = 32768;

  SuggestionResult suggest(ApiResponseEntity response, {ApiResponseEntity? probe}) {
    final first = ParsedResponse.of(response);
    var second = probe == null ? null : ParsedResponse.of(probe);
    final notes = <String>[];
    if (second != null && second.status ~/ 100 != first.status ~/ 100) {
      notes.add('The second response answered ${second.status}, not ${first.status}, so it was not used to find changing values.');
      second = null;
    }

    StabilityReport? stability;
    if (second != null && first.isJson) {
      if (second.isJson) {
        stability = StabilityProbe.compare(first.json, second.json);
      } else {
        notes.add('The second response body was not JSON, so its values could not be compared.');
        stability = StabilityReport.notComparable;
      }
    }

    final rows = <TestSuggestion>[];
    final contentType = first.header('content-type')?.trim();
    final contentTypeChanged = second != null && (second.header('content-type')?.trim() ?? '') != (contentType ?? '');
    _basics(first, second, contentType, contentTypeChanged, rows);
    if (contentTypeChanged) notes.add('Content-Type was different in the second response, so it is not suggested.');

    final volatile = <VolatileField>[];
    if (first.isJson) {
      _body(first, second, stability, rows, notes, volatile);
    } else if (response.truncated) {
      notes.add('The body was cut off at the response size limit, so no checks on its contents are suggested.');
    } else if (first.isEmpty) {
      notes.add('The body is empty, so only the status, content type and timing are suggested.');
    } else {
      notes.add('The body is not JSON, so only the status, content type and timing are suggested.');
    }

    // Grouped in the order of [SuggestionGroup]; within a group the order they were found in (List.sort is not stable).
    final ordered = [
      for (final group in SuggestionGroup.values) ...rows.where((r) => r.group == group),
    ];
    return SuggestionResult(suggestions: ordered, notes: notes, volatile: volatile, probed: second != null);
  }

  // --- status, headers, time -----------------------------------------------------

  void _basics(ParsedResponse first, ParsedResponse? second, String? contentType, bool contentTypeChanged, List<TestSuggestion> rows) {
    final ok = first.response.isSuccess;
    rows.add(TestSuggestion(
      id: 'status',
      group: SuggestionGroup.basics,
      label: 'status is ${first.status}',
      detail: ok ? null : 'This is an error answer: add it only to test the error case.',
      confidence: ok ? SuggestionConfidence.high : SuggestionConfidence.medium,
      assertion: AssertionEntity(type: AssertionType.statusEquals, expected: '${first.status}'),
      recommended: true,
    ));
    if (contentType != null && contentType.isNotEmpty && !contentTypeChanged) {
      rows.add(TestSuggestion(
        id: 'content-type',
        group: SuggestionGroup.basics,
        label: 'Content-Type is $contentType',
        detail: 'Compared as written, including the charset.',
        confidence: SuggestionConfidence.high,
        assertion: AssertionEntity(type: AssertionType.headerEquals, path: 'Content-Type', expected: contentType),
        recommended: true,
      ));
    }
    final measured = second == null || second.timeMs < first.timeMs ? first.timeMs : second.timeMs;
    final limit = ResponseTimeBound.forMeasured(measured);
    rows.add(TestSuggestion(
      id: 'time',
      group: SuggestionGroup.basics,
      label: 'response time is under $limit ms',
      detail: 'It took $measured ms. The limit is ${ResponseTimeBound.factor} times that and never under ${ResponseTimeBound.floorMs} ms, '
          'so a slower machine does not fail it.',
      confidence: SuggestionConfidence.medium,
      assertion: AssertionEntity(type: AssertionType.responseTimeBelowMs, expected: '$limit'),
    ));
  }

  // --- body ----------------------------------------------------------------------

  void _body(
    ParsedResponse first,
    ParsedResponse? second,
    StabilityReport? stability,
    List<TestSuggestion> rows,
    List<String> notes,
    List<VolatileField> volatile,
  ) {
    final json = first.json;
    final shape = BodyShape.of(json);
    if (shape.truncated) {
      notes.add('The body is large: only its first ${BodyShape.maxNodes} values (and ${BodyShape.maxArrayItems} items of an array) were analysed.');
    }
    final compared = stability != null && stability.comparable && second != null;
    final otherJson = compared ? second.json : null;
    final otherShape = compared ? BodyShape.of(otherJson) : null;

    _schema(json, compared ? otherJson : null, compared, shape, rows);
    _fields(shape, otherShape, stability, rows);
    _arrays(json, otherJson, shape, otherShape, compared, rows);
    _enums(shape, rows);
    _formats(shape, rows);
    _exact(shape, stability, compared, rows, volatile);
    if (stability != null && stability.comparable) _listChanging(stability, volatile);
  }

  void _schema(Object? json, Object? other, bool compared, BodyShape shape, List<TestSuggestion> rows) {
    if (json == null) return;
    final schema = _bounded(JsonSchemaTools.infer([json, if (compared) other]));
    final props = schema['properties'];
    final required = schema['required'];
    final label = switch (json) {
      List<dynamic> _ => 'body is an array whose elements have the shape seen here',
      Map<dynamic, dynamic> _ => 'body has the fields and types seen here',
      _ => 'body is ${_article(BodyShape.typeOf(json))}',
    };
    final fieldCount = props is Map ? props.length : 0;
    final requiredCount = required is List ? required.length : 0;
    final String detail;
    if (json is Map) {
      detail = compared
          ? '$requiredCount of $fieldCount top-level fields required: those present in both responses.'
          : '$requiredCount of $fieldCount top-level fields required: every one present now. Send again to learn which are optional.';
    } else {
      detail = compared ? 'Built from both responses.' : 'Built from this one response.';
    }
    rows.add(TestSuggestion(
      id: 'schema',
      group: SuggestionGroup.structure,
      label: label,
      detail: detail,
      confidence: compared ? SuggestionConfidence.high : SuggestionConfidence.medium,
      assertion: AssertionEntity(type: AssertionType.jsonSchema, expected: jsonEncode(schema)),
      recommended: true,
    ));
  }

  /// [schema] cut to fewer levels until its compact JSON is no longer than [maxSchemaChars].
  Map<String, dynamic> _bounded(Map<String, dynamic> schema) {
    var depth = 12;
    var current = schema;
    while (jsonEncode(current).length > maxSchemaChars && depth > 1) {
      depth -= 2;
      current = _limited(schema, depth);
    }
    return current;
  }

  Map<String, dynamic> _limited(Map<String, dynamic> schema, int depth) {
    final out = {...schema};
    if (depth <= 0) {
      out
        ..remove('properties')
        ..remove('items')
        ..remove('required');
      return out;
    }
    final props = schema['properties'];
    if (props is Map<String, dynamic>) {
      out['properties'] = {for (final e in props.entries) e.key: _limited(e.value as Map<String, dynamic>, depth - 1)};
    }
    final items = schema['items'];
    if (items is Map<String, dynamic>) out['items'] = _limited(items, depth - 1);
    return out;
  }

  void _fields(BodyShape shape, BodyShape? otherShape, StabilityReport? stability, List<TestSuggestion> rows) {
    var count = 0;
    for (final entry in shape.fields.entries) {
      if (count >= maxFieldRows) break;
      final path = entry.key;
      final field = entry.value;
      if (path.isEmpty || FieldPath.crossesArray(path)) continue;
      final depth = FieldPath.depth(path);
      if (depth > 3) continue;
      // exists treats a JSON null as missing, and a field the second response lacked is not one to require.
      if (field.nullable || field.optional) continue;
      if (otherShape != null && otherShape[path] == null) continue;
      if (stability != null && stability.unstablePresence.contains(path)) continue;
      // Below the top level only leaves: `data.user.id` existing already says `data.user` does.
      final container = field.types.contains('object') || field.types.contains('array');
      if (depth > 1 && container) continue;
      count++;
      rows.add(TestSuggestion(
        id: 'exists:$path',
        group: SuggestionGroup.fields,
        label: '${FieldPath.display(path)} exists',
        confidence: SuggestionConfidence.medium,
        assertion: AssertionEntity(type: AssertionType.jsonPathExists, path: path),
      ));
    }
  }

  void _arrays(Object? json, Object? other, BodyShape shape, BodyShape? otherShape, bool compared, List<TestSuggestion> rows) {
    var count = 0;
    for (final entry in shape.fields.entries) {
      if (count >= maxArrayRows) break;
      final path = entry.key;
      if (entry.value.soleType != 'array' || FieldPath.crossesArray(path) || FieldPath.depth(path) > 3) continue;
      if (!shape.hasElements(path)) continue;
      // An array that was empty in the second response is empty some of the time: not worth requiring items.
      if (otherShape != null && !otherShape.hasElements(path)) continue;
      count++;
      final shown = FieldPath.display(path);
      rows.add(TestSuggestion(
        id: 'array:$path',
        group: SuggestionGroup.arrays,
        label: '$shown is a non-empty array',
        detail: 'It has ${entry.value.seen == 1 ? '${_elements(shape, path)} items' : 'items'} now. Add it only if an empty list would be a bug.',
        confidence: SuggestionConfidence.medium,
        assertion: AssertionEntity(
          type: AssertionType.jsonSchema,
          path: path,
          expected: jsonEncode({'type': 'array', 'minItems': 1}),
        ),
      ));
      final value = JsonPathResolver.resolve(json, path);
      final samples = [value, if (compared) JsonPathResolver.resolve(other, path)];
      final items = JsonSchemaTools.infer(samples)['items'];
      if (items is Map<String, dynamic>) {
        rows.add(TestSuggestion(
          id: 'shape:$path',
          group: SuggestionGroup.arrays,
          label: '$shown ${_elementsPhrase(items)}',
          detail: 'Every element is checked, not just the first.',
          confidence: compared ? SuggestionConfidence.high : SuggestionConfidence.medium,
          assertion: AssertionEntity(
            type: AssertionType.jsonSchema,
            path: path,
            expected: jsonEncode({'type': 'array', 'items': _bounded(items)}),
          ),
        ));
      }
    }
  }

  int _elements(BodyShape shape, String path) => shape[FieldPath.element(path)]?.seen ?? 0;

  String _elementsPhrase(Map<String, dynamic> items) {
    final props = items['properties'];
    if (items['type'] == 'object' && props is Map && props.isNotEmpty) {
      final names = props.keys.take(6).join(', ');
      return 'elements have $names${props.length > 6 ? ' and ${props.length - 6} more' : ''}';
    }
    final type = items['type'];
    return type is String ? 'is an array of ${_plural(type)}' : 'elements share one shape';
  }

  void _enums(BodyShape shape, List<TestSuggestion> rows) {
    var count = 0;
    for (final entry in shape.fields.entries) {
      if (count >= maxEnumRows) break;
      final values = EnumRules.valuesOf(entry.key, entry.value);
      if (values == null) continue;
      final nullable = entry.value.nullable;
      final type = entry.value.soleType ?? 'string';
      final (path, schema) = _schemaAt(entry.key, {
        'type': nullable ? [type, 'null'] : type,
        'enum': [...values, if (nullable) null],
      });
      count++;
      rows.add(TestSuggestion(
        id: 'enum:${entry.key}',
        group: SuggestionGroup.allowedValues,
        label: '${FieldPath.display(entry.key)} is one of ${values.map(_quote).join(', ')}',
        detail: 'Seen ${entry.value.nonNull} times, always one of these ${values.length}. Add it only if the list is closed.',
        confidence: SuggestionConfidence.low,
        assertion: AssertionEntity(type: AssertionType.jsonSchema, path: path, expected: jsonEncode(schema)),
      ));
    }
  }

  void _formats(BodyShape shape, List<TestSuggestion> rows) {
    var count = 0;
    for (final entry in shape.fields.entries) {
      if (count >= maxFormatRows) break;
      final field = entry.value;
      if (field.soleType != 'string' || field.samples.isEmpty) continue;
      final strings = field.samples.whereType<String>().toList();
      final kind = ValueFormats.commonFormat(strings);
      final typeValue = field.nullable ? ['string', 'null'] : 'string';
      final confidence = field.nonNull >= 3 ? SuggestionConfidence.high : SuggestionConfidence.medium;
      Map<String, dynamic>? leaf;
      String? phrase;
      if (kind != null && kind != ValueFormat.opaqueId && kind != ValueFormat.jwt) {
        leaf = {'type': typeValue, 'format': kind.schemaFormat};
        phrase = 'is ${kind.phrase}';
      } else if (kind == ValueFormat.jwt) {
        leaf = {'type': typeValue, 'pattern': r'^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$'};
        phrase = 'is ${kind!.phrase}';
      } else if (Volatility.words(FieldPath.lastKey(entry.key)).contains('id')) {
        final pattern = ValueFormats.idPattern(strings);
        if (pattern != null) {
          leaf = {'type': typeValue, 'pattern': pattern.regex};
          phrase = pattern.phrase;
        }
      }
      if (leaf == null || phrase == null) continue;
      final (path, schema) = _schemaAt(entry.key, leaf);
      count++;
      rows.add(TestSuggestion(
        id: 'format:${entry.key}',
        group: SuggestionGroup.formats,
        label: '${FieldPath.display(entry.key)} $phrase',
        detail: field.nonNull >= 3 ? 'True of all ${field.samples.length} values checked.' : 'Seen in ${field.nonNull == 1 ? 'one value' : '${field.nonNull} values'}.',
        confidence: confidence,
        assertion: AssertionEntity(type: AssertionType.jsonSchema, path: path, expected: jsonEncode(schema)),
      ));
    }
  }

  void _exact(BodyShape shape, StabilityReport? stability, bool compared, List<TestSuggestion> rows, List<VolatileField> volatile) {
    var count = 0;
    final listed = <String>{};
    for (final entry in shape.fields.entries) {
      final path = entry.key;
      final field = entry.value;
      if (path.isEmpty || FieldPath.crossesArray(path) || FieldPath.depth(path) > 4) continue;
      if (field.seen != 1 || field.samples.length != 1 || field.soleType == null || !field.isScalar) continue;
      final value = field.samples.single;
      final why = Volatility.reasonAt(path, value);
      if (why != null) {
        if (volatile.length < 15 && listed.add(path)) volatile.add(VolatileField(FieldPath.display(path), why));
        continue;
      }
      if (compared && !stability!.isStable(path)) continue;
      if (count >= maxExactRows) continue;
      if (value is String && value.length > 80) continue;
      if (value is num && (!value.isFinite || value.abs() >= 9007199254740992)) continue;
      count++;
      rows.add(TestSuggestion(
        id: 'equals:$path',
        group: SuggestionGroup.exact,
        label: '${FieldPath.display(path)} equals ${_quote(value)}',
        detail: compared ? 'The same in both responses.' : 'Not verified: send again to see whether it changes.',
        confidence: compared ? SuggestionConfidence.medium : SuggestionConfidence.low,
        assertion: AssertionEntity(type: AssertionType.jsonPathEquals, path: path, expected: ResponseReader.stringify(value)),
      ));
    }
  }

  void _listChanging(StabilityReport stability, List<VolatileField> volatile) {
    final found = <String, VolatileField>{};
    void add(String path, String reason) {
      final label = FieldPath.display(path);
      if (found.length < 25) found.putIfAbsent(label, () => VolatileField(label, reason));
    }

    for (final path in stability.changing) {
      add(path, 'it changed between the two responses');
    }
    for (final path in stability.unstablePresence) {
      add(path, 'it was in only one of the two responses');
    }
    for (final path in stability.changingLength) {
      add(path, 'it had a different number of items');
    }
    // What the second response showed comes first and replaces a guess about the same field: it is evidence, the
    // rest is a guess from names and values.
    volatile
      ..removeWhere((v) => found.containsKey(v.label))
      ..insertAll(0, found.values);
  }

  // --- helpers -------------------------------------------------------------------

  /// An assertion that checks [leaf] for the field at [fieldPath]: its own path when no array is in the way, else
  /// the path of the outermost array with a schema that reaches the field in every element.
  (String, Map<String, dynamic>) _schemaAt(String fieldPath, Map<String, dynamic> leaf) {
    final steps = FieldPath.steps(fieldPath);
    final firstElement = steps.indexWhere((s) => s is! String);
    if (firstElement == -1) return (fieldPath, leaf);
    final prefix = FieldPath.join(steps.sublist(0, firstElement));
    Map<String, dynamic> wrap(List<Object> rest, {required bool outer}) {
      if (rest.isEmpty) return leaf;
      final head = rest.first;
      final inner = wrap(rest.sublist(1), outer: false);
      if (head is String) return {'properties': {head: inner}};
      // Only the array the check starts at is required to be one; deeper levels check what is there.
      return {if (outer) 'type': 'array', 'items': inner};
    }

    return (prefix, wrap(steps.sublist(firstElement), outer: true));
  }

  String _quote(Object? value) => value is String ? '"$value"' : ResponseReader.stringify(value);

  String _article(String type) => switch (type) {
        'integer' => 'an integer',
        'array' => 'an array',
        'object' => 'an object',
        _ => 'a $type',
      };

  String _plural(String type) => switch (type) {
        'integer' => 'integers',
        'number' => 'numbers',
        'string' => 'strings',
        'boolean' => 'booleans',
        'array' => 'arrays',
        'object' => 'objects',
        _ => '${type}s',
      };
}
