import '../../../../core/enums/auth_type.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../defaults/domain/entities/inherited_defaults.dart';
import '../../../defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/domain/entities/effective_request_options.dart';
import '../../../settings/domain/entities/request_settings.dart';
import '../../../settings/domain/repositories/request_settings_repository.dart';
import '../../../settings/domain/repositories/settings_repository.dart';
import '../entities/api_request_entity.dart';
import '../entities/request_auth.dart';
import '../services/request_spec_builder.dart';
import '../services/resolved_request_spec.dart';
import '../services/undefined_variables.dart';
import 'build_variable_resolver_usecase.dart';

/// A request built for the wire, with what a send still needs besides it.
final class PreparedRequest {
  /// Exactly what is transmitted: variables resolved, auth signed, the
  /// settings' trimming and no-cache header applied.
  final ResolvedRequestSpec spec;

  /// The scopes [spec] was resolved with.
  final VariableResolver resolver;

  /// The auth in force: the request's own, or the one it inherits (the nearest
  /// folder's, else the collection's) when it is set to inherit.
  final RequestAuth auth;

  /// The global settings with the request's own overrides on top.
  final EffectiveRequestOptions options;

  /// The `{{variables}}` the request uses that no scope defines. [spec] still
  /// holds them as literal text; [SendRequestUseCase] refuses to send it, a
  /// code snippet just prints it.
  final List<UndefinedVariable> undefinedVariables;

  /// What the request inherits from its collection and folders; null when the
  /// defaults are not wired (only the collection's auth then applies).
  final InheritedDefaults? inherited;

  const PreparedRequest({
    required this.spec,
    required this.resolver,
    required this.auth,
    required this.options,
    this.undefinedVariables = const [],
    this.inherited,
  });
}

/// The one path from a request to what leaves the app: scopes layered by
/// [BuildVariableResolverUseCase], headers, auth and variables inherited from
/// the collection and the folders above the request (see `DefaultsResolver`),
/// the settings applied. [SendRequestUseCase] sends the result and
/// [GenerateCodeSnippetUseCase] prints it, so a copied snippet can never differ
/// from the request that is sent. Without the two settings repositories the
/// defaults apply; without [defaults] only the collection's auth is inherited.
final class PrepareRequestUseCase implements UseCase<PreparedRequest, ApiRequestEntity> {
  final BuildVariableResolverUseCase _buildVariableResolverUseCase;
  final CollectionAuthRepository _collectionAuthRepository;
  final SettingsRepository? _settings;
  final RequestSettingsRepository? _requestSettings;
  final RequestSpecBuilder _specBuilder;
  final ResolveRequestDefaultsUseCase? _defaults;

  const PrepareRequestUseCase(
    this._buildVariableResolverUseCase,
    this._collectionAuthRepository, {
    this._settings,
    this._requestSettings,
    this._specBuilder = const RequestSpecBuilder(),
    this._defaults,
  });

  /// [dataVariables] are a collection run's data row: the highest-priority
  /// variable scope. [authOverride] is the auth in force with a token renewed since it was read (see
  /// `RenewRequestAuthUseCase`): it takes the place of the inherited auth for a request that inherits,
  /// else of the request's own.
  @override
  Future<PreparedRequest> call(
    ApiRequestEntity request, {
    Map<String, String> dataVariables = const {},
    RequestAuth? authOverride,
  }) async {
    final options = await _effectiveOptions(request.id);
    final inherited = await _defaults?.call(request);
    final resolver = await _buildVariableResolverUseCase(
      request.collectionId,
      dataVariables: dataVariables,
      folderId: request.folderId,
      inherited: inherited,
    );
    var inheritedAuth =
        inherited?.auth ?? RequestAuth.fromJsonString(await _collectionAuthRepository.getAuthJson(request.collectionId));
    if (authOverride != null) {
      if (request.auth.type == AuthType.inherit) {
        inheritedAuth = authOverride;
      } else {
        request = request.copyWith(auth: authOverride);
      }
    }
    final inheritedHeaders = inherited?.headerRows ?? const [];
    final spec = _specBuilder.build(
      request,
      resolver,
      inheritedAuth: inheritedAuth,
      inheritedHeaders: inheritedHeaders,
      trimKeysAndValues: options.trimKeysAndValues,
      sendNoCache: options.sendNoCache,
    );
    return PreparedRequest(
      spec: spec,
      resolver: resolver,
      auth: request.auth.resolveInherited(inheritedAuth),
      options: options,
      undefinedVariables: _specBuilder.undefinedVariables(
        request,
        resolver,
        inheritedAuth: inheritedAuth,
        inheritedHeaders: inheritedHeaders,
        trimKeysAndValues: options.trimKeysAndValues,
      ),
      inherited: inherited,
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
