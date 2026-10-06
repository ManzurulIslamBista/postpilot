import '../../../../core/errors/app_exception.dart';
import '../../../collections/domain/entities/collection_entity.dart';
import '../../../collections/domain/entities/collection_variable_entity.dart';
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';

/// One local collection with everything a whole-collection export needs.
final class LoadedCollection {
  final CollectionEntity collection;
  final List<FolderEntity> folders;
  final List<ApiRequestEntity> requests;
  final List<CollectionVariableEntity> variables;

  /// Null when the collection has no default auth (or it can't be read).
  final RequestAuth? auth;

  const LoadedCollection({
    required this.collection,
    required this.folders,
    required this.requests,
    required this.variables,
    required this.auth,
  });
}

/// Reads whole collections through the repositories, for the exports that
/// need a collection's folders, full requests, variables and auth at once.
final class CollectionLoader {
  final CollectionRepository _collectionRepository;
  final RequestRepository _requestRepository;
  final CollectionVariableRepository _collectionVariableRepository;
  final CollectionAuthRepository _collectionAuthRepository;

  const CollectionLoader(
    this._collectionRepository,
    this._requestRepository,
    this._collectionVariableRepository,
    this._collectionAuthRepository,
  );

  Future<LoadedCollection> load(int collectionId) async {
    final collections = await _collectionRepository.watchCollections().first;
    for (final collection in collections) {
      if (collection.id == collectionId) return _load(collection);
    }
    throw const NotFoundException('Collection not found.');
  }

  Future<List<LoadedCollection>> loadAll() async {
    final collections = await _collectionRepository.watchCollections().first;
    return [for (final collection in collections) await _load(collection)];
  }

  Future<LoadedCollection> _load(CollectionEntity collection) async {
    final folders = await _collectionRepository.watchFolders(collection.id).first;
    final summaries = await _requestRepository.watchByCollection(collection.id).first;
    final requests = <ApiRequestEntity>[];
    for (final summary in summaries) {
      final full = await _requestRepository.findById(summary.id);
      if (full != null) requests.add(full);
    }
    return LoadedCollection(
      collection: collection,
      folders: folders,
      requests: requests,
      variables: await _collectionVariableRepository.watchByCollection(collection.id).first,
      auth: _decodeAuth(await _collectionAuthRepository.getAuthJson(collection.id)),
    );
  }

  /// A corrupt stored value must not make the whole export fail.
  RequestAuth? _decodeAuth(String? json) {
    try {
      return RequestAuth.fromJsonString(json);
    } catch (_) {
      return null;
    }
  }
}
