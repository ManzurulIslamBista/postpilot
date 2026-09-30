import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/request_scripts_table.dart';

part 'request_scripts_dao.g.dart';

@DriftAccessor(tables: [RequestScripts])
class RequestScriptsDao extends DatabaseAccessor<AppDatabase> with _$RequestScriptsDaoMixin {
  RequestScriptsDao(super.db);

  Future<RequestScript?> findByRequest(int requestId) =>
      (select(requestScripts)..where((t) => t.requestId.equals(requestId))).getSingleOrNull();

  Stream<RequestScript?> watchByRequest(int requestId) =>
      (select(requestScripts)..where((t) => t.requestId.equals(requestId))).watchSingleOrNull();

  Future<void> upsert(RequestScriptsCompanion entry) => into(requestScripts).insertOnConflictUpdate(entry);
}
