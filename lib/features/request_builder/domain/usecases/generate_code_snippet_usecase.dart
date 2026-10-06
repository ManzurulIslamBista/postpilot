import '../../../../core/usecases/usecase.dart';
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../settings/domain/repositories/request_settings_repository.dart';
import '../../../settings/domain/repositories/settings_repository.dart';
import '../entities/api_request_entity.dart';
import '../services/code_generators/code_generator.dart';
import '../services/request_spec_builder.dart';
import 'build_variable_resolver_usecase.dart';
import 'prepare_request_usecase.dart';

final class GenerateCodeSnippetParams {
  final ApiRequestEntity request;
  final CodeGenerator generator;
  const GenerateCodeSnippetParams(this.request, this.generator);
}

/// Renders a request as a ready-to-paste snippet in another language/tool —
/// built by the same [PrepareRequestUseCase] that [SendRequestUseCase] sends
/// with (variable scopes, inherited collection auth, trimming and the no-cache
/// header from the settings), so the snippet always matches what the app
/// actually transmits. Pass [settings] and [requestSettings] to apply them;
/// without them the defaults do.
final class GenerateCodeSnippetUseCase implements UseCase<String, GenerateCodeSnippetParams> {
  final PrepareRequestUseCase _prepareRequestUseCase;

  GenerateCodeSnippetUseCase(
    BuildVariableResolverUseCase buildVariableResolverUseCase,
    CollectionAuthRepository collectionAuthRepository, {
    SettingsRepository? settings,
    RequestSettingsRepository? requestSettings,
    RequestSpecBuilder specBuilder = const RequestSpecBuilder(),
  }) : _prepareRequestUseCase = PrepareRequestUseCase(
          buildVariableResolverUseCase,
          collectionAuthRepository,
          settings: settings,
          requestSettings: requestSettings,
          specBuilder: specBuilder,
        );

  @override
  Future<String> call(GenerateCodeSnippetParams params) async =>
      params.generator.generate((await _prepareRequestUseCase(params.request)).spec);
}
