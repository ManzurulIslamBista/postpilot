// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_payloads_dao.dart';

// ignore_for_file: type=lint
mixin _$HistoryPayloadsDaoMixin on DatabaseAccessor<AppDatabase> {
  $HistoryEntriesTable get historyEntries => attachedDatabase.historyEntries;
  $HistoryPayloadsTable get historyPayloads => attachedDatabase.historyPayloads;
  HistoryPayloadsDaoManager get managers => HistoryPayloadsDaoManager(this);
}

class HistoryPayloadsDaoManager {
  final _$HistoryPayloadsDaoMixin _db;
  HistoryPayloadsDaoManager(this._db);
  $$HistoryEntriesTableTableManager get historyEntries =>
      $$HistoryEntriesTableTableManager(
        _db.attachedDatabase,
        _db.historyEntries,
      );
  $$HistoryPayloadsTableTableManager get historyPayloads =>
      $$HistoryPayloadsTableTableManager(
        _db.attachedDatabase,
        _db.historyPayloads,
      );
}
