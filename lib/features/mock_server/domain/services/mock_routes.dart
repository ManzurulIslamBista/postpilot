/// One endpoint the mock server answers.
final class MockRoute {
  final String method;

  /// Path segments; a segment that is a `:name`, `{name}` or `{{name}}` matches anything.
  final List<String> segments;
  final int status;
  final Map<String, String> headers;
  final String body;

  /// Where the answer came from, shown in the route list.
  final String requestName;
  final String exampleName;

  const MockRoute({
    required this.method,
    required this.segments,
    required this.status,
    required this.headers,
    required this.body,
    required this.requestName,
    required this.exampleName,
  });

  String get path => '/${segments.join('/')}';

  static bool isParam(String segment) =>
      segment.startsWith(':') || (segment.startsWith('{') && segment.endsWith('}')) || segment.startsWith('{{');
}

/// What a collection request needs to become a route.
final class MockSource {
  final String requestName;
  final String method;
  final String url;
  final int? exampleStatus;
  final Map<String, String> exampleHeaders;
  final String? exampleBody;
  final String? exampleName;

  const MockSource({
    required this.requestName,
    required this.method,
    required this.url,
    this.exampleStatus,
    this.exampleHeaders = const {},
    this.exampleBody,
    this.exampleName,
  });
}

final class MockRouteTable {
  final List<MockRoute> routes;

  /// Requests that have no saved example, so nothing to answer with.
  final List<String> skipped;
  const MockRouteTable(this.routes, this.skipped);

  /// The route for [method] and [path] (query string ignored). Static segments
  /// beat parameters, so `/users/me` is not swallowed by `/users/:id`.
  MockRoute? match(String method, String path) {
    final parts = _segmentsOf(path);
    MockRoute? best;
    var bestScore = -1;
    for (final route in routes) {
      if (route.method != method.toUpperCase() || route.segments.length != parts.length) continue;
      var score = 0;
      var ok = true;
      for (var i = 0; i < parts.length; i++) {
        final r = route.segments[i];
        if (MockRoute.isParam(r)) continue;
        if (r == parts[i]) {
          score++;
        } else {
          ok = false;
          break;
        }
      }
      if (ok && score > bestScore) {
        best = route;
        bestScore = score;
      }
    }
    return best;
  }

  /// Paths that exist for other methods, for a helpful 404 / 405.
  List<String> methodsFor(String path) {
    final parts = _segmentsOf(path);
    return {
      for (final r in routes)
        if (r.segments.length == parts.length && _matchesPath(r, parts)) r.method,
    }.toList();
  }

  static bool _matchesPath(MockRoute r, List<String> parts) {
    for (var i = 0; i < parts.length; i++) {
      if (!MockRoute.isParam(r.segments[i]) && r.segments[i] != parts[i]) return false;
    }
    return true;
  }

  static List<String> _segmentsOf(String path) {
    final q = path.indexOf('?');
    final clean = q >= 0 ? path.substring(0, q) : path;
    return clean.split('/').where((s) => s.isNotEmpty).map(_decode).toList();
  }

  static String _decode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }

  /// `{{baseUrl}}/users/:id?x=1` and `https://api.test/v1/users/42` both reduce to their path.
  static List<String> pathOfUrl(String url) {
    var rest = url.trim();
    final q = rest.indexOf('?');
    if (q >= 0) rest = rest.substring(0, q);
    final varBase = RegExp(r'^\{\{[^{}]+\}\}').firstMatch(rest);
    if (varBase != null) {
      rest = rest.substring(varBase.end);
    } else {
      final origin = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+').firstMatch(rest);
      if (origin != null) rest = rest.substring(origin.end);
    }
    return rest.split('/').where((s) => s.isNotEmpty).toList();
  }

  /// Builds the table. Several requests with the same method and path: the first wins.
  factory MockRouteTable.from(List<MockSource> sources) {
    final routes = <MockRoute>[];
    final skipped = <String>[];
    final seen = <String>{};
    for (final s in sources) {
      final body = s.exampleBody;
      if (body == null || s.exampleStatus == null) {
        skipped.add(s.requestName);
        continue;
      }
      final segments = pathOfUrl(s.url);
      final key = '${s.method.toUpperCase()} /${segments.map((x) => MockRoute.isParam(x) ? '*' : x).join('/')}';
      if (!seen.add(key)) continue;
      routes.add(MockRoute(
        method: s.method.toUpperCase(),
        segments: segments,
        status: s.exampleStatus!,
        headers: s.exampleHeaders,
        body: body,
        requestName: s.requestName,
        exampleName: s.exampleName ?? '',
      ));
    }
    routes.sort((a, b) => a.path.compareTo(b.path));
    return MockRouteTable(routes, skipped);
  }
}
