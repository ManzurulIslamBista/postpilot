import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../domain/services/mock_routes.dart';
import 'mock_server_engine.dart';

bool get isMockServerSupported => true;

MockServerEngine createMockServerEngine() => _IoMockServerEngine();

final class _IoMockServerEngine implements MockServerEngine {
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  MockRouteTable _table = const MockRouteTable([], []);
  MockServerConfig _config = const MockServerConfig();
  final _log = StreamController<MockLogEntry>.broadcast();

  /// Headers that describe how the original body travelled, not the text stored in the example.
  static const _skipHeaders = {'content-length', 'transfer-encoding', 'connection', 'content-encoding', 'keep-alive', 'date', 'server', 'set-cookie'};

  @override
  bool get isRunning => _server != null;

  @override
  int? get port => _server?.port;

  @override
  Stream<MockLogEntry> get log => _log.stream;

  @override
  void updateRoutes(MockRouteTable table) => _table = table;

  @override
  Future<void> start(MockServerConfig config, MockRouteTable table) async {
    if (_server != null) await stop();
    _config = config;
    _table = table;
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
    await _server?.close(force: true);
    _server = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _log.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final started = DateTime.now();
    final response = request.response;
    final method = request.method.toUpperCase();
    final path = request.uri.path;
    if (_config.cors) _cors(request, response);
    int status;
    String? routeLabel;
    try {
      if (method == 'OPTIONS' && _config.cors) {
        status = 204;
        response.statusCode = status;
      } else {
        final route = _table.match(method, path);
        if (_config.delay > Duration.zero) await Future<void>.delayed(_config.delay);
        if (route == null) {
          final others = _table.methodsFor(path);
          status = others.isEmpty ? 404 : 405;
          response
            ..statusCode = status
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'error': others.isEmpty ? 'No mock for $method $path' : '$method is not mocked for $path',
              if (others.isNotEmpty) 'mockedMethods': others,
              'routes': [for (final r in _table.routes) '${r.method} ${r.path}'],
            }));
        } else {
          status = route.status;
          routeLabel = '${route.method} ${route.path}';
          response.statusCode = status;
          route.headers.forEach((k, v) {
            if (!_skipHeaders.contains(k.toLowerCase())) {
              try {
                response.headers.set(k, v);
              } catch (_) {
                // A header value Dart refuses (a stray control character) is dropped, not fatal.
              }
            }
          });
          // dart:io pre-fills text/plain, so ask the example rather than the response.
          if (!route.headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
            response.headers.contentType = _looksJson(route.body) ? ContentType.json : ContentType.text;
          }
          response.headers.set('x-mock-server', 'postpilot');
          response.add(utf8.encode(route.body));
        }
      }
    } catch (_) {
      status = 500;
      try {
        response.statusCode = status;
      } catch (_) {}
    }
    await response.close();
    _log.add(MockLogEntry(
      at: started,
      method: method,
      path: request.uri.hasQuery ? '$path?${request.uri.query}' : path,
      status: status,
      route: routeLabel,
      duration: DateTime.now().difference(started),
    ));
  }

  void _cors(HttpRequest request, HttpResponse response) {
    response.headers
      ..set('access-control-allow-origin', request.headers.value('origin') ?? '*')
      ..set('access-control-allow-methods', 'GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS')
      ..set('access-control-allow-headers', request.headers.value('access-control-request-headers') ?? '*')
      ..set('access-control-max-age', '600');
  }

  bool _looksJson(String body) {
    final t = body.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }
}
