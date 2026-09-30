// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collection_variables_dao.dart';

// ignore_for_file: type=lint
mixin _$CollectionVariablesDaoMixin on DatabaseAccessor<AppDatabase> {
  $CollectionsTable get collections => attachedDatabase.collections;
  $CollectionVariablesTable get collectionVariables =>
      attachedDatabase.collectionVariables;
  CollectionVariablesDaoManager get managers =>
      CollectionVariablesDaoManager(this);
}

class CollectionVariablesDaoManager {
  final _$CollectionVariablesDaoMixin _db;
  CollectionVariablesDaoManager(this._db);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db.attachedDatabase, _db.collections);
  $$CollectionVariablesTableTableManager get collectionVariables =>
      $$CollectionVariablesTableTableManager(
        _db.attachedDatabase,
        _db.collectionVariables,
      );
}
