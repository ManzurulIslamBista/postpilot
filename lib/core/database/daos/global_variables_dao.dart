import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/global_variables_table.dart';

part 'global_variables_dao.g.dart';

@DriftAccessor(tables: [GlobalVariables])
class GlobalVariablesDao extends DatabaseAccessor<AppDatabase> with _$GlobalVariablesDaoMixin {
  GlobalVariablesDao(super.db);

  Stream<List<GlobalVariable>> watchAll() =>
      (select(globalVariables)..orderBy([(t) => OrderingTerm.asc(t.id)])).watch();

  Future<List<GlobalVariable>> getEnabled() =>
      (select(globalVariables)..where((t) => t.enabled.equals(true))).get();

  Future<int> addVariable(GlobalVariablesCompanion entry) => into(globalVariables).insert(entry);

  Future<void> updateVariable(int id, GlobalVariablesCompanion entry) =>
      (update(globalVariables)..where((t) => t.id.equals(id))).write(entry);

  Future<void> deleteVariable(int id) => (delete(globalVariables)..where((t) => t.id.equals(id))).go();
}
