import '../../../collections/domain/entities/collection_variable_entity.dart';
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../entities/imported_collection.dart';
import 'import_names.dart';

/// What [ImportedCollectionWriter] created.
final class WrittenCollection {
  final int collectionId;
  final int folders;
  final int requests;
  const WrittenCollection({required this.collectionId, required this.folders, required this.requests});
}

/// Persists an [ImportedCollection] tree through the collection, request,
/// variable and auth repositories.
final class ImportedCollectionWriter {
  final CollectionRepository _collectionRepository;
  final RequestRepository _requestRepository;
  final CollectionVariableRepository _collectionVariableRepository;
  final CollectionAuthRepository _collectionAuthRepository;

  const ImportedCollectionWriter(
    this._collectionRepository,
    this._requestRepository,
    this._collectionVariableRepository,
    this._collectionAuthRepository,
  );

  /// Creates a brand-new collection. If anything fails midway the half-built
  /// collection is deleted (the cascade removes its contents), so a retry
  /// doesn't leave a duplicate next to it.
  Future<WrittenCollection> write(ImportedCollection collection) async {
    final collectionId = await _collectionRepository.createCollection(collection.name);
    try {
      final auth = collection.auth;
      if (auth != null) await _collectionAuthRepository.setAuthJson(collectionId, auth.toJsonString());
      for (final variable in collection.variables) {
        await _collectionVariableRepository.upsert(CollectionVariableEntity(
          id: 0,
          collectionId: collectionId,
          key: variable.key,
          value: variable.value,
          enabled: variable.enabled,
        ));
      }
      await addItems(collectionId, null, collection.items);
    } catch (_) {
      await _collectionRepository.deleteCollection(collectionId);
      rethrow;
    }
    return WrittenCollection(
      collectionId: collectionId,
      folders: collection.folderCount,
      requests: collection.requestCount,
    );
  }

  /// Adds [items] to an existing collection, under [folderId] (null = top level).
  Future<void> addItems(int collectionId, int? folderId, List<ImportedItem> items) async {
    for (final item in items) {
      switch (item) {
        case ImportedFolder():
          final newFolderId = await _collectionRepository.createFolder(
            collectionId: collectionId,
            parentFolderId: folderId,
            name: ImportNames.folder(item.name),
          );
          await addItems(collectionId, newFolderId, item.children);
        case ImportedRequest():
          final requestId = await _requestRepository.createRequest(
            collectionId: collectionId,
            folderId: folderId,
            name: item.name,
          );
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
}
