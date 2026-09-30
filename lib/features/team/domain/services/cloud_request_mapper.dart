import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/entities/request_body.dart';
import '../entities/cloud_request_entity.dart';

abstract final class CloudRequestMapper {
  static const _contentType = 'Content-Type';

  /// The request-builder shape of [cloud], ready to be saved into a local
  /// collection (`id` and `collectionId` are placeholders until then). Auth is
  /// left on inherit so the local collection's auth and variables apply.
  static ApiRequestEntity toLocal(CloudRequestEntity cloud) => ApiRequestEntity(
        id: 0,
        collectionId: 0,
        folderId: null,
        name: cloud.name,
        method: HttpMethod.fromString(cloud.method),
        url: cloud.url,
        headers: cloud.headers,
        queryParams: const [],
        body: cloud.body.isEmpty ? RequestBody.empty : RequestBody(type: BodyType.raw, rawText: cloud.body),
        auth: const RequestAuth(),
      );

  /// [cloud] as the Send button runs it, without saving it anywhere. It belongs
  /// to no local collection (id 0, collection 0), so no collection variables or
  /// collection auth apply — only globals and the active environment do — and
  /// auth is explicitly none, since a cloud request carries no auth of its own.
  ///
  /// A cloud request has one raw-text body and no content-type choice, so the
  /// type is read from the text (JSON, XML, HTML, else plain text) rather than
  /// always claiming JSON. A `Content-Type` header written in another case
  /// (`content-type`) is renamed to the exact spelling the request sender looks
  /// for, or the sender would add a second, conflicting header.
  static ApiRequestEntity toSendable(CloudRequestEntity cloud) {
    final local = toLocal(cloud);
    return ApiRequestEntity(
      id: 0,
      collectionId: 0,
      folderId: null,
      name: local.name,
      method: local.method,
      url: local.url,
      headers: [
        for (final h in local.headers)
          h.key.toLowerCase() == _contentType.toLowerCase() ? h.copyWith(key: _contentType) : h,
      ],
      queryParams: const [],
      body: _withSniffedType(local.body),
      auth: RequestAuth.none,
    );
  }

  /// [cloud] as a new request [id] in local collection [collectionId] (under
  /// [folderId], or at the top level when null). Auth stays on inherit, so the
  /// new collection's own auth applies once the user sets one.
  static ApiRequestEntity toLocalIn(CloudRequestEntity cloud, {required int id, required int collectionId, int? folderId}) {
    final local = toLocal(cloud);
    return ApiRequestEntity(
      id: id,
      collectionId: collectionId,
      folderId: folderId,
      name: local.name,
      method: local.method,
      url: local.url,
      headers: local.headers,
      queryParams: local.queryParams,
      body: _withSniffedType(local.body),
      auth: local.auth,
    );
  }

  static RequestBody _withSniffedType(RequestBody body) =>
      body.type == BodyType.none ? body : body.copyWith(rawContentType: _sniff(body.rawText));

  static RawContentType _sniff(String text) {
    final head = text.trimLeft().toLowerCase();
    if (head.startsWith('{') || head.startsWith('[')) return RawContentType.json;
    if (head.startsWith('<!doctype html') || head.startsWith('<html')) return RawContentType.html;
    if (head.startsWith('<')) return RawContentType.xml;
    return RawContentType.text;
  }
}
