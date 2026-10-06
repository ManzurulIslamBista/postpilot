import 'mock_http.dart';

/// One route as the dialog lists it and the scenarios address it.
final class MockRouteInfo {
  /// `GET /users/:id`: the same text everywhere (route list, scenarios, request log).
  final String key;
  final String method;
  final String path;

  /// Where the answer comes from: the request's name, or the operation's summary.
  final String title;

  /// The status the normal answer has, when it is known before a request comes in.
  final int? status;

  /// Extra words for the list: `stateful`, `2 examples`.
  final String note;

  const MockRouteInfo({required this.key, required this.method, required this.path, required this.title, this.status, this.note = ''});
}

/// A request matched to a route.
final class MockMatch {
  /// The route's key, see [MockRouteInfo.key].
  final String key;

  /// What the path parameters were in this request (`id` to `42`).
  final Map<String, String> pathParams;

  /// The handler's own object for the route.
  final Object route;

  const MockMatch({required this.key, required this.pathParams, required this.route});
}

/// What answers the requests: the saved examples of a collection, or an OpenAPI document. The backend asks it to
/// match a request and to build the normal answer; scenarios and the log are applied around it.
abstract interface class MockHandler {
  List<MockRouteInfo> get routes;

  /// The route for [method] and [path] (no query string), or null.
  MockMatch? match(String method, String path);

  /// The methods the server answers for [path], to tell "wrong method" (405) from "nothing there" (404).
  List<String> methodsFor(String path);

  /// The normal answer for a matched request.
  MockResponse respond(MockMatch match, MockRequest request);

  /// What an error answer of [status] looks like for [match] (null for no route): a saved example with that status, or the
  /// error shape the spec declares. Null lets the backend use its plain `{"error": ...}` body.
  MockResponse? errorResponse(MockMatch? match, MockRequest request, int status, String message);
}

/// The reason phrase of an HTTP status, for error bodies.
String mockReasonPhrase(int status) => switch (status) {
      400 => 'Bad Request',
      401 => 'Unauthorized',
      403 => 'Forbidden',
      404 => 'Not Found',
      405 => 'Method Not Allowed',
      408 => 'Request Timeout',
      409 => 'Conflict',
      413 => 'Payload Too Large',
      422 => 'Unprocessable Entity',
      429 => 'Too Many Requests',
      500 => 'Internal Server Error',
      502 => 'Bad Gateway',
      503 => 'Service Unavailable',
      504 => 'Gateway Timeout',
      _ => status >= 500 ? 'Server Error' : (status >= 400 ? 'Error' : 'OK'),
    };
