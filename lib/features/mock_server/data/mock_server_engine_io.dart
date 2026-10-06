import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../domain/services/mock_backend.dart';
import '../domain/services/mock_cors.dart';
import '../domain/services/mock_http.dart';
import '../domain/services/mock_log.dart';
import '../domain/services/mock_routes.dart';
import 'mock_server_engine.dart';

bool get isMockServerSupported => true;

MockServerEngine createMockServerEngine() => _IoMockServerEngine();

/// The socket side of the mock server: it reads a request into a [MockRequest], asks the [MockBackend] what to do, and
/// writes that down. Routing, scenarios and every answer are the backend's.
final class _IoMockServerEngine implements MockServerEngine {
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  MockBackend? _backend;
  MockServerConfig _config = const MockServerConfig();

  /// A body larger than this is refused: a mock has no use for megabytes of upload.
  static const _maxBody = 1024 * 1024;

  /// [MockServerConfig.allowedOrigin] read once. An origin that cannot be read allows nobody.
  List<String> _allowedOrigins = const [MockCors.any];
  final _log = StreamController<MockLogEntry>.broadcast();

  @override
  bool get isRunning => _server != null;

  @override
  int? get port => _server?.port;

  @override
  Stream<MockLogEntry> get log => _log.stream;

  @override
  MockBackend? get backend => _backend;

  @override
  void updateRoutes(MockRouteTable table) => _backend?.table = table;

  @override
  Future<void> start(MockServerConfig config, MockRouteTable table, {MockBackend? backend}) async {
    if (_server != null) await stop();
    _config = config;
    _allowedOrigins = MockCors.parse(config.allowedOrigin) ?? const [];
    final answering = backend ?? _backend ?? MockBackend();
    answering
      ..table = table
      ..delay = config.delay;
    _backend = answering;
    try {
      _server = await HttpServer.bind(config.allowOtherDevices ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4, config.port);
    } on SocketException catch (e) {
      // A bind failure on a chosen port is nearly always "in use" or "not allowed" (the OS error
      // codes differ per system and are not always set), so say that instead of the raw message.
      throw StateError(
        config.port != 0
            ? 'Port ${config.port} is already in use or not allowed. Choose another port.'
            : "Couldn't start the server: ${e.message}",
      );
    }
    _subscription = _server!.listen(_handle, onError: (Object _) {});
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    // `force` also drops the connections a timeout scenario left open.
    await _server?.close(force: true);
    _server = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _log.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final received = DateTime.now();
    final response = request.response;
    final method = request.method.toUpperCase();
    final backend = _backend!;
    final target = request.uri.hasQuery ? '${request.uri.path}?${request.uri.query}' : request.uri.path;
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(', '));

    var status = 500;
    String? route;
    String? scenario;
    var requestBody = '';
    var responseBody = '';
    try {
      final body = await _readBody(request);
      requestBody = body.text;
      if (_config.cors) _cors(request, response);
      if (body.tooLarge) {
        status = 413;
        response
          ..statusCode = status
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'The request body is larger than ${_maxBody ~/ 1024 ~/ 1024} MB.'}));
      } else if (method == 'OPTIONS' && _config.cors) {
        // A browser's CORS preflight: always allowed (the headers say who may read what), never subject to a scenario.
        status = 204;
        response.statusCode = status;
      } else {
        final outcome = await backend.handle(MockRequest(
          method: method,
          path: request.uri.path,
          query: request.uri.queryParametersAll,
          headers: headers,
          body: body.text,
        ));
        route = outcome.route;
        scenario = outcome.scenario;
        final answer = outcome.response;
        if (answer == null) {
          // The timeout scenario: the connection stays open and nothing is written until the caller gives up
          // or the server stops.
          status = 0;
          _record(received, method, target, status, route, scenario, headers, requestBody, '');
          return;
        }
        status = answer.status;
        responseBody = answer.body;
        response.statusCode = status;
        answer.headers.forEach((name, value) {
          try {
            response.headers.set(name, value);
          } catch (_) {
            // A header value Dart refuses (a stray control character) is dropped, not fatal.
          }
        });
        // Last of the headers an answer can carry, so nothing in it can undo the mock's CORS setting.
        if (_config.cors) _cors(request, response);
        if (!outcome.headOnly && method != 'HEAD') response.add(utf8.encode(answer.body));
      }
    } catch (_) {
      status = 500;
      try {
        response.statusCode = status;
      } catch (_) {}
    }
    try {
      await response.close();
    } catch (_) {
      // The caller went away before the answer was written.
    }
    _record(received, method, target, status, route, scenario, headers, requestBody, responseBody);
  }

  void _record(
    DateTime received,
    String method,
    String target,
    int status,
    String? route,
    String? scenario,
    Map<String, String> headers,
    String requestBody,
    String responseBody,
  ) {
    if (_log.isClosed) return;
    _log.add(MockLogEntry(
      at: received,
      method: method,
      path: MockLogMasking.target(target),
      status: status,
      route: route,
      duration: DateTime.now().difference(received),
      scenario: scenario,
      requestHeaders: MockLogMasking.headers(headers),
      requestBody: MockLogMasking.body(requestBody),
      responseBody: MockLogMasking.body(responseBody),
    ));
  }

  Future<({String text, bool tooLarge})> _readBody(HttpRequest request) async {
    final bytes = BytesBuilder(copy: false);
    var tooLarge = false;
    await for (final chunk in request) {
      if (tooLarge) continue;
      bytes.add(chunk);
      if (bytes.length > _maxBody) tooLarge = true;
    }
    return (text: tooLarge ? '' : utf8.decode(bytes.takeBytes(), allowMalformed: true), tooLarge: tooLarge);
  }

  void _cors(HttpRequest request, HttpResponse response) {
    final headers = response.headers;
    final origin = request.headers.value('origin');
    if (_allowedOrigins.contains(MockCors.any)) {
      headers.set('access-control-allow-origin', '*');
    } else {
      // A named origin is answered by echoing it, and only when the caller is that origin: any other
      // page gets no permission and the browser keeps the response from it.
      headers.set('vary', 'origin');
      if (origin == null || !MockCors.allows(_allowedOrigins, origin)) return;
      headers.set('access-control-allow-origin', origin);
    }
    headers
      ..set('access-control-allow-methods', 'GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS')
      ..set('access-control-allow-headers', request.headers.value('access-control-request-headers') ?? '*')
      ..set('access-control-max-age', '600');
  }
}
