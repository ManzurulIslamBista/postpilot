// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_records_dao.dart';

// ignore_for_file: type=lint
mixin _$RunRecordsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CollectionsTable get collections => attachedDatabase.collections;
  $RunRecordsTable get runRecords => attachedDatabase.runRecords;
  RunRecordsDaoManager get managers => RunRecordsDaoManager(this);
}

class RunRecordsDaoManager {
  final _$RunRecordsDaoMixin _db;
  RunRecordsDaoManager(this._db);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db.attachedDatabase, _db.collections);
  $$RunRecordsTableTableManager get runRecords =>
      $$RunRecordsTableTableManager(_db.attachedDatabase, _db.runRecords);
}
