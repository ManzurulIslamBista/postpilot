import 'dart:convert';

/// One HTTP request as the mock server's logic sees it, free of any socket: the engine turns an
/// `HttpRequest` into this, so everything below it can be tested without a network.
final class MockRequest {
  /// Upper-case: `GET`.
  final String method;

  /// The path as sent, without the query string: `/users/42` (matching decodes each segment).
  final String path;

  /// Query parameters; a name sent twice has two values.
  final Map<String, List<String>> query;

  /// Header names in lower case.
  final Map<String, String> headers;
  final String body;

  MockRequest({
    required String method,
    required this.path,
    this.query = const {},
    Map<String, String> headers = const {},
    this.body = '',
  })  : method = method.toUpperCase(),
        headers = {for (final e in headers.entries) e.key.toLowerCase(): e.value};

  String? queryValue(String name) => query[name]?.firstOrNull;

  String? header(String name) => headers[name.toLowerCase()];

  Object? _json;
  bool _jsonRead = false;

  /// The body as JSON, or null when it is empty or not JSON (see [hasJsonBody]).
  Object? get bodyJson {
    if (!_jsonRead) {
      _jsonRead = true;
      try {
        _json = body.trim().isEmpty ? null : jsonDecode(body);
      } catch (_) {
        _json = null;
      }
    }
    return _json;
  }

  bool get hasBody => body.trim().isNotEmpty;

  /// A body that is present and is valid JSON.
  bool get hasJsonBody {
    if (!hasBody) return false;
    try {
      jsonDecode(body);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// `path?query` the way the caller would type it, for logs and the `Link` header.
  String get target {
    if (query.isEmpty) return path;
    final pairs = [
      for (final e in query.entries)
        for (final v in e.value) '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(v)}',
    ];
    return '$path?${pairs.join('&')}';
  }
}

/// What the server answers: status, headers and a text body.
final class MockResponse {
  final int status;

  /// Headers to send, as the mock decided them (CORS ones are the engine's).
  final Map<String, String> headers;
  final String body;

  const MockResponse(this.status, {this.headers = const {}, this.body = ''});

  /// A JSON answer.
  factory MockResponse.json(int status, Object? value, {Map<String, String> headers = const {}}) => MockResponse(
        status,
        headers: {'content-type': 'application/json', ...headers},
        body: jsonEncode(value),
      );

  MockResponse copyWith({int? status, Map<String, String>? headers, String? body}) =>
      MockResponse(status ?? this.status, headers: headers ?? this.headers, body: body ?? this.body);

  bool get isJson => headers.entries.any((e) => e.key.toLowerCase() == 'content-type' && e.value.toLowerCase().contains('json'));
}

/// How the engine must put an answer on the wire when the network is not perfect (see `MockNetwork`): paced, cut off, or
/// with a wrong Content-Length. Without one the answer is written as it is.
final class MockWire {
  /// The speed of the body in bytes per second; 0 writes it as fast as possible.
  final int bytesPerSecond;

  /// The share (0 to 1) of the body that is sent before the connection is dropped; null sends all of it.
  final double? truncateAt;

  /// Bytes the Content-Length header claims beyond the real body. The connection closes after the body, so the caller sees an
  /// answer that ends too early.
  final int declaredLengthExtra;

  const MockWire({this.bytesPerSecond = 0, this.truncateAt, this.declaredLengthExtra = 0});

  /// Whether the answer is cut short on purpose (the connection is dropped instead of closed in the normal way).
  bool get breaksTheBody => truncateAt != null || declaredLengthExtra > 0;
}

/// What the backend decided for a request: the answer, or none at all.
final class MockOutcome {
  /// Null when the server must never answer (the timeout scenario), or when the connection is to be dropped ([dropped]).
  final MockResponse? response;

  /// `GET /users/:id`, null when no route matched.
  final String? route;

  /// What was applied on top of the normal answer, for the log: `slow 200-800 ms`, `flaky (every 3rd)`, `401`.
  final String? scenario;

  /// Time from receiving the request to having the answer, by the backend's clock (delays included).
  final Duration elapsed;

  /// The request was a HEAD answered from the GET route: headers only, no body.
  final bool headOnly;

  /// What the network profile did to this request, for the log: `3G: +312 ms, 750 kbit/s`; null when none applied.
  final String? network;

  /// How to write the answer when the network is to affect it; null writes it plainly.
  final MockWire? wire;

  /// The connection is to be closed without an answer (offline, a lost connection, a flapping network that is down).
  final bool dropped;

  const MockOutcome({
    this.response,
    this.route,
    this.scenario,
    this.elapsed = Duration.zero,
    this.headOnly = false,
    this.network,
    this.wire,
    this.dropped = false,
  });

  bool get neverAnswers => response == null;
}

/// Time as the backend sees it. Tests replace it, so a "slow" scenario is checked without waiting.
abstract interface class MockClock {
  DateTime now();
  Future<void> delay(Duration duration);
}

final class SystemMockClock implements MockClock {
  const SystemMockClock();

  @override
  DateTime now() => DateTime.now();

  @override
  Future<void> delay(Duration duration) => Future<void>.delayed(duration);
}
