import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/request_baselines_table.dart';

part 'request_baselines_dao.g.dart';

@DriftAccessor(tables: [RequestBaselines])
class RequestBaselinesDao extends DatabaseAccessor<AppDatabase> with _$RequestBaselinesDaoMixin {
  RequestBaselinesDao(super.db);

  Future<RequestBaseline?> findByRequest(int requestId) =>
      (select(requestBaselines)..where((t) => t.requestId.equals(requestId))).getSingleOrNull();

  Stream<RequestBaseline?> watchByRequest(int requestId) =>
      (select(requestBaselines)..where((t) => t.requestId.equals(requestId))).watchSingleOrNull();

  /// Every baseline on this device, for "Export baselines…".
  Future<List<RequestBaseline>> all() => select(requestBaselines).get();

  Future<void> upsert(RequestBaselinesCompanion row) => into(requestBaselines).insertOnConflictUpdate(row);

  Future<void> deleteForRequest(int requestId) =>
      (delete(requestBaselines)..where((t) => t.requestId.equals(requestId))).go();
}
