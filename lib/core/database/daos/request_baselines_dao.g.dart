// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'request_baselines_dao.dart';

// ignore_for_file: type=lint
mixin _$RequestBaselinesDaoMixin on DatabaseAccessor<AppDatabase> {
  $CollectionsTable get collections => attachedDatabase.collections;
  $FoldersTable get folders => attachedDatabase.folders;
  $RequestsTable get requests => attachedDatabase.requests;
  $RequestBaselinesTable get requestBaselines =>
      attachedDatabase.requestBaselines;
  RequestBaselinesDaoManager get managers => RequestBaselinesDaoManager(this);
}

class RequestBaselinesDaoManager {
  final _$RequestBaselinesDaoMixin _db;
  RequestBaselinesDaoManager(this._db);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db.attachedDatabase, _db.collections);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db.attachedDatabase, _db.folders);
  $$RequestsTableTableManager get requests =>
      $$RequestsTableTableManager(_db.attachedDatabase, _db.requests);
  $$RequestBaselinesTableTableManager get requestBaselines =>
      $$RequestBaselinesTableTableManager(
        _db.attachedDatabase,
        _db.requestBaselines,
      );
}
