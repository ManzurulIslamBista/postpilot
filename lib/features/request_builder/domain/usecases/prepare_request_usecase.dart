import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/domain/entities/effective_request_options.dart';
import '../../../settings/domain/entities/request_settings.dart';
import '../../../settings/domain/repositories/request_settings_repository.dart';
import '../../../settings/domain/repositories/settings_repository.dart';
import '../entities/api_request_entity.dart';
import '../entities/request_auth.dart';
import '../services/request_spec_builder.dart';
import '../services/resolved_request_spec.dart';
import 'build_variable_resolver_usecase.dart';

/// A request built for the wire, with what a send still needs besides it.
final class PreparedRequest {
  /// Exactly what is transmitted: variables resolved, auth signed, the
  /// settings' trimming and no-cache header applied.
  final ResolvedRequestSpec spec;

  /// The scopes [spec] was resolved with.
  final VariableResolver resolver;

  /// The auth in force: the request's own, or the collection's when it inherits.
  final RequestAuth auth;

  /// The global settings with the request's own overrides on top.
  final EffectiveRequestOptions options;

  const PreparedRequest({required this.spec, required this.resolver, required this.auth, required this.options});
}

/// The one path from a request to what leaves the app: scopes layered by
/// [BuildVariableResolverUseCase], the collection's auth inherited, the
/// settings applied. [SendRequestUseCase] sends the result and
/// [GenerateCodeSnippetUseCase] prints it, so a copied snippet can never differ
/// from the request that is sent. Without the two settings repositories the
/// defaults apply.
final class PrepareRequestUseCase implements UseCase<PreparedRequest, ApiRequestEntity> {
  final BuildVariableResolverUseCase _buildVariableResolverUseCase;
  final CollectionAuthRepository _collectionAuthRepository;
  final SettingsRepository? _settings;
  final RequestSettingsRepository? _requestSettings;
  final RequestSpecBuilder _specBuilder;

  const PrepareRequestUseCase(
    this._buildVariableResolverUseCase,
    this._collectionAuthRepository, {
    this._settings,
    this._requestSettings,
    this._specBuilder = const RequestSpecBuilder(),
  });

  /// [dataVariables] are a collection run's data row: the highest-priority
  /// variable scope.
  @override
  Future<PreparedRequest> call(ApiRequestEntity request, {Map<String, String> dataVariables = const {}}) async {
    final options = await _effectiveOptions(request.id);
    final resolver = await _buildVariableResolverUseCase(request.collectionId, dataVariables: dataVariables);
    final inheritedAuth = RequestAuth.fromJsonString(await _collectionAuthRepository.getAuthJson(request.collectionId));
    final spec = _specBuilder.build(
      request,
      resolver,
      inheritedAuth: inheritedAuth,
      trimKeysAndValues: options.trimKeysAndValues,
      sendNoCache: options.sendNoCache,
    );
    return PreparedRequest(
      spec: spec,
      resolver: resolver,
      auth: request.auth.resolveInherited(inheritedAuth),
      options: options,
    );
  }

  /// A request whose overrides cannot be read is prepared with the global
  /// settings alone.
  Future<EffectiveRequestOptions> _effectiveOptions(int requestId) async {
    RequestSettings? overrides;
    try {
      overrides = await _requestSettings?.get(requestId);
    } catch (_) {
      overrides = null;
    }
    return EffectiveRequestOptions.resolve(_settings?.current ?? const AppSettings(), overrides);
  }
}
