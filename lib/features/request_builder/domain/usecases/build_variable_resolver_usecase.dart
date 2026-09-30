import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../environments/domain/repositories/global_variable_repository.dart';

/// Layers the variable scopes visible to a request in Postman precedence —
/// the active environment > its collection > globals — into one
/// [VariableResolver]. Each repository already excludes disabled variables.
///
/// A collection run's data row goes on top as [dataVariables], so a column
/// beats a variable of the same name and every scope that references it
/// (an environment value holding `{{column}}`, say) sees the row's value.
final class BuildVariableResolverUseCase implements UseCase<VariableResolver, int> {
  final CollectionVariableRepository _collectionVariableRepository;
  final EnvironmentRepository _environmentRepository;
  final GlobalVariableRepository _globalVariableRepository;

  const BuildVariableResolverUseCase(
    this._collectionVariableRepository,
    this._environmentRepository,
    this._globalVariableRepository,
  );

  @override
  Future<VariableResolver> call(int collectionId, {Map<String, String> dataVariables = const {}}) async =>
      VariableResolver.layered([
        if (dataVariables.isNotEmpty) dataVariables,
        await _environmentRepository.getActiveVariables(),
        await _collectionVariableRepository.getEnabledMap(collectionId),
        await _globalVariableRepository.getEnabledMap(),
      ]);
}
