import 'dart:math';

/// What can go wrong (or slow) on purpose, so an app's error handling can be seen working.
enum MockScenarioKind {
  normal('Normal', 'Answer as the route normally does'),
  emptyList('Empty list', 'Lists answer with no items'),
  unauthorized('401 Unauthorized', 'Answer 401'),
  forbidden('403 Forbidden', 'Answer 403'),
  notFound('404 Not found', 'Answer 404'),
  serverError('500 Server error', 'Answer 500'),
  slow('Slow', 'Wait before answering, a fixed time or a random one in a range'),
  flaky('Flaky', 'Fail every Nth request, or a share of them, and answer the others normally'),
  malformedJson('Malformed JSON', 'Answer 200 with a body that is cut off, so it does not parse'),
  timeout('Timeout', 'Never answer: the connection stays open until the caller gives up');

  const MockScenarioKind(this.label, this.description);

  final String label;
  final String description;
}

/// One scenario with its settings. Immutable: changing a route's scenario replaces it.
final class MockScenario {
  final MockScenarioKind kind;

  /// [MockScenarioKind.slow]: the wait in milliseconds, a fixed one when both are equal.
  final int latencyMinMs;
  final int latencyMaxMs;

  /// [MockScenarioKind.flaky]: every Nth request fails (when above 0), otherwise [failPercent] of them do.
  final int failEvery;
  final int failPercent;

  /// The status a flaky failure answers with.
  final int failStatus;

  const MockScenario(
    this.kind, {
    this.latencyMinMs = 1000,
    this.latencyMaxMs = 1000,
    this.failEvery = 3,
    this.failPercent = 30,
    this.failStatus = 500,
  });

  static const normal = MockScenario(MockScenarioKind.normal);

  /// Slow, [minMs] to [maxMs] (a fixed wait when they are equal).
  const MockScenario.slow(int minMs, [int? maxMs])
      : kind = MockScenarioKind.slow,
        latencyMinMs = minMs,
        latencyMaxMs = maxMs ?? minMs,
        failEvery = 0,
        failPercent = 0,
        failStatus = 500;

  /// Flaky: every [every]th request fails, or [percent] of them when [every] is 0.
  const MockScenario.flaky({int every = 0, int percent = 30, int status = 500})
      : kind = MockScenarioKind.flaky,
        latencyMinMs = 0,
        latencyMaxMs = 0,
        failEvery = every,
        failPercent = percent,
        failStatus = status;

  bool get isNormal => kind == MockScenarioKind.normal;

  /// A short phrase for the log and the route list: `slow 200-800 ms`, `flaky (every 3rd)`, `401 Unauthorized`.
  String get label => switch (kind) {
        MockScenarioKind.slow => latencyMinMs == latencyMaxMs ? 'slow $latencyMinMs ms' : 'slow $latencyMinMs-$latencyMaxMs ms',
        MockScenarioKind.flaky => failEvery > 0 ? 'flaky (every ${_ordinal(failEvery)}, $failStatus)' : 'flaky ($failPercent% fail, $failStatus)',
        _ => kind.label.toLowerCase(),
      };

  static String _ordinal(int n) => switch (n) {
        1 => '1st',
        2 => '2nd',
        3 => '3rd',
        _ => '${n}th',
      };

  MockScenario copyWith({int? latencyMinMs, int? latencyMaxMs, int? failEvery, int? failPercent, int? failStatus}) => MockScenario(
        kind,
        latencyMinMs: latencyMinMs ?? this.latencyMinMs,
        latencyMaxMs: latencyMaxMs ?? this.latencyMaxMs,
        failEvery: failEvery ?? this.failEvery,
        failPercent: failPercent ?? this.failPercent,
        failStatus: failStatus ?? this.failStatus,
      );
}

/// What the backend does with one request, decided by the scenarios in force.
final class MockDecision {
  /// A wait before answering (zero for none).
  final Duration latency;

  /// Answer this status instead of the route's own answer; null for the normal one.
  final int? failStatus;

  /// Never answer.
  final bool hang;

  /// Answer normally, then empty the lists in the answer.
  final bool emptyList;

  /// Answer normally, then cut the body so it is no longer valid JSON.
  final bool malformedJson;

  /// For the log, null when nothing was applied.
  final String? label;

  const MockDecision({
    this.latency = Duration.zero,
    this.failStatus,
    this.hang = false,
    this.emptyList = false,
    this.malformedJson = false,
    this.label,
  });

  static const none = MockDecision();
}

/// The scenarios in force: one for the whole server and one per route, changed while it runs. A route's own scenario
/// replaces the global one, so "Normal" on a route exempts it from a global failure.
final class MockScenarios {
  MockScenario global = MockScenario.normal;
  final Map<String, MockScenario> _routes = {};
  final Map<String, int> _counts = {};

  /// Routes that have a scenario of their own (a normal one included).
  Map<String, MockScenario> get routes => Map.unmodifiable(_routes);

  bool get isAllNormal => global.isNormal && _routes.values.every((s) => s.isNormal);

  void setGlobal(MockScenario scenario) {
    global = scenario;
    _counts.remove(_globalScope);
  }

  /// A scenario for the route with this key (`GET /users/:id`); null takes it back to the global one.
  void setRoute(String key, MockScenario? scenario) {
    if (scenario == null) {
      _routes.remove(key);
    } else {
      _routes[key] = scenario;
    }
    _counts.remove('route:$key');
  }

  void clear() {
    global = MockScenario.normal;
    _routes.clear();
    _counts.clear();
  }

  static const _globalScope = 'global';

  /// The scenario in force for [routeKey] and the scope it counts requests in.
  ({MockScenario scenario, String scope}) _effective(String? routeKey) {
    final own = routeKey == null ? null : _routes[routeKey];
    return own == null ? (scenario: global, scope: _globalScope) : (scenario: own, scope: 'route:$routeKey');
  }

  /// What to do with the next request for [routeKey] (null when no route matched). A flaky scenario counts requests per
  /// scope: the Nth since the scenario was set fails, and which ones fail does not depend on any other route's traffic.
  MockDecision decide(String? routeKey, Random random) {
    final (:scenario, :scope) = _effective(routeKey);
    switch (scenario.kind) {
      case MockScenarioKind.normal:
        return MockDecision.none;
      case MockScenarioKind.emptyList:
        return MockDecision(emptyList: true, label: scenario.label);
      case MockScenarioKind.unauthorized:
        return MockDecision(failStatus: 401, label: scenario.label);
      case MockScenarioKind.forbidden:
        return MockDecision(failStatus: 403, label: scenario.label);
      case MockScenarioKind.notFound:
        return MockDecision(failStatus: 404, label: scenario.label);
      case MockScenarioKind.serverError:
        return MockDecision(failStatus: 500, label: scenario.label);
      case MockScenarioKind.malformedJson:
        return MockDecision(malformedJson: true, label: scenario.label);
      case MockScenarioKind.timeout:
        return MockDecision(hang: true, label: scenario.label);
      case MockScenarioKind.slow:
        final low = min(scenario.latencyMinMs, scenario.latencyMaxMs);
        final high = max(scenario.latencyMinMs, scenario.latencyMaxMs);
        final wait = low == high ? low : low + random.nextInt(high - low + 1);
        return MockDecision(latency: Duration(milliseconds: wait), label: '${scenario.label} ($wait ms)');
      case MockScenarioKind.flaky:
        final n = _counts.update(scope, (c) => c + 1, ifAbsent: () => 1);
        final fails = scenario.failEvery > 0 ? n % scenario.failEvery == 0 : random.nextInt(100) < scenario.failPercent;
        return fails ? MockDecision(failStatus: scenario.failStatus, label: '${scenario.label}: failed') : MockDecision(label: '${scenario.label}: passed');
    }
  }
}
