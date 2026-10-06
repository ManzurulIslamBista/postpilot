import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../../core/errors/app_exception.dart';
import '../../device_helper/domain/services/device_targets.dart';
import '../data/mock_server_engine.dart';
import '../domain/services/mock_backend.dart';
import '../domain/services/mock_cors.dart';
import '../domain/services/mock_example_handler.dart';
import '../domain/services/mock_http.dart';
import '../domain/services/mock_pagination.dart';
import '../domain/services/mock_routes.dart';
import '../domain/services/mock_scenarios.dart';
import '../domain/services/mock_spec.dart';
import '../domain/services/mock_spec_handler.dart';
import '../domain/usecases/build_mock_routes_usecase.dart';

/// Where the server's answers come from.
enum MockSourceKind {
  examples('Saved examples'),
  openApi('OpenAPI document');

  const MockSourceKind(this.label);

  final String label;
}

/// One address the running server can be reached at, for a kind of device.
final class MockBaseUrl {
  final String label;
  final String url;
  final String note;
  const MockBaseUrl(this.label, this.url, this.note);
}

/// The mock server as the app sees it: one instance for the whole session, so
/// it keeps answering after its dialog is closed and the top bar can show that
/// it is running.
final class MockServerViewModel with ChangeNotifier {
  static const _logLimit = 300;

  final BuildMockRoutesUseCase _build;
  final MockServerEngine Function() _createEngine;
  MockServerEngine? _engine;
  StreamSubscription<MockLogEntry>? _logSub;

  /// What answers requests; it lives as long as this model, so scenarios and rules set before the server starts apply to it.
  final MockBackend backend;

  /// [clock] and [random] replace the real time and chance, so a test sees a "slow" or "flaky" scenario without waiting
  /// or luck. [createEngine] replaces the socket engine in tests.
  MockServerViewModel(
    this._build, {
    MockClock? clock,
    Random? random,
    MockServerEngine Function()? createEngine,
  })  : backend = MockBackend(clock: clock ?? const SystemMockClock(), random: random),
        _createEngine = createEngine ?? MockServerEngine.create;

  bool get isSupported => MockServerEngine.isSupported;
  bool get isRunning => _engine?.isRunning ?? false;
  int? get port => _engine?.port;

  int? collectionId;
  String portText = '3001';
  bool allowOtherDevices = false;
  bool cors = true;

  /// Who may read the answers from a browser when [cors] is on: `*` or origins.
  String allowedOrigin = MockCors.any;
  int delayMs = 0;

  /// True while CORS lets any website read the answers (the default), which the dialog says out loud.
  bool get allowsEveryWebsite => cors && (MockCors.parse(allowedOrigin)?.contains(MockCors.any) ?? false);

  MockRouteTable table = const MockRouteTable([], []);
  final List<MockLogEntry> log = [];
  String? error;
  bool isBusy = false;

  int get requestCount => log.length;

  // --- what answers ---------------------------------------------------------------------------

  MockSourceKind source = MockSourceKind.examples;

  /// The OpenAPI document as the user gave it, and what was made of it.
  String specText = '';
  MockSpec? spec;
  String? specError;
  MockSpecHandler? specHandler;

  /// How the document is served: the seed of the fake data, the items each collection starts with, the paging style, and
  /// whether requests are checked against the operation.
  int seed = 1;
  int seedCount = 10;
  MockPaginationStrategy pagination = MockPaginationStrategy.auto;
  bool validateRequests = true;

  /// The routes the server answers now, from whichever source is in use.
  List<MockRouteInfo> get routes {
    if (source == MockSourceKind.openApi) return specHandler?.routes ?? const [];
    return backend.examples.routes;
  }

  /// Switches the source; a running server follows at once.
  void useSource(MockSourceKind kind) {
    source = kind;
    _applySource();
    notifyListeners();
  }

  void _applySource() {
    backend.spec = source == MockSourceKind.openApi ? specHandler : null;
  }

  /// Reads [text] (OpenAPI 3 or Swagger 2, JSON or YAML). A document that cannot be read leaves the one in use as it was.
  void loadSpec(String text) {
    specText = text;
    specError = null;
    if (text.trim().isEmpty) {
      notifyListeners();
      return;
    }
    try {
      final parsed = MockSpec.parse(text);
      spec = parsed;
      specHandler = _newHandler(parsed);
      _applySource();
    } on ImportException catch (e) {
      specError = 'That is not an OpenAPI or Swagger document: ${e.message}';
    } catch (e) {
      specError = "Couldn't read that document: $e";
    }
    notifyListeners();
  }

  MockSpecHandler _newHandler(MockSpec spec) =>
      MockSpecHandler(spec, seed: seed, seedCount: seedCount, pagination: pagination, validateRequests: validateRequests);

  /// Changes how the document is served. The data starts again, because it was made with the old settings.
  void updateSpecOptions({int? seed, int? seedCount, MockPaginationStrategy? pagination, bool? validate}) {
    this.seed = seed ?? this.seed;
    this.seedCount = (seedCount ?? this.seedCount).clamp(0, 500);
    this.pagination = pagination ?? this.pagination;
    validateRequests = validate ?? validateRequests;
    final current = spec;
    if (current != null) {
      specHandler = _newHandler(current);
      _applySource();
    }
    notifyListeners();
  }

  /// Puts every resource back to its starting data (created, changed and deleted items are forgotten).
  void resetData() {
    specHandler?.resetData();
    notifyListeners();
  }

  // --- scenarios and rules -----------------------------------------------------------------------

  MockScenarios get scenarios => backend.scenarios;

  void setGlobalScenario(MockScenario scenario) {
    scenarios.setGlobal(scenario);
    notifyListeners();
  }

  /// A scenario for one route (`GET /users/:id`); null takes the route back to the global one.
  void setRouteScenario(String routeKey, MockScenario? scenario) {
    scenarios.setRoute(routeKey, scenario);
    notifyListeners();
  }

  void clearScenarios() {
    scenarios.clear();
    notifyListeners();
  }

  List<MockMatchRule> get rules => backend.rules;

  void setRules(List<MockMatchRule> rules) {
    backend.rules = List.unmodifiable(rules);
    notifyListeners();
  }

  // --- the server ---------------------------------------------------------------------------------

  void update({int? collection, String? port, bool? others, bool? corsOn, String? origin, int? delay}) {
    collectionId = collection ?? collectionId;
    portText = port ?? portText;
    allowOtherDevices = others ?? allowOtherDevices;
    cors = corsOn ?? cors;
    allowedOrigin = origin ?? allowedOrigin;
    delayMs = delay ?? delayMs;
    // The wait applies to the next request even while the server runs.
    backend.delay = Duration(milliseconds: delayMs);
    notifyListeners();
  }

  Future<void> start() async {
    final id = collectionId;
    if (isBusy || !isSupported) return;
    if (source == MockSourceKind.examples && id == null) return;
    final portNumber = int.tryParse(portText.trim());
    if (portNumber == null || portNumber < 1 || portNumber > 65535) {
      error = 'Enter a port between 1 and 65535.';
      notifyListeners();
      return;
    }
    if (cors && MockCors.parse(allowedOrigin) == null) {
      error = 'Allowed origin must be * or an origin such as http://localhost:5173 (separate several with commas).';
      notifyListeners();
      return;
    }
    if (source == MockSourceKind.openApi && specHandler == null) {
      error = 'Load an OpenAPI document first: paste it or open a file in the From OpenAPI tab.';
      notifyListeners();
      return;
    }
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      table = id == null ? const MockRouteTable([], []) : await _build(id);
      _applySource();
      final engine = _engine ??= _createEngine();
      await engine.start(
        MockServerConfig(
          port: portNumber,
          allowOtherDevices: allowOtherDevices,
          cors: cors,
          allowedOrigin: allowedOrigin.trim().isEmpty ? MockCors.any : allowedOrigin.trim(),
          delay: Duration(milliseconds: delayMs),
        ),
        table,
        backend: backend,
      );
      _logSub ??= engine.log.listen((e) {
        log.insert(0, e);
        if (log.length > _logLimit) log.removeLast();
        notifyListeners();
      });
    } catch (e) {
      error = e is StateError ? e.message : '$e';
    }
    isBusy = false;
    notifyListeners();
  }

  /// Re-reads the collection into the running server, so a new example is served without a restart.
  Future<void> reload() async {
    final id = collectionId;
    final engine = _engine;
    if (id == null || engine == null || !engine.isRunning) return;
    table = await _build(id);
    engine.updateRoutes(table);
    notifyListeners();
  }

  Future<void> stop() async {
    await _engine?.stop();
    notifyListeners();
  }

  void clearLog() {
    log.clear();
    notifyListeners();
  }

  /// The addresses the running server answers at, one per kind of device. [lanIp] is this computer's address on the local
  /// network, when known.
  List<MockBaseUrl> baseUrls({String? lanIp}) {
    final p = port;
    if (p == null) return const [];
    // `localhost` serves this computer, the iOS simulator and Flutter desktop and web alike; the emulators have their own alias for it.
    final urls = <MockBaseUrl>[
      MockBaseUrl('This computer, iOS simulator, Flutter desktop and web', 'http://localhost:$p', 'The simulator shares the Mac network, so localhost works.'),
    ];
    for (final target in DeviceTargets.forEmulators()) {
      if (target.host == 'localhost') continue;
      urls.add(MockBaseUrl(target.name, 'http://${target.host}:$p', target.note));
    }
    if (lanIp != null) {
      urls.add(MockBaseUrl(
        'Phone or tablet on the same Wi-Fi',
        'http://$lanIp:$p',
        allowOtherDevices
            ? 'Reachable from other devices on this network.'
            : 'Tick "Allow other devices" and restart the server first: it listens on this computer only.',
      ));
    }
    return urls;
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _engine?.dispose();
    super.dispose();
  }
}
