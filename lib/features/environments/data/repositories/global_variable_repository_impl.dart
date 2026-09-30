import 'package:drift/drift.dart' show Value;
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/global_variables_dao.dart';
import '../../domain/entities/global_variable_entity.dart';
import '../../domain/repositories/global_variable_repository.dart';

final class GlobalVariableRepositoryImpl implements GlobalVariableRepository {
  final GlobalVariablesDao _dao;
  const GlobalVariableRepositoryImpl(this._dao);

  @override
  Stream<List<GlobalVariableEntity>> watchAll() => _dao.watchAll().map(
        (rows) => rows
            .map((r) => GlobalVariableEntity(
                  id: r.id,
                  key: r.key,
                  value: r.value,
                  isSecret: r.isSecret,
                  enabled: r.enabled,
                ))
            .toList(),
      );

  @override
  Future<void> upsert(GlobalVariableEntity variable) {
    final companion = GlobalVariablesCompanion(
      key: Value(variable.key),
      value: Value(variable.value),
      isSecret: Value(variable.isSecret),
      enabled: Value(variable.enabled),
    );
    return variable.id == 0 ? _dao.addVariable(companion) : _dao.updateVariable(variable.id, companion);
  }

  @override
  Future<void> delete(int id) => _dao.deleteVariable(id);

  @override
  Future<Map<String, String>> getEnabledMap() async {
    final rows = await _dao.getEnabled();
    return {for (final r in rows) r.key: r.value};
  }
}
