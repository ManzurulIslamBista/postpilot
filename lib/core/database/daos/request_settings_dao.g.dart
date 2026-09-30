// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'request_settings_dao.dart';

// ignore_for_file: type=lint
mixin _$RequestSettingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CollectionsTable get collections => attachedDatabase.collections;
  $FoldersTable get folders => attachedDatabase.folders;
  $RequestsTable get requests => attachedDatabase.requests;
  $RequestSettingEntriesTable get requestSettingEntries =>
      attachedDatabase.requestSettingEntries;
  RequestSettingsDaoManager get managers => RequestSettingsDaoManager(this);
}

class RequestSettingsDaoManager {
  final _$RequestSettingsDaoMixin _db;
  RequestSettingsDaoManager(this._db);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db.attachedDatabase, _db.collections);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db.attachedDatabase, _db.folders);
  $$RequestsTableTableManager get requests =>
      $$RequestsTableTableManager(_db.attachedDatabase, _db.requests);
  $$RequestSettingEntriesTableTableManager get requestSettingEntries =>
      $$RequestSettingEntriesTableTableManager(
        _db.attachedDatabase,
        _db.requestSettingEntries,
      );
}
