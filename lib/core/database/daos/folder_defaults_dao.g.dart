// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'folder_defaults_dao.dart';

// ignore_for_file: type=lint
mixin _$FolderDefaultsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CollectionsTable get collections => attachedDatabase.collections;
  $FoldersTable get folders => attachedDatabase.folders;
  $FolderDefaultsTable get folderDefaults => attachedDatabase.folderDefaults;
  FolderDefaultsDaoManager get managers => FolderDefaultsDaoManager(this);
}

class FolderDefaultsDaoManager {
  final _$FolderDefaultsDaoMixin _db;
  FolderDefaultsDaoManager(this._db);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db.attachedDatabase, _db.collections);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db.attachedDatabase, _db.folders);
  $$FolderDefaultsTableTableManager get folderDefaults =>
      $$FolderDefaultsTableTableManager(
        _db.attachedDatabase,
        _db.folderDefaults,
      );
}
