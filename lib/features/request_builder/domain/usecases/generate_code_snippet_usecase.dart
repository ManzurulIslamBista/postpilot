import '../../../../core/usecases/usecase.dart';
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import '../../../settings/domain/repositories/request_settings_repository.dart';
import '../../../settings/domain/repositories/settings_repository.dart';
import '../entities/api_request_entity.dart';
import '../services/code_generators/code_generator.dart';
import '../services/code_generators/hmac_snippet_note.dart';
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
/// with (variable scopes, headers and auth inherited from the folders and the
/// collection, trimming and the no-cache header from the settings), so the
/// snippet always matches what the app actually transmits. Pass [settings] and
/// [requestSettings] to apply them; without them the defaults do. Pass [defaults]
/// to inherit from folders and collection headers; without it only the collection's
/// auth is inherited.
final class GenerateCodeSnippetUseCase implements UseCase<String, GenerateCodeSnippetParams> {
  final PrepareRequestUseCase _prepareRequestUseCase;

  GenerateCodeSnippetUseCase(
    BuildVariableResolverUseCase buildVariableResolverUseCase,
    CollectionAuthRepository collectionAuthRepository, {
    SettingsRepository? settings,
    RequestSettingsRepository? requestSettings,
    RequestSpecBuilder specBuilder = const RequestSpecBuilder(),
    ResolveRequestDefaultsUseCase? defaults,
  }) : _prepareRequestUseCase = PrepareRequestUseCase(
          buildVariableResolverUseCase,
          collectionAuthRepository,
          settings: settings,
          requestSettings: requestSettings,
          specBuilder: specBuilder,
          defaults: defaults,
        );

  @override
  Future<String> call(GenerateCodeSnippetParams params) async {
    final prepared = await _prepareRequestUseCase(params.request);
    // An HMAC signature that covers the clock is only good for a few minutes: the snippet says so.
    return HmacSnippetNote.append(params.generator.generate(prepared.spec), params.generator.id, prepared.auth);
  }
}
