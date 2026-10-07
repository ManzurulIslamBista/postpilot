import 'dart:convert';
import 'dart:math';
import 'mock_example_handler.dart';
import 'mock_handler.dart';
import 'mock_http.dart';
import 'mock_network.dart';
import 'mock_routes.dart';
import 'mock_scenarios.dart';
import 'mock_spec_handler.dart';

/// Everything the mock server decides for a request, with no socket in sight: which route it is, whether a scenario
/// (slow, flaky, a 401, a hung connection...) applies, what the answer is. The engine only moves bytes in and out, so
/// all of this is tested directly, with a clock that does not wait.
///
/// It answers from the saved examples of a collection, or, when [spec] is set, from an OpenAPI document.
final class MockBackend {
  final MockClock clock;
  final MockExampleHandler examples;
  final MockScenarios scenarios = MockScenarios();

  /// Slow, lossy, flapping, offline... networks for the whole server or one route, on top of the scenarios.
  final MockNetwork network;
  final Random _random;

  /// When set, requests are answered from this document and the saved examples are not used.
  MockSpecHandler? spec;

  /// A wait added before every answer, whatever the scenario.
  Duration delay;

  MockBackend({
    MockRouteTable table = const MockRouteTable([], []),
    this.clock = const SystemMockClock(),
    Random? random,
    this.delay = Duration.zero,
    this.spec,
    List<MockMatchRule> rules = const [],
  })  : examples = MockExampleHandler(table, rules: rules, clock: clock),
        network = MockNetwork(clock.now),
        _random = random ?? Random();

  MockRouteTable get table => examples.table;
  set table(MockRouteTable value) => examples.table = value;

  List<MockMatchRule> get rules => examples.rules;
  set rules(List<MockMatchRule> value) => examples.rules = value;

  /// What answers right now.
  MockHandler get handler => spec ?? examples;

  List<MockRouteInfo> get routes => handler.routes;

  Future<MockOutcome> handle(MockRequest request) async {
    final started = clock.now();
    final handler = this.handler;
    final method = request.method;

    var match = handler.match(method, request.path);
    var headOnly = false;
    // HEAD is GET without the body, so a route that only has a GET answers it.
    if (match == null && method == 'HEAD') {
      match = handler.match('GET', request.path);
      headOnly = match != null;
    }
    // OPTIONS on a path the server knows says what is allowed; browsers' CORS preflights are the engine's.
    if (match == null && method == 'OPTIONS') {
      final methods = handler.methodsFor(request.path);
      if (methods.isNotEmpty) {
        return MockOutcome(response: _finish(MockResponse(204, headers: {'allow': _allow(methods)})), elapsed: clock.now().difference(started));
      }
    }

    final decision = scenarios.decide(match?.key, _random);
    final net = network.decide(match?.key, _random);
    if (decision.hang || net.hang) {
      return MockOutcome(
        response: null,
        route: match?.key,
        scenario: decision.label,
        network: net.label,
        elapsed: clock.now().difference(started),
      );
    }
    final wait = delay + decision.latency + net.latency;
    if (wait > Duration.zero) await clock.delay(wait);
    if (net.dropConnection) {
      return MockOutcome(
        response: null,
        route: match?.key,
        scenario: decision.label,
        network: net.label,
        elapsed: clock.now().difference(started),
        dropped: true,
      );
    }

    MockResponse response;
    final fail = decision.failStatus;
    if (fail != null) {
      final message = 'The mock server is set to answer ${mockReasonPhrase(fail)} for this request.';
      response = handler.errorResponse(match, request, fail, message) ?? _plainError(fail, message);
    } else if (match == null) {
      response = _noRoute(handler, request);
    } else {
      response = handler.respond(match, request);
      if (decision.emptyList) response = emptyLists(response);
      if (decision.malformedJson) response = malformed(response);
    }
    // The network speaks last: a failing route is still slow, and a server error from the network replaces a good answer.
    final netError = fail == null ? net.errorStatus : null;
    if (netError != null) {
      final message = 'The mock server is simulating a bad network (${net.profile}): it answers ${mockReasonPhrase(netError)}.';
      response = handler.errorResponse(match, request, netError, message) ?? _plainError(netError, message);
      final retry = net.retryAfterSeconds;
      if (retry != null) response = response.copyWith(headers: {...response.headers, 'retry-after': '$retry'});
    }
    final corruption = net.corruption;
    if (corruption != null) response = corrupt(response, corruption);
    response = _finish(response);
    if (headOnly) {
      response = response.copyWith(headers: {...response.headers, 'content-length': '${utf8.encode(response.body).length}'});
    }
    final wrongLength = corruption == NetworkCorruption.wrongContentLength;
    final wire = !headOnly && (net.bytesPerSecond > 0 || net.truncateAt != null || wrongLength)
        ? MockWire(
            bytesPerSecond: net.bytesPerSecond,
            truncateAt: net.truncateAt,
            declaredLengthExtra: wrongLength ? max(16, utf8.encode(response.body).length ~/ 2) : 0,
          )
        : null;
    return MockOutcome(
      response: response,
      route: match?.key,
      scenario: decision.label,
      network: net.label,
      elapsed: clock.now().difference(started),
      headOnly: headOnly,
      wire: wire,
    );
  }

  /// [response] broken the way [mode] says. A wrong content length is on the wire, not in the response: see [MockWire].
  static MockResponse corrupt(MockResponse response, NetworkCorruption mode) => switch (mode) {
        NetworkCorruption.truncatedJson => malformed(response),
        NetworkCorruption.malformedJson => brokenSyntax(response),
        NetworkCorruption.wrongContentType => response.copyWith(headers: {
            for (final e in response.headers.entries)
              if (e.key.toLowerCase() != 'content-type') e.key: e.value,
            'content-type': 'text/html; charset=utf-8',
          }),
        NetworkCorruption.wrongContentLength => response,
      };

  /// [response] with a comma before the last closing bracket: valid JavaScript, a syntax error in JSON. An answer with no body
  /// gets a small broken object.
  static MockResponse brokenSyntax(MockResponse response) {
    var text = response.body.trim().isEmpty ? '{"data": [1,,]}' : response.body;
    final at = max(text.lastIndexOf('}'), text.lastIndexOf(']'));
    text = at >= 0 ? '${text.substring(0, at)},${text.substring(at)}' : '$text}';
    while (_parses(text)) {
      text = '$text}}';
    }
    return MockResponse(
      response.status == 204 ? 200 : response.status,
      headers: {...response.headers, 'content-type': 'application/json'},
      body: text,
    );
  }

  MockResponse _finish(MockResponse response) => response.copyWith(headers: {...response.headers, 'x-mock-server': 'postpilot'});

  MockResponse _plainError(int status, String message) =>
      MockResponse.json(status, {'error': mockReasonPhrase(status), 'message': message, 'status': status});

  String _allow(List<String> methods) {
    final all = {...methods, 'OPTIONS', if (methods.contains('GET')) 'HEAD'}.toList()..sort();
    return all.join(', ');
  }

  MockResponse _noRoute(MockHandler handler, MockRequest request) {
    final others = handler.methodsFor(request.path);
    final status = others.isEmpty ? 404 : 405;
    return MockResponse.json(
      status,
      {
        'error': others.isEmpty ? 'No mock for ${request.method} ${request.path}' : '${request.method} is not mocked for ${request.path}',
        if (others.isNotEmpty) 'mockedMethods': others,
        'routes': [for (final r in handler.routes) '${r.method} ${r.path}'],
      },
      headers: {if (others.isNotEmpty) 'allow': _allow(others)},
    );
  }

  static const _countKeys = {'total', 'totalcount', 'count', 'totalitems', 'totalelements', 'totalresults', 'numfound', 'resultcount'};
  static const _moreKeys = {'hasmore', 'hasnext', 'hasnextpage', 'more'};
  static const _cursorKeys = {'nextcursor', 'nextpagetoken', 'nexttoken', 'endcursor', 'next'};

  /// [response] with every list in its JSON body emptied (and the counts that describe them set to 0), for the "empty list"
  /// scenario. A body that is not JSON, or has no list, stays as it is.
  static MockResponse emptyLists(MockResponse response) {
    if (response.body.trim().isEmpty) return response;
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      return response;
    }
    final emptied = _empty(decoded, 0);
    final headers = {
      for (final e in response.headers.entries) e.key: e.key.toLowerCase() == 'x-total-count' ? '0' : e.value,
    }..remove('link');
    return response.copyWith(body: jsonEncode(emptied), headers: headers);
  }

  static Object? _empty(Object? value, int depth) {
    if (value is List) return <dynamic>[];
    if (value is! Map) return value;
    return {
      for (final e in value.entries)
        '${e.key}': switch (e.value) {
          List() => <dynamic>[],
          Map() when depth < 2 => _empty(e.value, depth + 1),
          num() when _countKeys.contains(_key('${e.key}')) => 0,
          bool() when _moreKeys.contains(_key('${e.key}')) => false,
          String() when _cursorKeys.contains(_key('${e.key}')) => null,
          _ => e.value,
        },
    };
  }

  static String _key(String name) => name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// [response] with a body that no longer parses as JSON: its first part, cut off. An answer without a body gets a
  /// truncated object, so a client that expects JSON has something to fail on.
  static MockResponse malformed(MockResponse response) {
    var text = response.body.trim().isEmpty ? '{"data": [' : response.body.substring(0, max(1, (response.body.length * 0.6).floor()));
    while (_parses(text)) {
      text = '$text,{';
    }
    return MockResponse(
      response.status == 204 ? 200 : response.status,
      headers: {...response.headers, 'content-type': 'application/json'},
      body: text,
    );
  }

  static bool _parses(String text) {
    try {
      jsonDecode(text);
      return true;
    } catch (_) {
      return false;
    }
  }
}
