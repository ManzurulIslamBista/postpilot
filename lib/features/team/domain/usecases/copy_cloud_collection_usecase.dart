import '../../../../core/usecases/usecase.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../entities/cloud_folder_entity.dart';
import '../entities/cloud_request_entity.dart';
import '../services/cloud_request_mapper.dart';

final class CopyCloudCollectionParams {
  final String name;
  final List<CloudFolderEntity> folders;
  final List<CloudRequestEntity> requests;

  const CopyCloudCollectionParams({required this.name, required this.folders, required this.requests});
}

final class CopiedCollection {
  final int collectionId;
  final int folders;
  final int requests;

  const CopiedCollection({required this.collectionId, required this.folders, required this.requests});

  String get description => '${_plural(folders, 'folder')}, ${_plural(requests, 'request')}';

  static String _plural(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';
}

/// Copies a team collection into a brand-new local collection: the same
/// folders (nested as they are) and requests. Cloud requests carry no auth or
/// query params, so the copies have none of either. If anything fails midway
/// the half-built collection is deleted (the cascade removes its contents), so
/// a retry doesn't leave a duplicate next to it.
final class CopyCloudCollectionUseCase implements UseCase<CopiedCollection, CopyCloudCollectionParams> {
  final CollectionRepository _collectionRepository;
  final RequestRepository _requestRepository;

  const CopyCloudCollectionUseCase(this._collectionRepository, this._requestRepository);

  @override
  Future<CopiedCollection> call(CopyCloudCollectionParams params) async {
    final collectionId = await _collectionRepository.createCollection(params.name);
    try {
      final folderIds = await _copyFolders(collectionId, params.folders);
      for (final cloud in params.requests) {
        final folderId = cloud.folderId == null ? null : folderIds[cloud.folderId];
        final requestId = await _requestRepository.createRequest(collectionId: collectionId, folderId: folderId, name: cloud.name);
        await _requestRepository.saveRequest(
          CloudRequestMapper.toLocalIn(cloud, id: requestId, collectionId: collectionId, folderId: folderId),
        );
      }
      return CopiedCollection(collectionId: collectionId, folders: folderIds.length, requests: params.requests.length);
    } catch (_) {
      await _collectionRepository.deleteCollection(collectionId);
      rethrow;
    }
  }

  /// Creates [folders] parents-first and returns cloud id -> local id. A folder
  /// whose parent isn't among [folders] goes to the top level.
  Future<Map<int, int>> _copyFolders(int collectionId, List<CloudFolderEntity> folders) async {
    final knownIds = {for (final f in folders) f.id};
    final created = <int, int>{};
    var pending = [...folders];
    while (pending.isNotEmpty) {
      final blocked = <CloudFolderEntity>[];
      for (final folder in pending) {
        final parent = folder.parentFolderId;
        if (parent != null && knownIds.contains(parent) && !created.containsKey(parent)) {
          blocked.add(folder);
        } else {
          created[folder.id] = await _collectionRepository.createFolder(
            collectionId: collectionId,
            parentFolderId: parent == null ? null : created[parent],
            name: folder.name,
          );
        }
      }
      if (blocked.length == pending.length) {
        // A parent cycle no folder can start: flatten what is left to the top level.
        for (final folder in blocked) {
          created[folder.id] = await _collectionRepository.createFolder(collectionId: collectionId, name: folder.name);
        }
        break;
      }
      pending = blocked;
    }
    return created;
  }
}
