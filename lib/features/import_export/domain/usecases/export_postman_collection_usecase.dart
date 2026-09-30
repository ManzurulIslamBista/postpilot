import '../../../../core/errors/app_exception.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../../request_builder/domain/services/importers/postman_collection_exporter.dart';

/// Serializes one local collection to Postman Collection v2.1 JSON.
final class ExportPostmanCollectionUseCase implements UseCase<String, int> {
  final CollectionRepository _collectionRepository;
  final RequestRepository _requestRepository;
  final CollectionVariableRepository _collectionVariableRepository;
  final CollectionAuthRepository _collectionAuthRepository;

  const ExportPostmanCollectionUseCase(
    this._collectionRepository,
    this._requestRepository,
    this._collectionVariableRepository,
    this._collectionAuthRepository,
  );

  @override
  Future<String> call(int collectionId) async {
    final collections = await _collectionRepository.watchCollections().first;
    final collection = collections.where((c) => c.id == collectionId).firstOrNull;
    if (collection == null) throw const NotFoundException('Collection not found.');

    final folders = await _collectionRepository.watchFolders(collectionId).first;
    final summaries = await _requestRepository.watchByCollection(collectionId).first;

    final requests = <ApiRequestEntity>[];
    for (final summary in summaries) {
      final full = await _requestRepository.findById(summary.id);
      if (full != null) requests.add(full);
    }

    final variables = await _collectionVariableRepository.watchByCollection(collectionId).first;
    final collectionAuth = RequestAuth.fromJsonString(await _collectionAuthRepository.getAuthJson(collectionId));

    return PostmanCollectionExporter.export(
      collectionName: collection.name,
      folders: folders,
      requests: requests,
      variables: variables,
      collectionAuth: collectionAuth,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
