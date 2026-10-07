import 'dart:convert';
import 'dart:typed_data';
import 'package:postpilot/features/traffic_recorder/domain/entities/recorded_exchange.dart';

/// A recorded call with only what a test cares about. [id] doubles as the second at which it started, so ids give the order.
RecordedExchange exchange({
  int id = 1,
  String method = 'GET',
  String path = '/users',
  int status = 200,
  List<RecordedHeader> requestHeaders = const [],
  String? requestBody,
  List<RecordedHeader> responseHeaders = const [RecordedHeader('content-type', 'application/json')],
  String? responseBody,
  bool requestTruncated = false,
  RecordedKind kind = RecordedKind.proxied,
  String url = 'https://api.example.com',
  Uint8List? rawRequestBody,
  Uint8List? rawResponseBody,
  bool responseUndecoded = false,
  String? responseEncoding,
  String? error,
}) {
  final request = rawRequestBody ?? (requestBody == null ? null : Uint8List.fromList(utf8.encode(requestBody)));
  final response = rawResponseBody ?? (responseBody == null ? null : Uint8List.fromList(utf8.encode(responseBody)));
  return RecordedExchange(
    id: id,
    startedAt: DateTime.utc(2026, 10, 7, 12, 0, id),
    duration: const Duration(milliseconds: 120),
    method: method,
    url: '$url$path',
    path: path,
    status: status,
    statusMessage: const {200: 'OK', 201: 'Created', 204: 'No Content', 404: 'Not Found', 500: 'Internal Server Error'}[status] ?? 'Status',
    requestHeaders: requestHeaders,
    requestBody: request,
    requestBodySize: request?.length ?? 0,
    requestBodyTruncated: requestTruncated,
    responseHeaders: responseHeaders,
    responseBody: response,
    responseBodySize: response?.length ?? 0,
    responseUndecoded: responseUndecoded,
    responseEncoding: responseEncoding,
    error: error,
    kind: kind,
  );
}
