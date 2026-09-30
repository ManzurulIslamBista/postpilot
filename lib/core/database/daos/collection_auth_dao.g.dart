// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collection_auth_dao.dart';

// ignore_for_file: type=lint
mixin _$CollectionAuthDaoMixin on DatabaseAccessor<AppDatabase> {
  $CollectionsTable get collections => attachedDatabase.collections;
  $CollectionAuthTable get collectionAuth => attachedDatabase.collectionAuth;
  CollectionAuthDaoManager get managers => CollectionAuthDaoManager(this);
}

class CollectionAuthDaoManager {
  final _$CollectionAuthDaoMixin _db;
  CollectionAuthDaoManager(this._db);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db.attachedDatabase, _db.collections);
  $$CollectionAuthTableTableManager get collectionAuth =>
      $$CollectionAuthTableTableManager(
        _db.attachedDatabase,
        _db.collectionAuth,
      );
}
