import 'api_client.dart';
import 'api_http_response.dart';

/// Told about every request that passes through [LoggingApiClient]: first as
/// it is sent, so a request still in flight can be shown, then again through
/// the returned [ApiCallCompletion] when it ends. Defined here rather than
/// depending on the console feature directly so `core/network` stays free of
/// feature imports.
abstract interface class ApiCallObserver {
  ApiCallCompletion onSend(ApiRequestSpec spec, {required DateTime sentAt});
}

/// How one call announced to [ApiCallObserver.onSend] ended.
final class ApiCallCompletion {
  final void Function(ApiHttpResponse response) onResponse;
  final void Function(Object error, Duration elapsed) onError;

  const ApiCallCompletion({required this.onResponse, required this.onError});
}

/// Wraps another [ApiClient], reports each send to an [ApiCallObserver], and
/// otherwise behaves exactly like the wrapped client — responses and errors
/// pass through untouched.
final class LoggingApiClient implements ApiClient {
  final ApiClient _inner;
  final ApiCallObserver _observer;

  const LoggingApiClient(this._inner, this._observer);

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    final call = _observer.onSend(spec, sentAt: DateTime.now());
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _inner.send(spec);
      call.onResponse(response);
      return response;
    } catch (error) {
      call.onError(error, stopwatch.elapsed);
      rethrow;
    }
  }
}
