// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'environments_dao.dart';

// ignore_for_file: type=lint
mixin _$EnvironmentsDaoMixin on DatabaseAccessor<AppDatabase> {
  $EnvironmentsTable get environments => attachedDatabase.environments;
  $EnvironmentVariablesTable get environmentVariables =>
      attachedDatabase.environmentVariables;
  EnvironmentsDaoManager get managers => EnvironmentsDaoManager(this);
}

class EnvironmentsDaoManager {
  final _$EnvironmentsDaoMixin _db;
  EnvironmentsDaoManager(this._db);
  $$EnvironmentsTableTableManager get environments =>
      $$EnvironmentsTableTableManager(_db.attachedDatabase, _db.environments);
  $$EnvironmentVariablesTableTableManager get environmentVariables =>
      $$EnvironmentVariablesTableTableManager(
        _db.attachedDatabase,
        _db.environmentVariables,
      );
}
