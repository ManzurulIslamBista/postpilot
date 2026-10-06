import '../../../core/utils/variable_resolver.dart';
import '../../environments/domain/repositories/environment_repository.dart';
import '../../request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import '../domain/services/flow_environment.dart';

/// The app's variables and environment, read the way a send reads them.
final class AppFlowEnvironment implements FlowEnvironment {
  final BuildVariableResolverUseCase _buildResolver;
  final EnvironmentRepository _environments;

  const AppFlowEnvironment(this._buildResolver, this._environments);

  @override
  Future<VariableResolver> resolver({
    required int collectionId,
    int? folderId,
    Map<String, String> dataVariables = const {},
  }) =>
      _buildResolver(collectionId, dataVariables: dataVariables, folderId: folderId);

  @override
  Future<String?> environmentName() async => (await _environments.watchActive().first)?.name;
}
