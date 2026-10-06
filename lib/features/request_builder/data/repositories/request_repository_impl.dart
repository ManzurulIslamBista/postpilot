import 'package:drift/drift.dart' show Value;
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/requests_dao.dart';
import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../domain/entities/api_request_entity.dart';
import '../../domain/entities/request_body.dart';
import '../../domain/repositories/request_repository.dart';
import '../models/request_json_codec.dart';

final class RequestRepositoryImpl implements RequestRepository {
  final RequestsDao _dao;
  const RequestRepositoryImpl(this._dao);

  @override
  Stream<List<RequestSummaryEntity>> watchByCollection(int collectionId) => _dao.watchByCollection(collectionId).map(
        (rows) => rows
            .map((r) => RequestSummaryEntity(
                  id: r.id,
                  folderId: r.folderId,
                  name: r.name,
                  method: HttpMethod.fromString(r.method),
                ))
            .toList(),
      );

  @override
  Stream<ApiRequestEntity?> watchById(int id) => _dao.watchById(id).map((r) => r == null ? null : _toEntity(r));

  @override
  Future<ApiRequestEntity?> findById(int id) async {
    final row = await _dao.findById(id);
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<int> createRequest({required int collectionId, int? folderId, required String name}) => _dao.createRequest(
        RequestsCompanion.insert(
          collectionId: collectionId,
          folderId: Value(folderId),
          name: name,
        ),
      );

  @override
  Future<void> saveRequest(ApiRequestEntity request) => _dao.updateRequest(
        request.id,
        RequestsCompanion(
          name: Value(request.name),
          method: Value(request.method.name),
          url: Value(request.url),
          headersJson: Value(RequestJsonCodec.encodeKeyValues(request.headers)),
          queryParamsJson: Value(RequestJsonCodec.encodeKeyValues(request.queryParams)),
          bodyType: Value(request.body.type.name),
          rawContentType: Value(request.body.rawContentType.name),
          bodyText: Value(request.body.rawText),
          formFieldsJson: Value(RequestJsonCodec.encodeKeyValues(request.body.formFields)),
          urlEncodedFieldsJson: Value(RequestJsonCodec.encodeKeyValues(request.body.urlEncodedFields)),
          graphqlQuery: Value(request.body.graphqlQuery),
          graphqlVariables: Value(request.body.graphqlVariables),
          authType: Value(request.auth.type.name),
          authConfigJson: Value(RequestJsonCodec.encodeAuth(request.auth)),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> deleteRequest(int id) => _dao.deleteRequest(id);

  ApiRequestEntity _toEntity(Request r) => ApiRequestEntity(
        id: r.id,
        collectionId: r.collectionId,
        folderId: r.folderId,
        name: r.name,
        method: HttpMethod.fromString(r.method),
        url: r.url,
        headers: RequestJsonCodec.decodeKeyValues(r.headersJson),
        queryParams: RequestJsonCodec.decodeKeyValues(r.queryParamsJson),
        body: RequestBody(
          type: BodyType.values.firstWhere((t) => t.name == r.bodyType, orElse: () => BodyType.none),
          rawContentType:
              RawContentType.values.firstWhere((t) => t.name == r.rawContentType, orElse: () => RawContentType.json),
          rawText: r.bodyText,
          formFields: RequestJsonCodec.decodeKeyValues(r.formFieldsJson),
          urlEncodedFields: RequestJsonCodec.decodeKeyValues(r.urlEncodedFieldsJson),
          graphqlQuery: r.graphqlQuery,
          graphqlVariables: r.graphqlVariables,
        ),
        auth: RequestJsonCodec.decodeAuth(r.authType, r.authConfigJson),
      );
}
