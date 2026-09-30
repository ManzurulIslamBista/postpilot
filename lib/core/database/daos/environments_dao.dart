import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/environments_table.dart';

part 'environments_dao.g.dart';

@DriftAccessor(tables: [Environments, EnvironmentVariables])
class EnvironmentsDao extends DatabaseAccessor<AppDatabase> with _$EnvironmentsDaoMixin {
  EnvironmentsDao(super.db);

  Stream<List<Environment>> watchAll() => select(environments).watch();

  Stream<Environment?> watchActive() =>
      (select(environments)..where((t) => t.isActive.equals(true))).watchSingleOrNull();

  Future<int> create(String name) => into(environments).insert(EnvironmentsCompanion.insert(name: name));

  Future<void> setActive(int id) => transaction(() async {
        await update(environments).write(const EnvironmentsCompanion(isActive: Value(false)));
        await (update(environments)..where((t) => t.id.equals(id)))
            .write(const EnvironmentsCompanion(isActive: Value(true)));
      });

  Future<void> clearActive() => update(environments).write(const EnvironmentsCompanion(isActive: Value(false)));

  Future<void> renameEnvironment(int id, String name) =>
      (update(environments)..where((t) => t.id.equals(id))).write(EnvironmentsCompanion(name: Value(name)));

  Future<void> deleteEnvironment(int id) => (delete(environments)..where((t) => t.id.equals(id))).go();

  Stream<List<EnvironmentVariable>> watchVariables(int environmentId) =>
      (select(environmentVariables)
            ..where((t) => t.environmentId.equals(environmentId))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
          .watch();

  Future<int> addVariable(EnvironmentVariablesCompanion entry) => into(environmentVariables).insert(entry);

  Future<void> updateVariable(int id, EnvironmentVariablesCompanion entry) =>
      (update(environmentVariables)..where((t) => t.id.equals(id))).write(entry);

  Future<void> deleteVariable(int id) => (delete(environmentVariables)..where((t) => t.id.equals(id))).go();
}
