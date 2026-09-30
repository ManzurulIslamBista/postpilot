// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'response_examples_dao.dart';

// ignore_for_file: type=lint
mixin _$ResponseExamplesDaoMixin on DatabaseAccessor<AppDatabase> {
  $CollectionsTable get collections => attachedDatabase.collections;
  $FoldersTable get folders => attachedDatabase.folders;
  $RequestsTable get requests => attachedDatabase.requests;
  $ResponseExamplesTable get responseExamples =>
      attachedDatabase.responseExamples;
  ResponseExamplesDaoManager get managers => ResponseExamplesDaoManager(this);
}

class ResponseExamplesDaoManager {
  final _$ResponseExamplesDaoMixin _db;
  ResponseExamplesDaoManager(this._db);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db.attachedDatabase, _db.collections);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db.attachedDatabase, _db.folders);
  $$RequestsTableTableManager get requests =>
      $$RequestsTableTableManager(_db.attachedDatabase, _db.requests);
  $$ResponseExamplesTableTableManager get responseExamples =>
      $$ResponseExamplesTableTableManager(
        _db.attachedDatabase,
        _db.responseExamples,
      );
}
