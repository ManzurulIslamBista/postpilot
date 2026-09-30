import 'package:drift/drift.dart' show Value;
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/environments_dao.dart';
import '../../domain/entities/environment_entity.dart';
import '../../domain/repositories/environment_repository.dart';

final class EnvironmentRepositoryImpl implements EnvironmentRepository {
  final EnvironmentsDao _dao;
  const EnvironmentRepositoryImpl(this._dao);

  @override
  Stream<List<EnvironmentEntity>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => EnvironmentEntity(id: r.id, name: r.name, isActive: r.isActive)).toList());

  @override
  Stream<EnvironmentEntity?> watchActive() =>
      _dao.watchActive().map((r) => r == null ? null : EnvironmentEntity(id: r.id, name: r.name, isActive: r.isActive));

  @override
  Future<int> create(String name) => _dao.create(name);

  @override
  Future<void> rename(int id, String name) => _dao.renameEnvironment(id, name);

  @override
  Future<void> setActive(int id) => _dao.setActive(id);

  @override
  Future<void> clearActive() => _dao.clearActive();

  @override
  Future<void> delete(int id) => _dao.deleteEnvironment(id);

  @override
  Stream<List<EnvironmentVariableEntity>> watchVariables(int environmentId) =>
      _dao.watchVariables(environmentId).map(
            (rows) => rows
                .map((r) => EnvironmentVariableEntity(
                      id: r.id,
                      environmentId: r.environmentId,
                      key: r.key,
                      value: r.value,
                      isSecret: r.isSecret,
                      enabled: r.enabled,
                    ))
                .toList(),
          );

  @override
  Future<void> upsertVariable(EnvironmentVariableEntity variable) {
    final companion = EnvironmentVariablesCompanion(
      environmentId: Value(variable.environmentId),
      key: Value(variable.key),
      value: Value(variable.value),
      isSecret: Value(variable.isSecret),
      enabled: Value(variable.enabled),
    );
    return variable.id == 0 ? _dao.addVariable(companion) : _dao.updateVariable(variable.id, companion);
  }

  @override
  Future<void> deleteVariable(int id) => _dao.deleteVariable(id);

  @override
  Future<Map<String, String>> getActiveVariables() async {
    final active = await _dao.watchActive().first;
    if (active == null) return const {};
    final vars = await _dao.watchVariables(active.id).first;
    return {for (final v in vars.where((v) => v.enabled)) v.key: v.value};
  }
}
