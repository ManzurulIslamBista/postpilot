// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entity_tags_dao.dart';

// ignore_for_file: type=lint
mixin _$EntityTagsDaoMixin on DatabaseAccessor<AppDatabase> {
  $EntityTagsTable get entityTags => attachedDatabase.entityTags;
  EntityTagsDaoManager get managers => EntityTagsDaoManager(this);
}

class EntityTagsDaoManager {
  final _$EntityTagsDaoMixin _db;
  EntityTagsDaoManager(this._db);
  $$EntityTagsTableTableManager get entityTags =>
      $$EntityTagsTableTableManager(_db.attachedDatabase, _db.entityTags);
}
