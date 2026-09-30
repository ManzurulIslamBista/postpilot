import '../../../request_builder/domain/entities/key_value_item.dart';

/// A cloud collection's request. This is a deliberately simplified
/// counterpart to the local `ApiRequestEntity` (request_builder feature) —
/// a single raw-text body and no auth/query-param editing, per the MVP scope
/// for shared collections. [folderId] is `null` for requests at the
/// collection root.
final class CloudRequestEntity {
  final int id;
  final int collectionId;
  final int? folderId;
  final String name;
  final String method;
  final String url;
  final List<KeyValueItem> headers;
  final String body;
  final DateTime updatedAt;

  const CloudRequestEntity({
    required this.id,
    required this.collectionId,
    required this.folderId,
    required this.name,
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
    required this.updatedAt,
  });

  CloudRequestEntity copyWith({
    String? name,
    String? method,
    String? url,
    List<KeyValueItem>? headers,
    String? body,
  }) =>
      CloudRequestEntity(
        id: id,
        collectionId: collectionId,
        folderId: folderId,
        name: name ?? this.name,
        method: method ?? this.method,
        url: url ?? this.url,
        headers: headers ?? this.headers,
        body: body ?? this.body,
        updatedAt: updatedAt,
      );
}
