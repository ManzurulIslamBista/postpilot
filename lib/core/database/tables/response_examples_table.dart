import 'package:drift/drift.dart';
import 'requests_table.dart';

@TableIndex(name: 'response_examples_request_id', columns: {#requestId})
class ResponseExamples extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get requestId => integer().references(Requests, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  IntColumn get statusCode => integer()();
  TextColumn get headersJson => text().withDefault(const Constant('{}'))();
  TextColumn get body => text().withDefault(const Constant(''))();
  DateTimeColumn get savedAt => dateTime().withDefault(currentDateAndTime)();
}
