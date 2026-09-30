import 'package:flutter/foundation.dart' show compute;
import '../../../../core/usecases/usecase.dart';
import '../../../collections/domain/entities/collection_variable_entity.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../services/openapi_parser.dart';

/// Recreates an OpenAPI 3.x / Swagger 2.0 document (JSON or YAML) as a
/// brand-new local collection, one folder per tag, with the document's server
/// stored once as the collection's `baseUrl` variable. Returns the new
/// collection's id.
final class ImportOpenApiUseCase implements UseCase<int, String> {
  final CollectionRepository _collectionRepository;
  final RequestRepository _requestRepository;
  final CollectionVariableRepository _collectionVariableRepository;

  const ImportOpenApiUseCase(this._collectionRepository, this._requestRepository, this._collectionVariableRepository);

  @override
  Future<int> call(String text) async {
    // Off the UI isolate: a multi-MB document would otherwise freeze the
    // window before the import spinner ever paints.
    final parsed = await compute(OpenApiParser.parse, text);
    final collectionId = await _collectionRepository.createCollection(parsed.name);
    try {
      if (parsed.baseUrl.isNotEmpty) {
        await _collectionVariableRepository.upsert(CollectionVariableEntity(
          id: 0,
          collectionId: collectionId,
          key: OpenApiParser.baseUrlVariable,
          value: parsed.baseUrl,
          enabled: true,
        ));
      }
      for (final request in parsed.rootRequests) {
        await _persist(request, collectionId, null);
      }
      for (final folder in parsed.folders) {
        final folderId = await _collectionRepository.createFolder(collectionId: collectionId, name: folder.name);
        for (final request in folder.requests) {
          await _persist(request, collectionId, folderId);
        }
      }
    } catch (_) {
      // A half-imported collection would sit in the sidebar and a retry would
      // create a duplicate next to it; the cascade removes its contents too.
      await _collectionRepository.deleteCollection(collectionId);
      rethrow;
    }
    return collectionId;
  }

  Future<void> _persist(OpenApiRequestItem item, int collectionId, int? folderId) async {
    final requestId = await _requestRepository.createRequest(collectionId: collectionId, folderId: folderId, name: item.name);
    await _requestRepository.saveRequest(ApiRequestEntity(
      id: requestId,
      collectionId: collectionId,
      folderId: folderId,
      name: item.name,
      method: item.method,
      url: item.url,
      headers: item.headers,
      queryParams: item.queryParams,
      body: item.body,
      auth: item.auth,
    ));
  }
}
