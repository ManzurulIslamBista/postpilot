import '../../../../core/usecases/usecase.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../environments/domain/repositories/global_variable_repository.dart';
import '../entities/variable_info.dart';

/// Every `{{variable}}` a request in [collectionId] can see, with where each
/// one comes from. Layered exactly as [BuildVariableResolverUseCase] resolves
/// them (active environment > collection > globals): a name held by several
/// scopes appears once, as the highest-precedence scope's. Disabled variables
/// are not visible to a request, so they are left out.
final class ListVariablesUseCase implements UseCase<Map<String, VariableInfo>, int> {
  final CollectionVariableRepository _collectionVariables;
  final EnvironmentRepository _environments;
  final GlobalVariableRepository _globals;

  const ListVariablesUseCase(this._collectionVariables, this._environments, this._globals);

  @override
  Future<Map<String, VariableInfo>> call(int collectionId) async {
    final result = <String, VariableInfo>{};

    // Lowest precedence first, so each later scope overwrites the one below.
    for (final g in await _globals.watchAll().first) {
      if (!g.enabled) continue;
      result[g.key] = VariableInfo(
        name: g.key,
        source: VariableSource.global,
        value: g.value,
        isSecret: g.isSecret,
      );
    }
    for (final v in await _collectionVariables.watchByCollection(collectionId).first) {
      if (!v.enabled) continue;
      result[v.key] = VariableInfo(name: v.key, source: VariableSource.collection, value: v.value);
    }
    final active = (await _environments.watchAll().first).where((e) => e.isActive).firstOrNull;
    if (active != null) {
      for (final v in await _environments.watchVariables(active.id).first) {
        if (!v.enabled) continue;
        result[v.key] = VariableInfo(
          name: v.key,
          source: VariableSource.environment,
          scopeName: active.name,
          value: v.value,
          isSecret: v.isSecret,
        );
      }
    }
    return result;
  }
}
