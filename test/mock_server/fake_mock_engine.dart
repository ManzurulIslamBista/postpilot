// A mock server engine with no socket: it records how it was started and lets a test push log entries, so the view model
// and the dialog can be tested without a port (and in widget tests, where real sockets are faked away).
import 'dart:async';
import 'package:postpilot/features/mock_server/data/mock_server_engine.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_backend.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_routes.dart';

final class FakeMockEngine implements MockServerEngine {
  bool _running = false;
  int? _port;
  MockBackend? _backend;
  final _log = StreamController<MockLogEntry>.broadcast();

  /// What the last start was given.
  MockServerConfig? config;
  MockRouteTable? table;
  int starts = 0;

  /// Set to make the next start fail like a taken port does.
  String? failWith;

  @override
  bool get isRunning => _running;

  @override
  int? get port => _running ? _port : null;

  @override
  Stream<MockLogEntry> get log => _log.stream;

  @override
  MockBackend? get backend => _backend;

  @override
  Future<void> start(MockServerConfig config, MockRouteTable table, {MockBackend? backend}) async {
    if (failWith != null) throw StateError(failWith!);
    this.config = config;
    this.table = table;
    starts++;
    _backend = (backend ?? _backend ?? MockBackend())
      ..table = table
      ..delay = config.delay;
    _port = config.port;
    _running = true;
  }

  @override
  Future<void> stop() async => _running = false;

  @override
  void updateRoutes(MockRouteTable table) {
    this.table = table;
    _backend?.table = table;
  }

  @override
  Future<void> dispose() async {
    _running = false;
    await _log.close();
  }

  /// A request the server "received".
  void emit(MockLogEntry entry) => _log.add(entry);
}
