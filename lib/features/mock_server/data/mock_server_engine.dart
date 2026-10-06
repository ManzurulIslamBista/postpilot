import 'mock_server_engine_stub.dart' if (dart.library.io) 'mock_server_engine_io.dart' as platform;
import '../domain/services/mock_backend.dart';
import '../domain/services/mock_cors.dart';
import '../domain/services/mock_log.dart';
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

/// One request the server answered (or, with status 0, one it was told never to answer).
///
/// Nothing in it is a credential: the address, the headers and both bodies were masked before the entry was made, so it can be
/// shown, copied or turned into a cURL command as it is.
final class MockLogEntry {
  final DateTime at;
  final String method;

  /// The path and query as received, with secret query values masked.
  final String path;
  final int status;

  /// The route that matched (`GET /users/:id`), null when none did.
  final String? route;
  final Duration duration;

  /// What the scenarios did to this request (`slow 200-800 ms (412 ms)`, `flaky (every 3rd, 500): failed`), null for nothing.
  final String? scenario;

  /// The request's headers (credentials masked, transport headers left out) and body (masked, cut).
  final Map<String, String> requestHeaders;
  final String requestBody;

  /// The answer's body, masked and cut.
  final String responseBody;

  const MockLogEntry({
    required this.at,
    required this.method,
    required this.path,
    required this.status,
    required this.route,
    required this.duration,
    this.scenario,
    this.requestHeaders = const {},
    this.requestBody = '',
    this.responseBody = '',
  });

  /// The server never answered this one (the timeout scenario).
  bool get neverAnswered => status == 0;

  /// One line of the body for a list row: what was sent, else what was answered.
  String get preview => MockLogMasking.preview(requestBody.isNotEmpty ? requestBody : responseBody);

  /// A cURL command that repeats this request against [baseUrl] (`http://localhost:3001`). Credentials stay masked.
  String toCurl(String baseUrl) => MockCurl.build(
        method: method,
        url: '${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path',
        headers: requestHeaders,
        body: requestBody,
      );
}

/// A local HTTP server (desktop and mobile only; a browser cannot listen).
abstract interface class MockServerEngine {
  static bool get isSupported => platform.isMockServerSupported;
  static MockServerEngine create() => platform.createMockServerEngine();

  bool get isRunning;
  int? get port;
  Stream<MockLogEntry> get log;

  /// What answers the requests of the running server (scenarios, the OpenAPI document and the saved examples can be changed
  /// on it while it runs); null before the first start.
  MockBackend? get backend;

  /// Starts answering from [table], or from [backend] when one is given (it then owns the routes, the scenarios and the
  /// clock; [table] is put into it). Throws a readable message when the port is taken.
  Future<void> start(MockServerConfig config, MockRouteTable table, {MockBackend? backend});
  Future<void> stop();

  /// Swaps the routes of a running server without restarting it.
  void updateRoutes(MockRouteTable table);
  Future<void> dispose();
}
