import '../entities/global_variable_entity.dart';

abstract interface class GlobalVariableRepository {
  Stream<List<GlobalVariableEntity>> watchAll();

  /// Inserts when [variable.id] is 0, otherwise updates that row.
  Future<void> upsert(GlobalVariableEntity variable);
  Future<void> delete(int id);

  /// Flat, enabled-only key/value map — the lowest-precedence layer when
  /// resolving `{{variable}}` tokens.
  Future<Map<String, String>> getEnabledMap();
}
