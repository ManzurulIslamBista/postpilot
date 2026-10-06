final class CollectionEntity {
  final int id;
  final String name;

  const CollectionEntity({required this.id, required this.name});
}

final class FolderEntity {
  final int id;
  final int collectionId;
  final int? parentFolderId;
  final String name;

  const FolderEntity({
    required this.id,
    required this.collectionId,
    required this.parentFolderId,
    required this.name,
  });
}
