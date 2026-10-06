import 'dart:convert';
import 'dart:typed_data';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';

/// A response with [body] (encoded as JSON unless it is a String, which is sent as written).
ApiResponseEntity response(
  Object? body, {
  int status = 200,
  int ms = 120,
  Map<String, String> headers = const {'Content-Type': 'application/json; charset=utf-8'},
  bool truncated = false,
}) =>
    ApiResponseEntity(
      statusCode: status,
      statusMessage: status == 200 ? 'OK' : '',
      headers: headers,
      bodyBytes: Uint8List.fromList(utf8.encode(body is String ? body : jsonEncode(body))),
      duration: Duration(milliseconds: ms),
      truncated: truncated,
    );

/// Four orders, nested and mixed: a page of orders with ids, a status that repeats, an optional note, money as
/// integers and decimals, a request id that is a 64-bit number, an empty array and a cursor.
Map<String, dynamic> ordersBody({int queueDepth = 12, String cursor = 'c2VhcmNoLWN1cnNvci0xMjM0NTY3ODkwYWJjZGVm', int requestId = 9007199254740993}) => {
      'data': {
        'orders': [
          {
            'id': 'b1f4c2a0-5e1d-4b8e-9d57-0a1b2c3d4e5f',
            'status': 'paid',
            'total': 19.99,
            'email': 'ann@example.com',
            'note': null,
            'created_at': '2026-10-06T09:15:30Z',
          },
          {
            'id': '7c9e6679-7425-40de-944b-e07fc1f90ae7',
            'status': 'paid',
            'total': 5,
            'email': 'bob@example.com',
            'note': 'gift',
            'created_at': '2026-10-06T09:16:30Z',
          },
          {
            'id': '16fd2706-8baf-433b-82eb-8c7fada847da',
            'status': 'shipped',
            'total': 42.5,
            'email': 'cy@example.com',
            'note': null,
            'created_at': '2026-10-05T10:00:00Z',
          },
          {
            'id': '886313e1-3b8a-5372-9b90-0c9aee199e5d',
            'status': 'paid',
            'total': 7,
            'email': 'di@example.com',
            'note': null,
            'created_at': '2026-10-04T10:00:00Z',
          },
        ],
        'page': 1,
        'next_cursor': cursor,
      },
      'currency': 'USD',
      'queueDepth': queueDepth,
      'requestId': requestId,
      'ok': true,
      'tags': <Object?>[],
    };
