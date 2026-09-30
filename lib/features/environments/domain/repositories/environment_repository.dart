import '../entities/environment_entity.dart';

abstract interface class EnvironmentRepository {
  Stream<List<EnvironmentEntity>> watchAll();
  Stream<EnvironmentEntity?> watchActive();
  Future<int> create(String name);
  Future<void> rename(int id, String name);
  Future<void> setActive(int id);

  /// Deactivates whichever environment is active ("No Environment").
  Future<void> clearActive();
  Future<void> delete(int id);

  Stream<List<EnvironmentVariableEntity>> watchVariables(int environmentId);
  Future<void> upsertVariable(EnvironmentVariableEntity variable);
  Future<void> deleteVariable(int id);

  /// Flat, enabled-only key/value map for the currently active environment —
  /// used by [SendRequestUseCase] to resolve `{{variable}}` tokens.
  Future<Map<String, String>> getActiveVariables();
}
