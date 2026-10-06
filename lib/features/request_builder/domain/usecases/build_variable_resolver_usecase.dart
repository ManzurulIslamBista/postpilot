import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../defaults/domain/entities/inherited_defaults.dart';
import '../../../defaults/domain/repositories/defaults_repository.dart';
import '../../../defaults/domain/services/defaults_resolver.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../environments/domain/repositories/global_variable_repository.dart';

/// Layers the variable scopes visible to a request into one [VariableResolver], highest precedence
/// first:
///
///  1. a collection run's data row ([dataVariables]);
///  2. the active environment;
///  3. the variables of the request's folders, the innermost folder first;
///  4. the collection's variables;
///  5. the globals.
///
/// (There are no request-level variables.) Each repository already excludes disabled variables.
/// Folders only take part when the request's folder is known (a [folderId], or [inherited] already
/// resolved for it) and the [DefaultsRepository] is wired; without them the layers are what they
/// were before folders had variables. Callers that know the request pass its folder: a scope the
/// folder holds is invisible otherwise.
///
/// A collection run's data row goes on top as [dataVariables], so a column beats a variable of the
/// same name and every scope that references it (an environment value holding `{{column}}`, say)
/// sees the row's value.
final class BuildVariableResolverUseCase implements UseCase<VariableResolver, int> {
  final CollectionVariableRepository _collectionVariableRepository;
  final EnvironmentRepository _environmentRepository;
  final GlobalVariableRepository _globalVariableRepository;
  final DefaultsRepository? _defaults;

  const BuildVariableResolverUseCase(
    this._collectionVariableRepository,
    this._environmentRepository,
    this._globalVariableRepository, [
    this._defaults,
  ]);

  /// [inherited] saves a second read of the folder levels for a caller that has resolved them already.
  @override
  Future<VariableResolver> call(
    int collectionId, {
    Map<String, String> dataVariables = const {},
    int? folderId,
    InheritedDefaults? inherited,
  }) async =>
      VariableResolver.layered([
        if (dataVariables.isNotEmpty) dataVariables,
        await _environmentRepository.getActiveVariables(),
        ...await _folderScopes(collectionId, folderId, inherited),
        await _collectionVariableRepository.getEnabledMap(collectionId),
        await _globalVariableRepository.getEnabledMap(),
      ]);

  Future<List<Map<String, String>>> _folderScopes(int collectionId, int? folderId, InheritedDefaults? inherited) async {
    if (inherited != null) return inherited.variableScopes;
    final defaults = _defaults;
    if (defaults == null || folderId == null) return const [];
    final tree = await defaults.loadTree(collectionId);
    return DefaultsResolver.resolve(tree.chainFor(folderId)).variableScopes;
  }
}
