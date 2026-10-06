import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/collections_table.dart';
import '../tables/folder_defaults_table.dart';

part 'folder_defaults_dao.g.dart';

@DriftAccessor(tables: [FolderDefaults, Folders])
class FolderDefaultsDao extends DatabaseAccessor<AppDatabase> with _$FolderDefaultsDaoMixin {
  FolderDefaultsDao(super.db);

  Future<FolderDefault?> findByFolder(int folderId) =>
      (select(folderDefaults)..where((t) => t.folderId.equals(folderId))).getSingleOrNull();

  Stream<FolderDefault?> watchByFolder(int folderId) =>
      (select(folderDefaults)..where((t) => t.folderId.equals(folderId))).watchSingleOrNull();

  /// Every folder default of [collectionId], for resolving what a request inherits in one read.
  Future<List<FolderDefault>> allForCollection(int collectionId) {
    final query = select(folderDefaults).join([innerJoin(folders, folders.id.equalsExp(folderDefaults.folderId))])
      ..where(folders.collectionId.equals(collectionId));
    return query.map((row) => row.readTable(folderDefaults)).get();
  }

  Future<void> upsert(FolderDefaultsCompanion row) => into(folderDefaults).insertOnConflictUpdate(row);

  Future<void> deleteForFolder(int folderId) =>
      (delete(folderDefaults)..where((t) => t.folderId.equals(folderId))).go();
}
