import '../../../../core/database/daos/collections_dao.dart';
import '../../domain/entities/collection_entity.dart';
import '../../domain/repositories/collection_repository.dart';

final class CollectionRepositoryImpl implements CollectionRepository {
  final CollectionsDao _dao;
  const CollectionRepositoryImpl(this._dao);

  @override
  Stream<List<CollectionEntity>> watchCollections() =>
      _dao.watchAllCollections().map((rows) => rows.map((r) => CollectionEntity(id: r.id, name: r.name)).toList());

  @override
  Future<int> createCollection(String name) => _dao.createCollection(name);

  @override
  Future<void> renameCollection(int id, String name) => _dao.renameCollection(id, name);

  @override
  Future<void> deleteCollection(int id) => _dao.deleteCollection(id);

  @override
  Stream<List<FolderEntity>> watchFolders(int collectionId) => _dao.watchFolders(collectionId).map(
        (rows) => rows
            .map((r) => FolderEntity(
                  id: r.id,
                  collectionId: r.collectionId,
                  parentFolderId: r.parentFolderId,
                  name: r.name,
                  orderIndex: r.orderIndex,
                ))
            .toList(),
      );

  @override
  Future<int> createFolder({required int collectionId, int? parentFolderId, required String name}) =>
      _dao.createFolder(collectionId: collectionId, parentFolderId: parentFolderId, name: name);

  @override
  Future<void> renameFolder(int id, String name) => _dao.renameFolder(id, name);

  @override
  Future<void> deleteFolder(int id) => _dao.deleteFolder(id);

  @override
  Future<int> duplicateCollection(int id) => _dao.duplicateCollection(id);

  @override
  Future<int> duplicateFolder(int id) => _dao.duplicateFolder(id);

  @override
  Future<int> duplicateRequest(int id) => _dao.duplicateRequest(id);
}
