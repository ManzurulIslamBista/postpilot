// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entity_uids_dao.dart';

// ignore_for_file: type=lint
mixin _$EntityUidsDaoMixin on DatabaseAccessor<AppDatabase> {
  $EntityUidsTable get entityUids => attachedDatabase.entityUids;
  EntityUidsDaoManager get managers => EntityUidsDaoManager(this);
}

class EntityUidsDaoManager {
  final _$EntityUidsDaoMixin _db;
  EntityUidsDaoManager(this._db);
  $$EntityUidsTableTableManager get entityUids =>
      $$EntityUidsTableTableManager(_db.attachedDatabase, _db.entityUids);
}
