import 'package:drift/drift.dart';

/// Key-value app settings. Named `SettingEntries` so its row class does not
/// clash with a domain `AppSettings`.
class SettingEntries extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
