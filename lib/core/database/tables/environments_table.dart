import 'package:drift/drift.dart';

class Environments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
}

class EnvironmentVariables extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get environmentId => integer().references(Environments, #id, onDelete: KeyAction.cascade)();
  TextColumn get key => text()();
  TextColumn get value => text().withDefault(const Constant(''))();
  BoolColumn get isSecret => boolean().withDefault(const Constant(false))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();
}
