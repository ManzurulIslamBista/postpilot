import 'package:drift/drift.dart';
import 'requests_table.dart';

/// The recorded 'known good' shape of a request's response (status, headers of interest, body schema and
/// stable values) that later responses are compared with. Local to this device, one row per request.
class RequestBaselines extends Table {
  IntColumn get requestId => integer().references(Requests, #id, onDelete: KeyAction.cascade)();
  TextColumn get snapshotJson => text().withDefault(const Constant('{}'))();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get recordedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {requestId};
}
