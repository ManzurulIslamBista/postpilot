import 'package:drift/drift.dart';
import 'collections_table.dart';

/// One finished collection run (from the app or the CLI), kept on this device only so failures can be
/// grouped, compared with earlier runs and re-run. Never part of workspace.json or Git. The JSON columns
/// hold masked, size-capped text.
class RunRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get collectionId => integer().references(Collections, #id, onDelete: KeyAction.cascade)();
  TextColumn get environmentName => text().withDefault(const Constant(''))();

  /// 'app' or 'cli'.
  TextColumn get source => text().withDefault(const Constant('app'))();
  IntColumn get passed => integer().withDefault(const Constant(0))();
  IntColumn get failed => integer().withDefault(const Constant(0))();
  IntColumn get skipped => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get summaryJson => text().withDefault(const Constant('{}'))();

  /// Per request/iteration results (name, method, url template, status, assertion messages, duration).
  TextColumn get resultsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
}
