import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/mock_server_engine.dart';
import '../domain/services/mock_cors.dart';
import '../domain/services/mock_routes.dart';
import '../domain/usecases/build_mock_routes_usecase.dart';

/// The mock server as the app sees it: one instance for the whole session, so
/// it keeps answering after its dialog is closed and the top bar can show that
/// it is running.
final class MockServerViewModel with ChangeNotifier {
  static const _logLimit = 300;

  final BuildMockRoutesUseCase _build;
  MockServerEngine? _engine;
  StreamSubscription<MockLogEntry>? _logSub;

  MockServerViewModel(this._build);

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

  void update({int? collection, String? port, bool? others, bool? corsOn, String? origin, int? delay}) {
    collectionId = collection ?? collectionId;
    portText = port ?? portText;
    allowOtherDevices = others ?? allowOtherDevices;
    cors = corsOn ?? cors;
    allowedOrigin = origin ?? allowedOrigin;
    delayMs = delay ?? delayMs;
    notifyListeners();
  }

  Future<void> start() async {
    final id = collectionId;
    if (id == null || isBusy || !isSupported) return;
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
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      table = await _build(id);
      final engine = _engine ??= MockServerEngine.create();
      await engine.start(
        MockServerConfig(
          port: portNumber,
          allowOtherDevices: allowOtherDevices,
          cors: cors,
          allowedOrigin: allowedOrigin.trim().isEmpty ? MockCors.any : allowedOrigin.trim(),
          delay: Duration(milliseconds: delayMs),
        ),
        table,
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

  @override
  void dispose() {
    _logSub?.cancel();
    _engine?.dispose();
    super.dispose();
  }
}
