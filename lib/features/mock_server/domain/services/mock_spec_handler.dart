import 'mock_faker.dart';
import 'mock_handler.dart';
import 'mock_http.dart';
import 'mock_pagination.dart';
import 'mock_resources.dart';
import 'mock_schema_validator.dart';
import 'mock_spec.dart';

/// Serves an OpenAPI document with no saved example behind it.
///
/// * Answers are made up from the response schemas (an `example` or `default` first, else fake data that follows the
///   field's name, format and limits; see [MockFaker]). The same seed always gives the same data.
/// * A request is checked against the operation: a missing required query parameter, header or body field answers 400 (or
///   422, whichever the document declares) in the error shape the document describes.
/// * A resource family (`/users` and `/users/{id}`) is stateful: it starts with a few fake items; POST adds one, PUT and
///   PATCH change one, DELETE removes one, and the lists and GET-by-id show it. Lists can be paged and filtered by
///   query parameters that name a field.
/// * Every other operation answers a fake of its first 2xx response.
final class MockSpecHandler implements MockHandler {
  final MockSpec spec;
  final int seed;

  /// Items each collection starts with.
  final int seedCount;
  final MockPaginationStrategy pagination;

  /// Whether to answer 400 for a request that breaks the operation's declared parameters and body.
  final bool validateRequests;

  late final MockFaker faker = MockFaker(seed: seed, resolver: spec.resolver);
  late final MockSchemaValidator _validator = MockSchemaValidator(spec.resolver);
  late final List<MockResourceFamily> families = MockResources.detect(spec);
  late final MockStore store = MockStore(faker: faker, seedCount: seedCount);
  late final List<String> _baseSegments = spec.basePath.split('/').where((s) => s.isNotEmpty).toList();

  late final Map<SpecOperation, (MockResourceFamily, MockResourceRole)> _roles = {
    for (final family in families)
      for (final op in family.operations) op: (family, family.roleOf(op)!),
  };

  MockSpecHandler(this.spec, {this.seed = 1, this.seedCount = 10, this.pagination = MockPaginationStrategy.auto, this.validateRequests = true});

  /// Forgets every created, changed and deleted item: the collections start from their seed again.
  void resetData() => store.reset();

  @override
  late final List<MockRouteInfo> routes = [
    for (final op in spec.operations)
      MockRouteInfo(
        key: op.key,
        method: op.method,
        path: '${spec.basePath}${SpecOperation.routePath(op.segments)}',
        title: op.summary.isNotEmpty ? op.summary : (op.operationId.isNotEmpty ? op.operationId : op.key),
        status: op.success?.code,
        note: _roles.containsKey(op) ? 'stateful' : '',
      ),
  ];

  // --- routing ---------------------------------------------------------------------------

  @override
  MockMatch? match(String method, String path) {
    final parts = _split(path);
    MockMatch? best;
    var bestScore = -1;
    for (final withBase in _baseSegments.isEmpty ? const [true] : const [true, false]) {
      for (final op in spec.operations) {
        if (op.method != method.toUpperCase()) continue;
        final pattern = withBase ? [..._baseSegments, ...op.segments] : op.segments;
        final captured = _capture(pattern, parts);
        if (captured == null) continue;
        if (captured.score > bestScore) {
          best = MockMatch(key: op.key, pathParams: captured.params, route: op);
          bestScore = captured.score;
        }
      }
      // The path without the document's base path is only tried when nothing matched with it.
      if (best != null) break;
    }
    return best;
  }

  @override
  List<String> methodsFor(String path) {
    final parts = _split(path);
    return {
      for (final op in spec.operations)
        if (_capture([..._baseSegments, ...op.segments], parts) != null || (_baseSegments.isNotEmpty && _capture(op.segments, parts) != null)) op.method,
    }.toList();
  }

  static List<String> _split(String path) => [
        for (final s in path.split('/'))
          if (s.isNotEmpty) _decode(s),
      ];

  static String _decode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }

  /// The path parameters of [path] against [pattern] (a `{name}` matches anything), and how many static segments agreed.
  static ({Map<String, String> params, int score})? _capture(List<String> pattern, List<String> path) {
    if (pattern.length != path.length) return null;
    final params = <String, String>{};
    var score = 0;
    for (var i = 0; i < pattern.length; i++) {
      if (SpecOperation.isParam(pattern[i])) {
        params[SpecOperation.paramName(pattern[i])] = path[i];
      } else if (pattern[i] == path[i]) {
        score++;
      } else {
        return null;
      }
    }
    return (params: params, score: score);
  }

  // --- answering ----------------------------------------------------------------------------

  @override
  MockResponse respond(MockMatch match, MockRequest request) {
    final op = match.route as SpecOperation;
    if (validateRequests) {
      final problems = _validate(op, match.pathParams, request);
      if (problems.isNotEmpty) return _validationError(op, problems);
    }
    final role = _roles[op];
    if (role != null) return _crud(role.$1, role.$2, op, match, request);
    return _stateless(op, match.pathParams);
  }

  @override
  MockResponse? errorResponse(MockMatch? match, MockRequest request, int status, String message) =>
      _error(match?.route as SpecOperation?, status, message);

  // --- validation ---------------------------------------------------------------------------

  List<MockViolation> _validate(SpecOperation op, Map<String, String> pathParams, MockRequest request) {
    final problems = <MockViolation>[];
    for (final p in op.parameters) {
      switch (p.location) {
        case 'path':
          final value = pathParams[p.name];
          if (value != null) problems.addAll(_validator.validateText(p.schema, value, 'path.${p.name}'));
        case 'query':
          final values = request.query[p.name];
          if (values == null || values.isEmpty) {
            if (p.required) problems.add(MockViolation('query.${p.name}', 'is required'));
          } else {
            for (final v in values) {
              problems.addAll(_validator.validateText(p.schema, v, 'query.${p.name}'));
            }
          }
        case 'header':
          final value = request.header(p.name);
          if (value == null) {
            if (p.required) problems.add(MockViolation('header.${p.name}', 'is required'));
          } else {
            problems.addAll(_validator.validateText(p.schema, value, 'header.${p.name}'));
          }
      }
    }
    final body = op.requestBody;
    if (body != null && const {'POST', 'PUT', 'PATCH'}.contains(op.method)) {
      final json = body.contentType.isEmpty || body.contentType.contains('json');
      if (!request.hasBody) {
        if (body.required) problems.add(const MockViolation(r'$', 'a request body is required'));
      } else if (json && body.schema != null) {
        if (!request.hasJsonBody) {
          problems.add(const MockViolation(r'$', 'the request body is not valid JSON'));
        } else {
          problems.addAll(_validator.validate(body.schema!, request.bodyJson, partial: op.method == 'PATCH'));
        }
      }
    }
    return problems;
  }

  MockResponse _validationError(SpecOperation op, List<MockViolation> problems) {
    final status = op.responses.containsKey('400') ? 400 : (op.responses.containsKey('422') ? 422 : 400);
    final more = problems.length > 1 ? ' (and ${problems.length - 1} more)' : '';
    return _error(op, status, '${problems.first}$more', details: problems);
  }

  // --- error shapes ----------------------------------------------------------------------------

  /// The first error schema any operation declares, for the operations that declare none of their own.
  late final Map<String, dynamic>? _sharedErrorSchema = () {
    for (final op in spec.operations) {
      for (final r in op.responses.values) {
        final code = r.code;
        if (r.schema != null && (r.status == 'default' || (code != null && code >= 400))) return r.schema;
      }
    }
    return null;
  }();

  /// An error answer of [status] in the shape the document declares for it: the operation's response for that status, else
  /// its `default`, else an error schema used elsewhere in the document, else a plain `{error, message, status}`.
  MockResponse _error(SpecOperation? op, int status, String message, {List<MockViolation> details = const []}) {
    final declared = op?.responseFor(status);
    final schema = declared?.schema ?? _sharedErrorSchema;
    final reason = mockReasonPhrase(status);
    if (schema != null) {
      final fake = faker.generate(schema, name: 'error', path: r'$error');
      if (fake is Map) {
        final filled = _fillError(Map<String, dynamic>.from(fake), status, reason, message, details, 0);
        return MockResponse.json(status, filled);
      }
      if (fake is String) return MockResponse.json(status, message);
    }
    return MockResponse.json(status, {
      'error': reason,
      'message': message,
      'status': status,
      if (details.isNotEmpty) 'details': [for (final d in details) {'field': d.field, 'message': d.message}],
    });
  }

  static const _messageKeys = {'message', 'msg', 'errormessage', 'errordescription', 'detail', 'description', 'reason', 'text'};
  static const _statusKeys = {'status', 'statuscode', 'httpstatus', 'httpstatuscode', 'code', 'errorcode'};
  static const _listKeys = {'errors', 'details', 'violations', 'fielderrors', 'issues', 'validationerrors', 'problems'};
  static const _fieldKeys = {'field', 'path', 'name', 'param', 'parameter', 'property', 'pointer', 'location', 'loc', 'source'};

  Map<String, dynamic> _fillError(Map<String, dynamic> error, int status, String reason, String message, List<MockViolation> details, int depth) {
    String normal(String k) => k.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final hasMessage = error.keys.any((k) => _messageKeys.contains(normal(k)));
    for (final key in error.keys.toList()) {
      final k = normal(key);
      final value = error[key];
      if (value is Map && depth < 2) {
        error[key] = _fillError(Map<String, dynamic>.from(value), status, reason, message, details, depth + 1);
      } else if (_messageKeys.contains(k) && (value is String || value == null)) {
        error[key] = message;
      } else if (k == 'error' && (value is String || value == null)) {
        // `error` is the short reason when there is also a message, else it carries the message itself.
        error[key] = hasMessage ? reason : message;
      } else if (k == 'title' && value is String) {
        error[key] = reason;
      } else if (_statusKeys.contains(k) && value is num) {
        error[key] = status;
      } else if (_statusKeys.contains(k) && value is String) {
        error[key] = k == 'status' ? 'error' : reason.toLowerCase().replaceAll(' ', '_');
      } else if (_listKeys.contains(k) && value is List) {
        error[key] = _errorItems(value, details, message, messageElsewhere: hasMessage);
      }
    }
    return error;
  }

  /// The entries of an error list (`errors`, `details`...): one per problem, in the shape the faked sample had. With no
  /// problem to list (a 404, say) the list is empty, unless it is the only place the shape has for a message.
  List<dynamic> _errorItems(List<dynamic> template, List<MockViolation> details, String message, {required bool messageElsewhere}) {
    final sample = template.firstOrNull;
    if (details.isEmpty) return messageElsewhere || sample is Map ? <dynamic>[] : [message];
    if (sample is Map) {
      return [
        for (final d in details)
          {
            for (final e in sample.entries)
              '${e.key}': switch (e.key.toString().toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')) {
                final k when _fieldKeys.contains(k) && e.value is String => d.field,
                final k when _messageKeys.contains(k) && e.value is String => d.message,
                'code' || 'type' || 'rule' when e.value is String => 'invalid',
                _ => e.value,
              },
          },
      ];
    }
    return [for (final d in details) d.field.isEmpty ? d.message : '${d.field}: ${d.message}'];
  }

  // --- operations that are not part of a resource ------------------------------------------------

  MockResponse _stateless(SpecOperation op, Map<String, String> pathParams) {
    final ok = op.success;
    final code = ok?.code ?? 200;
    if (ok == null) return MockResponse.json(200, <String, dynamic>{});
    if (code == 204 || (ok.schema == null && ok.example == null)) return MockResponse(code);
    Object? body = ok.example ?? faker.generate(ok.schema!, name: op.operationId.isEmpty ? 'result' : op.operationId, path: '\$.${op.key}');
    body = _echo(body, op, pathParams);
    if (ok.contentType.startsWith('text/') && body is String) {
      return MockResponse(code, headers: {'content-type': ok.contentType}, body: body);
    }
    return MockResponse.json(code, body);
  }

  /// A fake object that has a property named like a path parameter gets the value the request used, so
  /// `GET /users/42` answers a user whose `id` is 42.
  Object? _echo(Object? body, SpecOperation op, Map<String, String> pathParams) {
    if (body is! Map || pathParams.isEmpty) return body;
    final result = Map<String, dynamic>.from(body);
    pathParams.forEach((name, value) {
      final parameter = op.parameter(name, 'path');
      final integer = parameter != null && MockFaker.typeOf(spec.resolver.flatten(parameter.schema)) == 'integer';
      final typed = integer ? (int.tryParse(value) ?? value) : value;
      final isLast = op.segments.isNotEmpty && SpecOperation.isParam(op.segments.last) && SpecOperation.paramName(op.segments.last) == name;
      if (result.containsKey(name)) {
        result[name] = typed;
      } else if (isLast && result.containsKey('id')) {
        result['id'] = typed;
      }
    });
    return result;
  }

  // --- stateful resources --------------------------------------------------------------------------

  /// The concrete collection an operation works on: a collection under a parent has one list per parent.
  String _scope(SpecOperation op, MockResourceRole role, Map<String, String> params) {
    final isItem = role != MockResourceRole.list && role != MockResourceRole.create;
    final segments = isItem ? op.segments.sublist(0, op.segments.length - 1) : op.segments;
    return '/${segments.map((s) => SpecOperation.isParam(s) ? (params[SpecOperation.paramName(s)] ?? '') : s).join('/')}';
  }

  MockResponse _crud(MockResourceFamily family, MockResourceRole role, SpecOperation op, MockMatch match, MockRequest request) {
    final scope = _scope(op, role, match.pathParams);
    final id = family.idParam == null ? null : match.pathParams[family.idParam];
    switch (role) {
      case MockResourceRole.list:
        return _list(family, op, scope, request);
      case MockResourceRole.create:
        final body = _bodyObject(request);
        if (body == null) return _error(op, 400, 'The request body must be a JSON object.');
        final created = store.create(family, scope, body);
        return _item(family, op, _status(op, 201, prefer: 201), created);
      case MockResourceRole.read:
        final found = store.find(family, scope, id!);
        return found == null ? _notFound(family, op, id) : _item(family, op, _status(op, 200), found);
      case MockResourceRole.replace:
        final body = _bodyObject(request);
        if (body == null) return _error(op, 400, 'The request body must be a JSON object.');
        final replaced = store.replace(family, scope, id!, body);
        return replaced == null ? _notFound(family, op, id) : _item(family, op, _status(op, 200), replaced);
      case MockResourceRole.update:
        final body = _bodyObject(request);
        if (body == null) return _error(op, 400, 'The request body must be a JSON object.');
        final merged = store.merge(family, scope, id!, body);
        return merged == null ? _notFound(family, op, id) : _item(family, op, _status(op, 200), merged);
      case MockResourceRole.remove:
        final removed = store.remove(family, scope, id!);
        if (removed == null) return _notFound(family, op, id);
        final status = _status(op, 204);
        final declared = op.success;
        // A delete that declares a body answers with the item it removed; the usual 204 has none.
        if (status == 204 || declared == null || (declared.schema == null && declared.example == null)) return MockResponse(status);
        return _item(family, op, status, removed);
    }
  }

  /// The body of a write as an object: `{}` when there is none, null when it is something else.
  Map<String, dynamic>? _bodyObject(MockRequest request) {
    if (!request.hasBody) return <String, dynamic>{};
    final json = request.bodyJson;
    return json is Map ? json.cast<String, dynamic>() : null;
  }

  /// The status [op] declares for success; [prefer] wins when several 2xx are declared and it is one of them.
  int _status(SpecOperation op, int fallback, {int? prefer}) {
    if (prefer != null && op.responses.containsKey('$prefer')) return prefer;
    return op.success?.code ?? fallback;
  }

  MockResponse _notFound(MockResourceFamily family, SpecOperation op, String id) =>
      _error(op, 404, 'No ${_singular(family.name)} with ${family.idField} "$id".');

  String _singular(String name) => name.endsWith('s') && name.length > 1 ? name.substring(0, name.length - 1) : name;

  MockResponse _item(MockResourceFamily family, SpecOperation op, int status, Map<String, dynamic> item) {
    final shown = _public(family, item);
    final envelope = family.itemEnvelope;
    if (envelope == null) return MockResponse.json(status, shown);
    final body = <String, dynamic>{envelope.payloadKey: shown};
    envelope.meta.forEach((name, schema) {
      body[name] = faker.generate(schema, name: name, path: '\$.${family.name}.item.$name');
    });
    return MockResponse.json(status, body);
  }

  /// [item] without its write-only properties (a password the client sent is not echoed back).
  Map<String, dynamic> _public(MockResourceFamily family, Map<String, dynamic> item) {
    final flat = spec.resolver.flatten(family.itemSchema);
    final properties = flat['properties'];
    if (properties is! Map) return item;
    final hidden = <String>{
      for (final e in properties.entries)
        if (e.value is Map && spec.resolver.flatten((e.value as Map).cast<String, dynamic>())['writeOnly'] == true) '${e.key}',
    };
    if (hidden.isEmpty) return item;
    return {for (final e in item.entries) if (!hidden.contains(e.key)) e.key: e.value};
  }

  MockResponse _list(MockResourceFamily family, SpecOperation op, String scope, MockRequest request) {
    final names = MockPagination.namesOf(op.parameters);
    final strategy = pagination == MockPaginationStrategy.auto ? MockPagination.detect(names) : pagination;
    final filtered = MockPagination.filter(store.items(family, scope), request, except: MockPagination.reserved(names));
    final page = MockPagination.paginate(filtered, request, strategy: strategy, names: names);
    final shown = [for (final item in page.items) _public(family, item)];
    final status = _status(op, 200);
    final envelope = family.listEnvelope;
    if (envelope == null) return MockResponse.json(status, shown, headers: page.headers);
    final body = <String, dynamic>{envelope.payloadKey: shown};
    envelope.meta.forEach((name, schema) {
      final paging = MockPagination.meta(name, page);
      body[name] = paging.found ? paging.value : faker.generate(schema, name: name, path: '\$.${family.name}.list.$name');
    });
    return MockResponse.json(status, body, headers: page.headers);
  }

  /// A one-line description of what was found, for the dialog.
  String get summary {
    final stateful = families.length;
    return '${spec.operations.length} operations, $stateful resource${stateful == 1 ? '' : 's'} with data in memory';
  }
}
