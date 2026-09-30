import '../entities/collection_entity.dart';

abstract interface class CollectionRepository {
  Stream<List<CollectionEntity>> watchCollections();
  Future<int> createCollection(String name);
  Future<void> renameCollection(int id, String name);
  Future<void> deleteCollection(int id);

  Stream<List<FolderEntity>> watchFolders(int collectionId);
  Future<int> createFolder({required int collectionId, int? parentFolderId, required String name});
  Future<void> renameFolder(int id, String name);
  Future<void> deleteFolder(int id);

  Future<int> duplicateCollection(int id);
  Future<int> duplicateFolder(int id);
  Future<int> duplicateRequest(int id);
}
