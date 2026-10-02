import 'package:flutter/foundation.dart' show compute;
import '../../../../core/usecases/usecase.dart';
import '../../../collections/domain/entities/collection_variable_entity.dart';
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../../request_builder/domain/services/importers/postman_collection_parser.dart';
import '../services/import_names.dart';

/// Recreates an entire Postman collection export (folders, requests,
/// collection variables and collection auth) inside a brand-new local
/// collection. Returns the new collection's id. If saving fails midway the
/// half-built collection is deleted again, so a retry doesn't add a duplicate.
final class ImportPostmanCollectionUseCase implements UseCase<int, String> {
  final CollectionRepository _collectionRepository;
  final RequestRepository _requestRepository;
  final CollectionVariableRepository _collectionVariableRepository;
  final CollectionAuthRepository _collectionAuthRepository;

  const ImportPostmanCollectionUseCase(
    this._collectionRepository,
    this._requestRepository,
    this._collectionVariableRepository,
    this._collectionAuthRepository,
  );

  @override
  Future<int> call(String json) async {
    // Off the UI isolate: a multi-MB collection would otherwise freeze the
    // window before the import spinner ever paints. The BOM some editors and
    // exporters prepend is not JSON (the format detector already ignores it).
    final parsed = await compute(PostmanCollectionParser.parse, json.replaceFirst('﻿', '').trim());
    final collectionId = await _collectionRepository.createCollection(parsed.name);
    try {
      final auth = parsed.auth;
      if (auth != null) await _collectionAuthRepository.setAuthJson(collectionId, auth.toJsonString());
      for (final variable in parsed.variables) {
        await _collectionVariableRepository.upsert(CollectionVariableEntity(
          id: 0,
          collectionId: collectionId,
          key: variable.key,
          value: variable.value,
          enabled: variable.enabled,
        ));
      }
      for (final item in parsed.items) {
        await _persist(item, collectionId, null);
      }
    } catch (_) {
      // The cascade removes the collection's contents too. Best effort: the
      // original failure is what the user needs to see.
      try {
        await _collectionRepository.deleteCollection(collectionId);
      } catch (_) {}
      rethrow;
    }
    return collectionId;
  }

  Future<void> _persist(PostmanItem item, int collectionId, int? folderId) async {
    switch (item) {
      case PostmanFolderItem():
        final newFolderId =
            await _collectionRepository.createFolder(collectionId: collectionId, parentFolderId: folderId, name: ImportNames.folder(item.name));
        for (final child in item.children) {
          await _persist(child, collectionId, newFolderId);
        }
      case PostmanRequestItem():
        final requestId =
            await _requestRepository.createRequest(collectionId: collectionId, folderId: folderId, name: item.name);
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
}
