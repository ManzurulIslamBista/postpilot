// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collection_defaults_dao.dart';

// ignore_for_file: type=lint
mixin _$CollectionDefaultsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CollectionsTable get collections => attachedDatabase.collections;
  $CollectionDefaultsTable get collectionDefaults =>
      attachedDatabase.collectionDefaults;
  CollectionDefaultsDaoManager get managers =>
      CollectionDefaultsDaoManager(this);
}

class CollectionDefaultsDaoManager {
  final _$CollectionDefaultsDaoMixin _db;
  CollectionDefaultsDaoManager(this._db);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db.attachedDatabase, _db.collections);
  $$CollectionDefaultsTableTableManager get collectionDefaults =>
      $$CollectionDefaultsTableTableManager(
        _db.attachedDatabase,
        _db.collectionDefaults,
      );
}
