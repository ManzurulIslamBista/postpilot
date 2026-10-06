import '../../../../core/enums/http_method.dart';
import 'key_value_item.dart';
import 'request_auth.dart';
import 'request_body.dart';

final class ApiRequestEntity {
  final int id;
  final int collectionId;
  final int? folderId;
  final String name;
  final HttpMethod method;
  final String url;
  final List<KeyValueItem> headers;
  final List<KeyValueItem> queryParams;
  final RequestBody body;
  final RequestAuth auth;

  const ApiRequestEntity({
    required this.id,
    required this.collectionId,
    required this.folderId,
    required this.name,
    required this.method,
    required this.url,
    required this.headers,
    required this.queryParams,
    required this.body,
    required this.auth,
  });

  ApiRequestEntity copyWith({
    String? name,
    HttpMethod? method,
    String? url,
    List<KeyValueItem>? headers,
    List<KeyValueItem>? queryParams,
    RequestBody? body,
    RequestAuth? auth,
  }) =>
      ApiRequestEntity(
        id: id,
        collectionId: collectionId,
        folderId: folderId,
        name: name ?? this.name,
        method: method ?? this.method,
        url: url ?? this.url,
        headers: headers ?? this.headers,
        queryParams: queryParams ?? this.queryParams,
        body: body ?? this.body,
        auth: auth ?? this.auth,
      );
}

final class RequestSummaryEntity {
  final int id;
  final int? folderId;
  final String name;
  final HttpMethod method;

  const RequestSummaryEntity({required this.id, required this.folderId, required this.name, required this.method});
}
