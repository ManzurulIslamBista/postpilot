import 'mock_handler.dart';
import 'mock_http.dart';
import 'mock_routes.dart';
import 'mock_template.dart';

/// Where a [MockMatchRule] reads the value it compares.
enum MockMatchSource {
  query('Query parameter'),
  body('JSON body field'),
  header('Header');

  const MockMatchSource(this.label);

  final String label;
}

/// "When this part of the request equals that, answer with this saved example", for one route.
final class MockMatchRule {
  /// Stable, so an editable list of rules keeps its rows.
  final String id;

  /// The route's key (`POST /login`).
  final String routeKey;
  final MockMatchSource source;

  /// The query parameter or header name, or the dotted path into the JSON body (`user.role`).
  final String field;

  /// The text the value must equal.
  final String equals;

  /// The saved example to answer with, by name.
  final String exampleName;

  const MockMatchRule({
    required this.id,
    required this.routeKey,
    required this.source,
    required this.field,
    required this.equals,
    required this.exampleName,
  });

  MockMatchRule copyWith({String? routeKey, MockMatchSource? source, String? field, String? equals, String? exampleName}) => MockMatchRule(
        id: id,
        routeKey: routeKey ?? this.routeKey,
        source: source ?? this.source,
        field: field ?? this.field,
        equals: equals ?? this.equals,
        exampleName: exampleName ?? this.exampleName,
      );

  bool get isComplete => field.trim().isNotEmpty && exampleName.isNotEmpty;

  /// Whether [request] has the value this rule asks for.
  bool matches(MockRequest request) {
    final name = field.trim();
    if (name.isEmpty) return false;
    switch (source) {
      case MockMatchSource.query:
        return request.query[name]?.contains(equals) ?? false;
      case MockMatchSource.header:
        return request.header(name) == equals;
      case MockMatchSource.body:
        Object? current = request.bodyJson;
        for (final part in name.split('.')) {
          if (current is Map && current.containsKey(part)) {
            current = current[part];
          } else if (current is List && int.tryParse(part) != null && int.parse(part) < current.length) {
            current = current[int.parse(part)];
          } else {
            return false;
          }
        }
        return '$current' == equals;
    }
  }
}

/// Answers from the saved examples of a collection.
///
/// A route that has several saved examples answers with the first successful one, unless the request asks for another:
/// `?status=404` (or the header `x-mock-status`) picks the example saved with that status, `?example=Not found` (or `x-mock-example`) the
/// one with that name, and a [MockMatchRule] picks one by a query parameter, header or JSON body field. `{{...}}` in
/// the body is filled from the request (see [MockTemplate]).
final class MockExampleHandler implements MockHandler {
  MockRouteTable table;
  List<MockMatchRule> rules;
  final MockClock clock;

  MockExampleHandler(this.table, {this.rules = const [], this.clock = const SystemMockClock()});

  /// Headers that described how the body travelled when it was saved, not the text stored in the example.
  static const _skipHeaders = {
    'content-length', 'transfer-encoding', 'connection', 'content-encoding', 'keep-alive', 'date', 'server', 'set-cookie',
  };

  @override
  List<MockRouteInfo> get routes => [
        for (final r in table.routes)
          MockRouteInfo(
            key: r.key,
            method: r.method,
            path: r.path,
            title: r.requestName,
            status: r.status,
            note: r.allExamples.length > 1 ? '${r.allExamples.length} examples' : r.exampleName,
          ),
      ];

  @override
  MockMatch? match(String method, String path) {
    final m = table.matchWithParams(method, path);
    return m == null ? null : MockMatch(key: m.route.key, pathParams: m.params, route: m.route);
  }

  @override
  List<String> methodsFor(String path) => table.methodsFor(path);

  @override
  MockResponse respond(MockMatch match, MockRequest request) {
    final route = match.route as MockRoute;
    final choice = _choose(route, request);
    if (choice.missing != null) {
      return MockResponse.json(404, {
        'error': choice.missing,
        'available': [
          for (final e in route.allExamples) {'name': e.name, 'status': e.status},
        ],
      });
    }
    final example = choice.example!;
    final body = MockTemplate.render(example.body, request, pathParams: match.pathParams, now: clock.now());
    return _answer(example, body, route.allExamples.length > 1);
  }

  @override
  MockResponse? errorResponse(MockMatch? match, MockRequest request, int status, String message) {
    if (match == null) return null;
    final route = match.route as MockRoute;
    for (final e in route.allExamples) {
      if (e.status == status) {
        return _answer(e, MockTemplate.render(e.body, request, pathParams: match.pathParams, now: clock.now()), true);
      }
    }
    return null;
  }

  MockResponse _answer(MockExample example, String body, bool named) {
    final headers = <String, String>{};
    example.headers.forEach((k, v) {
      final name = k.toLowerCase();
      // `Access-Control-*` in an example is what the real server decided for its own callers; the mock's own CORS setting
      // decides here, so those are never replayed.
      if (_skipHeaders.contains(name) || name.startsWith('access-control-')) return;
      if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(k) || RegExp(r'[\x00-\x1f\x7f]').hasMatch(v)) return;
      headers[name] = v;
    });
    headers.putIfAbsent('content-type', () => _looksJson(body) ? 'application/json' : 'text/plain');
    if (named && example.name.isNotEmpty && !RegExp(r'[^\x20-\x7e]').hasMatch(example.name)) headers['x-mock-example'] = example.name;
    return MockResponse(example.status, headers: headers, body: body);
  }

  ({MockExample? example, String? missing}) _choose(MockRoute route, MockRequest request) {
    final examples = route.allExamples;
    final defaultExample = examples.firstWhere((e) => e.status >= 200 && e.status < 300, orElse: () => examples.first);
    // With one example there is nothing to choose, and `?status=` or `?example=` may be the app's own parameter.
    if (examples.length < 2) return (example: defaultExample, missing: null);

    for (final rule in rules) {
      if (rule.routeKey != route.key || !rule.isComplete || !rule.matches(request)) continue;
      final named = examples.where((e) => e.name == rule.exampleName).firstOrNull;
      if (named != null) return (example: named, missing: null);
    }

    final name = request.queryValue('example') ?? request.header('x-mock-example');
    if (name != null && name.isNotEmpty) {
      final named = examples.where((e) => e.name.toLowerCase() == name.toLowerCase()).firstOrNull;
      if (named != null) return (example: named, missing: null);
      return (example: null, missing: 'No saved example named "$name" for ${route.key}');
    }

    final wanted = int.tryParse(request.queryValue('status') ?? request.header('x-mock-status') ?? '');
    if (wanted != null && wanted >= 100 && wanted <= 599) {
      final byStatus = examples.where((e) => e.status == wanted).firstOrNull;
      if (byStatus != null) return (example: byStatus, missing: null);
      // `?status=200` on a route that is filtered by a status field is just a filter: the default answer stands.
    }
    return (example: defaultExample, missing: null);
  }

  static bool _looksJson(String body) {
    final t = body.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }
}
