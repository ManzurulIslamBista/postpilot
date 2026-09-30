// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_dao.dart';

// ignore_for_file: type=lint
mixin _$SettingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SettingEntriesTable get settingEntries => attachedDatabase.settingEntries;
  SettingsDaoManager get managers => SettingsDaoManager(this);
}

class SettingsDaoManager {
  final _$SettingsDaoMixin _db;
  SettingsDaoManager(this._db);
  $$SettingEntriesTableTableManager get settingEntries =>
      $$SettingEntriesTableTableManager(
        _db.attachedDatabase,
        _db.settingEntries,
      );
}
