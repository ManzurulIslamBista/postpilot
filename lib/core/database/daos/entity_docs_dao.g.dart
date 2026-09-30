// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entity_docs_dao.dart';

// ignore_for_file: type=lint
mixin _$EntityDocsDaoMixin on DatabaseAccessor<AppDatabase> {
  $EntityDocsTable get entityDocs => attachedDatabase.entityDocs;
  EntityDocsDaoManager get managers => EntityDocsDaoManager(this);
}

class EntityDocsDaoManager {
  final _$EntityDocsDaoMixin _db;
  EntityDocsDaoManager(this._db);
  $$EntityDocsTableTableManager get entityDocs =>
      $$EntityDocsTableTableManager(_db.attachedDatabase, _db.entityDocs);
}
