// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'global_variables_dao.dart';

// ignore_for_file: type=lint
mixin _$GlobalVariablesDaoMixin on DatabaseAccessor<AppDatabase> {
  $GlobalVariablesTable get globalVariables => attachedDatabase.globalVariables;
  GlobalVariablesDaoManager get managers => GlobalVariablesDaoManager(this);
}

class GlobalVariablesDaoManager {
  final _$GlobalVariablesDaoMixin _db;
  GlobalVariablesDaoManager(this._db);
  $$GlobalVariablesTableTableManager get globalVariables =>
      $$GlobalVariablesTableTableManager(
        _db.attachedDatabase,
        _db.globalVariables,
      );
}
