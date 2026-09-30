import 'package:drift/drift.dart';

class HistoryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get requestId => integer().nullable()();
  TextColumn get method => text()();
  TextColumn get url => text()();
  IntColumn get statusCode => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get responseHeadersJson => text().withDefault(const Constant('{}'))();
  Column<Uint8List> get responseBody => blob().nullable()();
  DateTimeColumn get sentAt => dateTime().withDefault(currentDateAndTime)();
}
