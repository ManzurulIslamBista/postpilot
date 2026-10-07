import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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

  /// Connections taken over from the HTTP server to write a throttled or broken answer by hand; stopping the server ends them.
  final Set<Socket> _wireSockets = {};

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
    // The server does not own a connection it handed over: a slow body must not keep running after Stop.
    for (final socket in _wireSockets.toList()) {
      socket.destroy();
    }
    _wireSockets.clear();
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
    String? network;
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
        network = outcome.network;
        final answer = outcome.response;
        if (answer == null) {
          // The timeout scenario: the connection stays open and nothing is written until the caller gives up
          // or the server stops. A network that drops the connection closes it at once instead.
          status = 0;
          if (outcome.dropped) await _drop(response);
          _record(received, method, target, status, route, scenario, headers, requestBody, '', network: network, dropped: outcome.dropped);
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
        final wire = outcome.wire;
        if (wire != null && !outcome.headOnly && method != 'HEAD') {
          // A throttled, cut-off or mislabelled answer is written by hand, so the pacing and the lie about its length are real.
          responseBody = await _writeOnWire(response, answer, wire, backend.clock);
          _record(received, method, target, status, route, scenario, headers, requestBody, responseBody, network: network);
          return;
        }
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
    _record(received, method, target, status, route, scenario, headers, requestBody, responseBody, network: network);
  }

  /// Closes the connection without a word, which a client sees as a connection error (no network, a reset).
  Future<void> _drop(HttpResponse response) async {
    try {
      final socket = await response.detachSocket(writeHeaders: false);
      socket.destroy();
    } catch (_) {
      // Already gone.
    }
  }

  /// Writes [answer] on the connection itself: the headers at once, then the body in paced slices ([MockWire.bytesPerSecond]),
  /// stopping early and dropping the connection when the wire says the body is cut off. The Content-Length header says what the
  /// whole body would be (plus [MockWire.declaredLengthExtra] when it lies), which is how a client notices a cut-off one.
  /// Returns the part of the body that was sent.
  Future<String> _writeOnWire(HttpResponse response, MockResponse answer, MockWire wire, MockClock clock) async {
    final bytes = utf8.encode(answer.body);
    final share = wire.truncateAt;
    // Cut at least one byte short of the whole, so "cut off" is always true.
    final int cut = share == null || bytes.isEmpty ? bytes.length : min(bytes.length - 1, (bytes.length * share).floor());
    response
      ..persistentConnection = false
      ..headers.set('content-length', '${bytes.length + wire.declaredLengthExtra}');
    final socket = await response.detachSocket();
    _wireSockets.add(socket);
    var finished = false;
    try {
      // The headers leave now, so a slow body starts after them and not together with them.
      await socket.flush();
      final rate = wire.bytesPerSecond;
      if (rate <= 0) {
        if (cut > 0) socket.add(bytes.sublist(0, cut));
        await socket.flush();
      } else {
        // Twenty slices a second; a link slower than twenty bytes a second sends one byte at a time, as often as it takes.
        final slice = max(1, rate ~/ 20);
        final pause = rate >= 20 ? const Duration(milliseconds: 50) : Duration(milliseconds: (1000 / rate).ceil());
        for (var at = 0; at < cut && _wireSockets.contains(socket); at += slice) {
          socket.add(bytes.sublist(at, min(cut, at + slice)));
          await socket.flush();
          await clock.delay(pause);
        }
      }
      finished = _wireSockets.contains(socket);
    } catch (_) {
      // The caller went away while the body was being written.
    } finally {
      _wireSockets.remove(socket);
      if (finished && !wire.breaksTheBody) {
        try {
          await socket.close();
        } catch (_) {}
      } else {
        socket.destroy();
      }
    }
    return utf8.decode(bytes.sublist(0, cut), allowMalformed: true);
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
    String responseBody, {
    String? network,
    bool dropped = false,
  }) {
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
      network: network,
      dropped: dropped,
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
