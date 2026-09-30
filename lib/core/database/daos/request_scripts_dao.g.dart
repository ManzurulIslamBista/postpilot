// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'request_scripts_dao.dart';

// ignore_for_file: type=lint
mixin _$RequestScriptsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CollectionsTable get collections => attachedDatabase.collections;
  $FoldersTable get folders => attachedDatabase.folders;
  $RequestsTable get requests => attachedDatabase.requests;
  $RequestScriptsTable get requestScripts => attachedDatabase.requestScripts;
  RequestScriptsDaoManager get managers => RequestScriptsDaoManager(this);
}

class RequestScriptsDaoManager {
  final _$RequestScriptsDaoMixin _db;
  RequestScriptsDaoManager(this._db);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db.attachedDatabase, _db.collections);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db.attachedDatabase, _db.folders);
  $$RequestsTableTableManager get requests =>
      $$RequestsTableTableManager(_db.attachedDatabase, _db.requests);
  $$RequestScriptsTableTableManager get requestScripts =>
      $$RequestScriptsTableTableManager(
        _db.attachedDatabase,
        _db.requestScripts,
      );
}
