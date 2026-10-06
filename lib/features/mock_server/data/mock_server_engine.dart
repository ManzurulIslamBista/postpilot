import 'mock_server_engine_stub.dart' if (dart.library.io) 'mock_server_engine_io.dart' as platform;
import '../domain/services/mock_cors.dart';
import '../domain/services/mock_routes.dart';

final class MockServerConfig {
  final int port;

  /// Listen on every network interface so a phone or emulator can reach it.
  final bool allowOtherDevices;
  final bool cors;

  /// With [cors]: the origin allowed to read the answers from a browser, `*` for any
  /// website, or several origins separated by commas. See [MockCors].
  final String allowedOrigin;
  final Duration delay;

  const MockServerConfig({
    this.port = 3001,
    this.allowOtherDevices = false,
    this.cors = true,
    this.allowedOrigin = MockCors.any,
    this.delay = Duration.zero,
  });
}

/// One request the server answered.
final class MockLogEntry {
  final DateTime at;
  final String method;
  final String path;
  final int status;
  final String? route;
  final Duration duration;

  const MockLogEntry({required this.at, required this.method, required this.path, required this.status, required this.route, required this.duration});
}

/// A local HTTP server (desktop and mobile only; a browser cannot listen).
abstract interface class MockServerEngine {
  static bool get isSupported => platform.isMockServerSupported;
  static MockServerEngine create() => platform.createMockServerEngine();

  bool get isRunning;
  int? get port;
  Stream<MockLogEntry> get log;

  /// Starts answering from [table]. Throws a readable message when the port is taken.
  Future<void> start(MockServerConfig config, MockRouteTable table);
  Future<void> stop();

  /// Swaps the routes of a running server without restarting it.
  void updateRoutes(MockRouteTable table);
  Future<void> dispose();
}
