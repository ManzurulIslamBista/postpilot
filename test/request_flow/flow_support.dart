import 'dart:convert';
import 'dart:typed_data';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/request_spec_builder.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_report.dart';
import 'package:postpilot/features/request_flow/domain/services/flow_clock.dart';
import 'package:postpilot/features/request_flow/domain/services/flow_executor.dart';

/// Time that only moves when the engine waits: sleeping adds to the clock and is recorded, so a test sees every wait
/// without taking it.
final class FakeFlowClock implements FlowClock {
  DateTime time = DateTime.utc(2026, 1, 1, 12);
  final List<Duration> sleeps = [];

  @override
  DateTime now() => time;

  @override
  Future<void> sleep(Duration duration, {ApiCancelToken? cancel}) async {
    sleeps.add(duration);
    time = time.add(duration);
  }

  /// The waits, in milliseconds.
  List<int> get waits => [for (final d in sleeps) d.inMilliseconds];
}

ApiResponseEntity jsonResponse(
  Object? json, {
  int status = 200,
  Map<String, String> headers = const {},
  Duration duration = const Duration(milliseconds: 10),
}) =>
    textResponse(jsonEncode(json), status: status, headers: headers, duration: duration);

ApiResponseEntity textResponse(
  String body, {
  int status = 200,
  Map<String, String> headers = const {},
  Duration duration = const Duration(milliseconds: 10),
}) =>
    ApiResponseEntity(
      statusCode: status,
      statusMessage: status == 200 ? 'OK' : (status >= 500 ? 'Server Error' : ''),
      headers: headers,
      bodyBytes: Uint8List.fromList(utf8.encode(body)),
      duration: duration,
    );

ApiRequestEntity flowRequest({
  String url = 'https://api.test/items',
  HttpMethod method = HttpMethod.get,
  List<KeyValueItem> queryParams = const [],
  RequestBody body = const RequestBody(),
  int id = 1,
}) =>
    ApiRequestEntity(
      id: id,
      collectionId: 1,
      folderId: null,
      name: 'Items',
      method: method,
      url: url,
      headers: const [],
      queryParams: queryParams,
      body: body,
      auth: const RequestAuth(),
    );

RequestBody jsonBody(Object json) => RequestBody(type: BodyType.raw, rawText: jsonEncode(json));

/// A flow context over [variables], no cancel token, notes collected into [notes].
FlowContext flowContext({Map<String, String> variables = const {}, List<String>? notes, ApiCancelToken? cancel}) =>
    FlowContext(
      resolver: () async => VariableResolver(variables),
      onNote: notes?.add,
      cancelToken: cancel,
    );

/// A [FlowSend] that answers from [answer] and remembers what it was asked for, as the URL the request builder would
/// send (so a test reads page parameters the way the server would).
final class FakeServer {
  final FlowExchange Function(Uri url, ApiRequestEntity request, int call) answer;
  final List<ApiRequestEntity> requests = [];
  final List<Uri> urls = [];

  FakeServer(this.answer);

  /// The request as the server sees it.
  Future<FlowExchange> send(ApiRequestEntity request) async {
    final spec = const RequestSpecBuilder().build(request, VariableResolver(const {}));
    requests.add(request);
    final url = Uri.parse(spec.url);
    urls.add(url);
    return answer(url, request, requests.length);
  }

  /// The JSON body of the n-th request, as sent.
  Object? bodyOf(int index) => jsonBodyOf(requests[index]);

  /// The JSON body [request] is sent with.
  static Object? jsonBodyOf(ApiRequestEntity request) {
    final spec = const RequestSpecBuilder().build(request, VariableResolver(const {}));
    return jsonDecode(utf8.decode(spec.bodyBytes!));
  }
}

FlowExchange responded(ApiResponseEntity response) => FlowResponded(response);

FlowExchange failed([String summary = "Couldn't reach the server"]) => FlowFailed(StateError(summary), summary);
