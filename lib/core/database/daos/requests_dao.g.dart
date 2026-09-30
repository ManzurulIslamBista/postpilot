// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'requests_dao.dart';

// ignore_for_file: type=lint
mixin _$RequestsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CollectionsTable get collections => attachedDatabase.collections;
  $FoldersTable get folders => attachedDatabase.folders;
  $RequestsTable get requests => attachedDatabase.requests;
  RequestsDaoManager get managers => RequestsDaoManager(this);
}

class RequestsDaoManager {
  final _$RequestsDaoMixin _db;
  RequestsDaoManager(this._db);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db.attachedDatabase, _db.collections);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db.attachedDatabase, _db.folders);
  $$RequestsTableTableManager get requests =>
      $$RequestsTableTableManager(_db.attachedDatabase, _db.requests);
}
