import 'package:drift/drift.dart' show Value;
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/collection_variables_dao.dart';
import '../../domain/entities/collection_variable_entity.dart';
import '../../domain/repositories/collection_variable_repository.dart';

final class CollectionVariableRepositoryImpl implements CollectionVariableRepository {
  final CollectionVariablesDao _dao;
  const CollectionVariableRepositoryImpl(this._dao);

  @override
  Stream<List<CollectionVariableEntity>> watchByCollection(int collectionId) =>
      _dao.watchByCollection(collectionId).map(
            (rows) => rows
                .map((r) => CollectionVariableEntity(
                      id: r.id,
                      collectionId: r.collectionId,
                      key: r.key,
                      value: r.value,
                      enabled: r.enabled,
                    ))
                .toList(),
          );

  @override
  Future<void> upsert(CollectionVariableEntity variable) {
    final companion = CollectionVariablesCompanion(
      collectionId: Value(variable.collectionId),
      key: Value(variable.key),
      value: Value(variable.value),
      enabled: Value(variable.enabled),
    );
    return variable.id == 0 ? _dao.addVariable(companion) : _dao.updateVariable(variable.id, companion);
  }

  @override
  Future<void> delete(int id) => _dao.deleteVariable(id);

  @override
  Future<Map<String, String>> getEnabledMap(int collectionId) async {
    final rows = await _dao.getEnabledByCollection(collectionId);
    return {for (final r in rows) r.key: r.value};
  }
}
