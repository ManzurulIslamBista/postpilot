import 'dart:convert';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../import_export/domain/services/openapi_parser.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/entities/request_body.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';
import 'generated_case.dart';
import 'openapi_schemas.dart';

/// Turns an OpenAPI 3 / Swagger 2 document into requests with assertions that test the API against its own
/// description. One operation gives:
///
///  * CONTRACT: a valid request built from the schema's examples and defaults, expecting the documented success
///    status (`is 2xx` when the document names several, or none), a content type and the response's JSON Schema;
///  * NEGATIVE: each required body field and required query or header parameter left out in turn, each property
///    given a value of the wrong type, no body at all, and broken JSON, expecting a client error (`4xx`, never an
///    exact code the document does not promise) and the error response's schema when the document has one;
///  * BOUNDARY: a value just past each minimum, maximum, length, enum and item limit, and a whole number too big
///    for its type, expecting a client error;
///  * AUTH, for an operation that needs credentials: none, and malformed ones, expecting the documented 401 or 403
///    (both, when the document names neither).
///
/// The requests, their examples and their credentials come from the importer ([OpenApiParser]); the document is
/// read through the importer's own reference handling ([OpenApiParser.view]). Pure Dart.
abstract final class OpenApiTestGenerator {
  static GeneratedSuite generate(String specText) {
    final parsed = OpenApiParser.parse(specText);
    final run = _Run(parsed, OpenApiParser.view(specText))..collect();
    return GeneratedSuite(name: parsed.name, baseUrl: parsed.baseUrl, cases: run.cases, notes: run.notes);
  }
}

/// The most cases of each kind one operation gives, so a very large operation does not drown the rest.
const _maxMissing = 25;
const _maxWrongType = 10;
const _maxBoundary = 30;
const _longestStringTested = 10000;
const _mostItemsTested = 100;

final _pathParam = RegExp(r'\{([^{}/]+)\}');
final _nonWord = RegExp(r'\W');
const _overflowMarker = '@@overflow@@';

/// One more than the largest 64-bit integer.
const _int64Overflow = '9223372036854775808';
const _ignoredHeaders = {'accept', 'content-type', 'authorization'};

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
List<dynamic> _list(Object? v) => v is List ? v : const [];

final class _Run {
  final ParsedOpenApiDocument parsed;
  final OpenApiDocumentView view;
  final OpenApiSchemas schemas;
  final List<GeneratedCase> cases = [];
  final List<String> notes = [];

  _Run(this.parsed, this.view) : schemas = OpenApiSchemas(view);

  void collect() {
    final items = <String, OpenApiRequestItem>{
      for (final item in [...parsed.rootRequests, for (final f in parsed.folders) ...f.requests]) '${item.method.name} ${item.url}': item,
    };
    for (final entry in _map(view.root['paths']).entries) {
      if (entry.key.startsWith('x-')) continue;
      final pathItem = view.resolve(_map(entry.value));
      final pathParams = _list(pathItem['parameters']);
      for (final method in HttpMethod.values) {
        final operation = pathItem[method.name];
        if (operation is! Map) continue;
        final url = '{{${OpenApiParser.baseUrlVariable}}}${entry.key.replaceAllMapped(_pathParam, (m) => '{{${m[1]!.replaceAll(_nonWord, '_')}}}')}';
        final item = items['${method.name} $url'];
        if (item == null) {
          notes.add('${method.label} ${entry.key} was skipped: the importer could not read it.');
          continue;
        }
        cases.addAll(_Operation(this, entry.key, method, _map(operation), pathParams, item).build());
      }
    }
  }
}

/// One path parameter, query parameter or header parameter with its schema.
final class _Param {
  final String name;
  final String location;
  final bool required;
  final Map<String, dynamic> schema;
  const _Param(this.name, this.location, this.required, this.schema);
}

/// What an operation documents for one response code.
final class _Doc {
  final String code;
  final bool hasContent;

  /// The self-contained JSON Schema of its JSON body, when it has one.
  final Map<String, dynamic>? schema;
  const _Doc(this.code, this.hasContent, this.schema);
}

final class _Operation {
  final _Run run;
  final String path;
  final HttpMethod method;
  final Map<String, dynamic> op;
  final List<dynamic> pathParams;
  final OpenApiRequestItem item;

  late final String label = '${method.label} $path';
  late final bool changesData = method == HttpMethod.post || method == HttpMethod.put || method == HttpMethod.patch || method == HttpMethod.delete;

  final List<_Param> params = [];
  Map<String, dynamic>? bodySchema;
  bool jsonBody = false;
  bool bodyRequired = false;

  /// The valid JSON body, decoded; null when the operation takes none (or not JSON).
  Object? validBody;
  final Map<String, _Doc> docs = {};

  late List<KeyValueItem> _query;
  late List<KeyValueItem> _headers;

  _Operation(this.run, this.path, this.method, this.op, this.pathParams, this.item) {
    _readParameters();
    _readBody();
    _readResponses();
    _query = [
      for (final q in item.queryParams)
        q.enabled && q.value.trim().isEmpty ? q.copyWith(value: _paramText(q.key, 'query')) : q,
    ];
    _headers = [
      for (final h in item.headers)
        h.enabled && h.value.trim().isEmpty && h.key.toLowerCase() != 'content-type' ? h.copyWith(value: _paramText(h.key, 'header')) : h,
    ];
  }

  // --- reading the operation ---------------------------------------------------------

  void _readParameters() {
    final merged = <String, Map<String, dynamic>>{};
    for (final raw in [...pathParams, ..._list(op['parameters'])]) {
      final p = run.view.resolve(_map(raw));
      if (p.isNotEmpty) merged['${p['in']}:${p['name']}'] = p;
    }
    for (final p in merged.values) {
      final location = p['in'];
      final name = p['name'];
      if (name is! String || (location != 'query' && location != 'path' && location != 'header')) continue;
      if (location == 'header' && _ignoredHeaders.contains(name.toLowerCase())) continue;
      final declared = _map(p['schema']);
      final raw = declared.isNotEmpty ? declared : _swaggerSchema(p);
      params.add(_Param(name, location as String, p['required'] == true || location == 'path', run.schemas.inline(raw, forRequest: true)));
    }
  }

  /// A Swagger 2 parameter keeps its schema keywords on the parameter itself.
  Map<String, dynamic> _swaggerSchema(Map<String, dynamic> p) => {
        for (final key in const ['type', 'format', 'enum', 'minimum', 'maximum', 'exclusiveMinimum', 'exclusiveMaximum', 'minLength', 'maxLength', 'pattern', 'minItems', 'maxItems', 'items'])
          if (p.containsKey(key)) key: p[key],
      };

  void _readBody() {
    Map<String, dynamic> schema = const {};
    if (run.view.isSwagger2) {
      final bodyParams = [
        for (final raw in [...pathParams, ..._list(op['parameters'])])
          if (run.view.resolve(_map(raw))['in'] == 'body') run.view.resolve(_map(raw)),
      ];
      if (bodyParams.isNotEmpty) {
        final declared = op['consumes'] is List ? op['consumes'] as List : _list(run.view.root['consumes']);
        jsonBody = declared.isEmpty || declared.any((c) => '$c'.contains('json'));
        schema = _map(bodyParams.last['schema']);
        bodyRequired = bodyParams.last['required'] == true;
      }
    } else {
      final requestBody = run.view.resolve(_map(op['requestBody']));
      final content = _map(requestBody['content']);
      final mediaType = content.keys.where((k) => k.contains('json')).firstOrNull;
      if (mediaType != null) {
        jsonBody = true;
        schema = _map(_map(content[mediaType])['schema']);
        bodyRequired = requestBody['required'] == true;
      }
    }
    if (schema.isNotEmpty) bodySchema = run.schemas.inline(schema, forRequest: true);
    if (!jsonBody || item.body.type != BodyType.raw || item.body.rawContentType != RawContentType.json) {
      jsonBody = false;
      return;
    }
    Object? decoded;
    try {
      decoded = item.body.rawText.trim().isEmpty ? null : jsonDecode(item.body.rawText);
    } on FormatException {
      decoded = null;
    }
    final fitted = bodySchema == null ? decoded : run.schemas.conform(decoded, bodySchema!);
    final properties = _map(bodySchema?['properties']);
    // The importer's example holds every property, a read-only one too; a client does not send those.
    validBody = fitted is Map && properties.isNotEmpty ? {for (final e in fitted.entries) if (properties.containsKey(e.key)) e.key: e.value} : fitted;
  }

  void _readResponses() {
    final responses = _map(op['responses']);
    final produced = op['produces'] is List ? op['produces'] as List : _list(run.view.root['produces']);
    final producesJson = produced.isEmpty || produced.any((p) => '$p'.contains('json'));
    for (final e in responses.entries) {
      final response = run.view.resolve(_map(e.value));
      Map<String, dynamic> schema = const {};
      var hasContent = false;
      if (run.view.isSwagger2) {
        schema = producesJson ? _map(response['schema']) : const {};
        hasContent = response['schema'] is Map;
      } else {
        final content = _map(response['content']);
        hasContent = content.isNotEmpty;
        final mediaType = content.keys.where((k) => k.contains('json')).firstOrNull;
        if (mediaType != null) schema = _map(_map(content[mediaType])['schema']);
      }
      docs[e.key.toUpperCase()] = _Doc(e.key, hasContent, schema.isEmpty ? null : run.schemas.inline(schema, forRequest: false));
    }
  }

  // --- the valid request ---------------------------------------------------------------

  String _paramText(String name, String location) {
    final param = params.where((p) => p.name == name && p.location == location).firstOrNull;
    final value = param == null ? null : run.schemas.valueFor(param.schema);
    return _text(value is List ? value.firstOrNull : value);
  }

  String _text(Object? v) => v == null ? '' : (v is String ? v : (v is num || v is bool ? '$v' : jsonEncode(v)));

  /// [value] as the raw JSON body. The overflow marker is a string in the tree and a bare number in the text: no
  /// Dart integer is as big as the one it stands for.
  RequestBody _bodyOf(Object? value, {String? raw}) => item.body.copyWith(
        type: BodyType.raw,
        rawContentType: RawContentType.json,
        rawText: raw ?? const JsonEncoder.withIndent('  ').convert(value).replaceAll('"$_overflowMarker"', _int64Overflow),
      );

  GeneratedCase _make(
    TestCategory category,
    String suffix, {
    required List<AssertionEntity> assertions,
    String? url,
    List<KeyValueItem>? query,
    List<KeyValueItem>? headers,
    RequestBody? body,
    RequestAuth? auth,
  }) =>
      GeneratedCase(
        category: category,
        operation: label,
        name: '$label ($suffix)',
        method: method,
        url: url ?? item.url,
        headers: headers ?? _headers,
        queryParams: query ?? _query,
        body: body ?? (validBody == null ? item.body : _bodyOf(validBody)),
        auth: auth ?? item.auth,
        assertions: assertions,
        changesData: changesData,
      );

  List<GeneratedCase> build() => [..._contract(), ..._negative(), ..._boundary(), ..._auth()];

  // --- expectations --------------------------------------------------------------------

  /// A client error, and the error schema of the first of [codes] the document gives one for.
  List<AssertionEntity> _clientError(List<String> codes) => [
        AssertionEntity(type: AssertionType.statusEquals, expected: '4xx'),
        ..._schemaOf(codes),
      ];

  List<AssertionEntity> _schemaOf(List<String> codes) {
    for (final code in codes) {
      final schema = docs[code]?.schema;
      if (schema != null) return [AssertionEntity(type: AssertionType.jsonSchema, expected: jsonEncode(schema))];
    }
    return const [];
  }

  static const _badRequestCodes = ['400', '422', '4XX', 'DEFAULT'];
  static const _authCodes = ['401', '403', '4XX', 'DEFAULT'];

  // --- contract ------------------------------------------------------------------------

  List<GeneratedCase> _contract() {
    final success = [for (final e in docs.entries) if (RegExp(r'^2\d\d$').hasMatch(e.key) || e.key == '2XX') e.value];
    final exact = [for (final d in success) if (RegExp(r'^2\d\d$').hasMatch(d.code)) d.code];
    final range = success.any((d) => d.code.toUpperCase() == '2XX');
    final assertions = <AssertionEntity>[
      if (exact.length == 1 && !range)
        AssertionEntity(type: AssertionType.statusEquals, expected: exact.single)
      else
        AssertionEntity(type: AssertionType.statusIn2xx),
    ];
    if (success.any((d) => d.hasContent)) {
      assertions.add(AssertionEntity(type: AssertionType.headerExists, path: 'Content-Type'));
    }
    // One schema to check against: with several success responses that differ, no schema is a safer claim than a wrong one.
    final schemas = {for (final d in success) if (d.schema != null) jsonEncode(d.schema)};
    if (schemas.length == 1) assertions.add(AssertionEntity(type: AssertionType.jsonSchema, expected: schemas.single));
    return [_make(TestCategory.contract, 'contract', assertions: assertions)];
  }

  // --- negative ------------------------------------------------------------------------

  List<GeneratedCase> _negative() {
    final out = <GeneratedCase>[];
    final rejected = _clientError(_badRequestCodes);
    final body = validBody;
    final schema = bodySchema;

    // A required field of the body left out, one at a time.
    if (body is Map && schema != null) {
      for (final fieldPath in _requiredPaths(schema, body, 0).take(_maxMissing)) {
        out.add(_make(TestCategory.negative, 'missing ${fieldPath.join('.')}', assertions: rejected, body: _bodyOf(_without(body, fieldPath))));
      }
    }
    // A required query or header parameter left out.
    for (final p in params.where((p) => p.required && p.location == 'query')) {
      out.add(_make(TestCategory.negative, 'missing query ${p.name}', assertions: rejected, query: [for (final q in _query) if (q.key != p.name) q]));
    }
    for (final p in params.where((p) => p.required && p.location == 'header')) {
      out.add(_make(TestCategory.negative, 'missing header ${p.name}', assertions: rejected, headers: [for (final h in _headers) if (h.key != p.name) h]));
    }
    // A value of the wrong type for each property.
    if (body is Map && schema != null) {
      var count = 0;
      for (final e in _map(schema['properties']).entries) {
        if (count >= _maxWrongType) break;
        if (!body.containsKey(e.key)) continue;
        final wrong = _wrongValue(_typeOf(_map(e.value)));
        if (wrong == null) continue;
        count++;
        out.add(_make(TestCategory.negative, 'wrong type ${e.key}', assertions: rejected, body: _bodyOf({...body, e.key: wrong})));
      }
    }
    // A wrong kind of value for a parameter that is a number or a boolean.
    for (final p in params.where((p) => p.location == 'path')) {
      final wrong = _wrongValue(_typeOf(p.schema));
      if (wrong is String) out.add(_make(TestCategory.negative, 'wrong type path ${p.name}', assertions: rejected, url: _withPathValue(p.name, wrong)));
    }
    for (final p in params.where((p) => p.location == 'query')) {
      final wrong = _wrongValue(_typeOf(p.schema));
      if (wrong is String) out.add(_make(TestCategory.negative, 'wrong type query ${p.name}', assertions: rejected, query: _withRow(_query, p.name, wrong)));
    }
    // No body at all, and a body that is not JSON.
    if (jsonBody && (bodyRequired || _requiredNames(schema).isNotEmpty)) {
      out.add(_make(TestCategory.negative, 'empty body', assertions: rejected, body: item.body.copyWith(type: BodyType.raw, rawContentType: RawContentType.json, rawText: '')));
    }
    if (jsonBody) {
      out.add(_make(TestCategory.negative, 'malformed JSON', assertions: rejected, body: _bodyOf(null, raw: '{"broken": ')));
    }
    return out;
  }

  Iterable<List<String>> _requiredPaths(Map<String, dynamic> schema, Object? value, int depth) sync* {
    final required = _requiredNames(schema);
    final props = _map(schema['properties']);
    for (final e in props.entries) {
      if (!required.contains(e.key) || value is! Map || !value.containsKey(e.key)) continue;
      yield [e.key];
      final child = _map(e.value);
      if (depth < 1 && _typeOf(child) == 'object') {
        for (final sub in _requiredPaths(child, value[e.key], depth + 1)) {
          yield [e.key, ...sub];
        }
      }
    }
    for (final name in required) {
      if (!props.containsKey(name) && value is Map && value.containsKey(name)) yield [name];
    }
  }

  List<String> _requiredNames(Map<String, dynamic>? schema) => _list(schema?['required']).whereType<String>().toList();

  Object? _without(Map<dynamic, dynamic> body, List<String> fieldPath) {
    final copy = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
    var node = copy;
    for (var i = 0; i < fieldPath.length - 1; i++) {
      final next = node[fieldPath[i]];
      if (next is! Map<String, dynamic>) return copy;
      node = next;
    }
    node.remove(fieldPath.last);
    return copy;
  }

  Object? _wrongValue(String? type) => switch (type) {
        'string' => 12345,
        'integer' || 'number' => 'not-a-number',
        'boolean' => 'not-a-boolean',
        'array' => 'not-an-array',
        'object' => 'not-an-object',
        _ => null,
      };

  String _withPathValue(String name, String value) => item.url.replaceAll('{{${name.replaceAll(_nonWord, '_')}}}', Uri.encodeComponent(value));

  List<KeyValueItem> _withRow(List<KeyValueItem> rows, String key, String value) {
    final found = rows.any((r) => r.key == key);
    return [
      for (final r in rows)
        if (r.key == key) r.copyWith(value: value, enabled: true) else r,
      if (!found) KeyValueItem(key: key, value: value),
    ];
  }

  // --- boundary ------------------------------------------------------------------------

  List<GeneratedCase> _boundary() {
    final out = <GeneratedCase>[];
    final rejected = _clientError(_badRequestCodes);
    final body = validBody;
    final schema = bodySchema;

    if (body is Map && schema != null) {
      for (final e in _map(schema['properties']).entries) {
        if (out.length >= _maxBoundary) break;
        if (!body.containsKey(e.key)) continue;
        for (final (suffix, value) in _violations(_map(e.value), '${e.key}')) {
          if (out.length >= _maxBoundary) break;
          out.add(_make(TestCategory.boundary, '${e.key} $suffix', assertions: rejected, body: _bodyOf({...body, e.key: value})));
        }
      }
    }
    for (final p in params) {
      for (final (suffix, value) in _violations(p.schema, p.name)) {
        if (out.length >= _maxBoundary) break;
        final text = value == _overflowMarker ? _int64Overflow : _text(value);
        final name = '${p.location} ${p.name} $suffix';
        out.add(switch (p.location) {
          'path' => _make(TestCategory.boundary, name, assertions: rejected, url: _withPathValue(p.name, text)),
          'query' => _make(TestCategory.boundary, name, assertions: rejected, query: _withRow(_query, p.name, text)),
          _ => _make(TestCategory.boundary, name, assertions: rejected, headers: _withRow(_headers, p.name, text)),
        });
      }
    }
    return out;
  }

  /// The values just past what [schema] allows, each with how to say it in a case name, in a fixed order.
  List<(String, Object?)> _violations(Map<String, dynamic> schema, String field) {
    final out = <(String, Object?)>[];
    final type = _typeOf(schema);
    final min = _num(schema['minimum']);
    final max = _num(schema['maximum']);
    final isNumber = type == 'integer' || type == 'number';
    if (isNumber && min != null) out.add(('below minimum', schema['exclusiveMinimum'] == true ? min : min - 1));
    if (isNumber && max != null) out.add(('above maximum', schema['exclusiveMaximum'] == true ? max : max + 1));
    final minLength = schema['minLength'];
    final maxLength = schema['maxLength'];
    if (type == 'string' && minLength is int && minLength >= 1) out.add(('too short', 'a' * (minLength - 1)));
    if (type == 'string' && maxLength is int) {
      if (maxLength <= _longestStringTested) {
        out.add(('too long', 'a' * (maxLength + 1)));
      } else {
        run.notes.add('$label: $field allows $maxLength characters, too many to build a test value for.');
      }
    }
    final enumValues = schema['enum'];
    if (enumValues is List && enumValues.isNotEmpty) out.add(('not in enum', _notIn(enumValues)));
    final items = _map(schema['items']);
    final minItems = schema['minItems'];
    final maxItems = schema['maxItems'];
    if (type == 'array' && minItems is int && minItems >= 1) {
      out.add(('too few items', [for (var i = 0; i < minItems - 1; i++) run.schemas.valueFor(items)]));
    }
    if (type == 'array' && maxItems is int && maxItems <= _mostItemsTested) {
      out.add(('too many items', [for (var i = 0; i <= maxItems; i++) run.schemas.valueFor(items)]));
    }
    if (type == 'integer' && max == null) {
      // A whole number past the largest the declared format holds; the app writes it as a bare number.
      out.add(('overflow', schema['format'] == 'int32' ? 2147483648 : _overflowMarker));
    }
    return out;
  }

  Object _notIn(List<dynamic> values) {
    final numbers = values.whereType<num>().toList();
    if (numbers.length == values.length) return numbers.reduce((a, b) => a > b ? a : b) + 1;
    var candidate = 'not-a-valid-value';
    while (values.contains(candidate)) {
      candidate += '!';
    }
    return candidate;
  }

  // --- auth ----------------------------------------------------------------------------

  List<GeneratedCase> _auth() {
    final security = op.containsKey('security') ? op['security'] : run.view.root['security'];
    final needsAuth = security is List && security.isNotEmpty && security.every((r) => r is Map && r.isNotEmpty);
    if (!needsAuth) return const [];
    final malformed = _malformedAuth(item.auth);
    if (item.auth.type == AuthType.none || item.auth.type == AuthType.inherit || malformed == null) {
      run.notes.add('$label needs credentials, but its security scheme has no credentials the app can build, so no auth cases were made.');
      return const [];
    }
    final documented = [for (final code in const ['401', '403']) if (docs.containsKey(code)) code];
    final expected = (documented.isEmpty ? const ['401', '403'] : documented).join(', ');
    final assertions = [AssertionEntity(type: AssertionType.statusEquals, expected: expected), ..._schemaOf(_authCodes)];
    final basic = item.auth.type == AuthType.basic || item.auth.type == AuthType.digest;
    return [
      _make(TestCategory.auth, 'no credentials', assertions: assertions, auth: RequestAuth.none),
      _make(TestCategory.auth, basic ? 'wrong credentials' : 'malformed token', assertions: assertions, auth: malformed),
    ];
  }

  RequestAuth? _malformedAuth(RequestAuth auth) => switch (auth.type) {
        AuthType.bearer || AuthType.oauth2 || AuthType.jwtBearer => const RequestAuth(type: AuthType.bearer, bearerToken: 'malformed.token'),
        AuthType.basic || AuthType.digest => const RequestAuth(type: AuthType.basic, basicUsername: 'invalid', basicPassword: 'invalid'),
        AuthType.apiKey => auth.copyWith(apiKeyValue: 'invalid'),
        _ => null,
      };

  // --- schema helpers ------------------------------------------------------------------

  static String? _typeOf(Map<String, dynamic> schema) {
    final type = schema['type'];
    if (type is String) return type;
    if (type is List) return type.whereType<String>().where((t) => t != 'null').firstOrNull;
    if (schema['properties'] is Map) return 'object';
    if (schema['items'] is Map) return 'array';
    return null;
  }

  static num? _num(Object? v) => v is num ? v : null;
}
