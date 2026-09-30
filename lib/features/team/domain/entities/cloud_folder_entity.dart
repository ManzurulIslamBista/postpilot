/// A folder inside a cloud collection (`cloud_folders`). Folders nest via
/// [parentFolderId] (`null` = directly under the collection root).
final class CloudFolderEntity {
  final int id;
  final int collectionId;
  final int? parentFolderId;
  final String name;

  const CloudFolderEntity({
    required this.id,
    required this.collectionId,
    required this.parentFolderId,
    required this.name,
  });
}
