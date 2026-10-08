// Pure Dart plus a conditional import (like the recorder and the mock server): nothing here needs Flutter, so the command line
// can `import` this file, call `CorsProxyEngine.create().start(...)` and listen to `events`.
import '../domain/cors_proxy_protocol.dart';
import 'cors_proxy_engine_stub.dart' if (dart.library.io) 'cors_proxy_engine_io.dart' as platform;

export '../domain/cors_proxy_protocol.dart';

/// How the proxy listens and who may use it.
final class CorsProxyConfig {
  /// The secret every call but a preflight must carry.
  final String token;

  /// `127.0.0.1` (this computer only) or `0.0.0.0` (every network interface; see [listensOnAllInterfaces]).
  final String host;

  /// 0 picks a free port.
  final int port;

  /// Origins allowed besides the pages on this computer, as `CorsProxyOrigins.normalize` writes them.
  final List<String> allowedOrigins;

  /// Accept the TLS certificate of any server, also a self-signed or expired one.
  final bool insecure;

  /// How long to wait for a server to connect, and how long it may stay silent while answering.
  final Duration connectTimeout;
  final Duration timeout;

  const CorsProxyConfig({
    required this.token,
    this.host = loopbackHost,
    this.port = CorsProxyProtocol.defaultPort,
    this.allowedOrigins = const [],
    this.insecure = false,
    this.connectTimeout = const Duration(seconds: 15),
    this.timeout = const Duration(seconds: 60),
  });

  static const loopbackHost = '127.0.0.1';
  static const allInterfaces = '0.0.0.0';

  /// Reachable from other devices on the network, not only from this computer.
  bool get listensOnAllInterfaces => host == allInterfaces || host == '::';

  CorsProxyOrigins get origins => CorsProxyOrigins(allowedOrigins);

  /// A reason this configuration cannot be started, null when it can.
  String? get problem {
    if (port < 0 || port > 65535) return 'The port must be between 1 and 65535 (0 picks a free one).';
    return CorsProxyToken.problem(token) ?? (listensOnAllInterfaces ? CorsProxyToken.lanProblem(token) : null);
  }
}

/// One call the proxy handled, with nothing secret in it: the query of the address is masked and no header or body is kept.
final class CorsProxyEvent {
  final DateTime at;
  final String method;

  /// `host[:port]` of the target, or the proxy's own address for a call the proxy answered itself.
  final String host;

  /// The path of the target with its query masked.
  final String path;
  final int status;
  final Duration duration;

  /// What went wrong when the proxy refused the call or the server could not be reached; null for a forwarded call.
  final String? error;

  const CorsProxyEvent({
    required this.at,
    required this.method,
    required this.host,
    required this.path,
    required this.status,
    required this.duration,
    this.error,
  });

  /// `GET api.example.com/users?page=2 200 143 ms`: the one line that is printed and shown for a call.
  String get line => '$method $host$path $status ${duration.inMilliseconds} ms${error == null ? '' : '  [$error]'}';
}

/// A small reverse proxy for web pages: it forwards the call a page makes to the address named in `X-PostPilot-Url` and
/// answers with the CORS headers the target lacks. See [CorsProxyProtocol].
abstract interface class CorsProxyEngine {
  /// False in a browser, which cannot listen on a port.
  static bool get isSupported => platform.isCorsProxySupported;
  static CorsProxyEngine create() => platform.createCorsProxyEngine();

  bool get isRunning;

  /// The port it listens on (the real one when 0 was asked for); null when stopped.
  int? get port;

  /// What it was started with; null before the first start.
  CorsProxyConfig? get config;

  /// Every handled call, in the order they finished. A broadcast stream.
  Stream<CorsProxyEvent> get events;

  /// Starts listening. Throws a [StateError] with a readable message when the port is taken or the configuration is wrong.
  Future<void> start(CorsProxyConfig config);

  Future<void> stop();
  Future<void> dispose();
}
