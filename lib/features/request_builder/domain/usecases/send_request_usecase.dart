import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../../../core/enums/auth_type.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_http_response.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../../../auth_renewal/domain/services/oauth2_token_manager.dart';
import '../../../auth_renewal/domain/usecases/relogin_usecase.dart';
import '../../../auth_renewal/domain/usecases/renew_request_auth_usecase.dart';
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../history/domain/repositories/history_repository.dart';
import '../../../history/domain/repositories/history_store.dart';
import '../../../history/domain/services/history_run_budget.dart';
import '../../../odoo/domain/services/odoo_jsonrpc.dart';
import '../../../odoo/domain/services/smart_references.dart';
import '../../../settings/domain/repositories/request_settings_repository.dart';
import '../../../settings/domain/repositories/settings_repository.dart';
import '../entities/api_request_entity.dart';
import '../entities/api_response_entity.dart';
import '../entities/request_auth.dart';
import '../services/digest_auth_challenge.dart';
import '../services/request_spec_builder.dart';
import '../services/resolved_request_spec.dart';
import '../services/undefined_variables.dart';
import 'build_variable_resolver_usecase.dart';
import 'prepare_request_usecase.dart';

/// Builds the request through [PrepareRequestUseCase] (`{{variables}}` from the
/// active environment > folders > collection > globals, headers and auth signed
/// per its type and inherited from the folders and collection, the settings applied), sends it (retrying
/// once for Digest's challenge-response handshake), and records the result to
/// history — the single place a request actually leaves the app.
///
/// How it is sent (timeout, redirects, TLS, proxy, size cap, header tidying)
/// comes from the global settings with the request's own overrides on top.
/// Without the two settings repositories the defaults apply.
final class SendRequestUseCase implements UseCase<ApiResponseEntity, ApiRequestEntity> {
  final ApiClient _apiClient;
  final HistoryRepository _historyRepository;
  final PrepareRequestUseCase _prepareRequestUseCase;
  final RenewRequestAuthUseCase? _renewAuth;
  final ReloginUseCase? _relogin;

  /// Looks `{{xmlid:...}}` / `{{ref:...}}` tokens up on the Odoo server a request goes to; without it a request that
  /// holds one is refused (the literal token is never sent).
  final SmartReferenceResolver? _smartReferences;

  SendRequestUseCase(
    this._apiClient,
    BuildVariableResolverUseCase buildVariableResolverUseCase,
    this._historyRepository,
    CollectionAuthRepository collectionAuthRepository, [
    SettingsRepository? settingsRepository,
    RequestSettingsRepository? requestSettingsRepository,
    RequestSpecBuilder specBuilder = const RequestSpecBuilder(),
    ResolveRequestDefaultsUseCase? defaults,
    RenewRequestAuthUseCase? renewAuth,
    ReloginUseCase? relogin,
    SmartReferenceResolver? smartReferences,
  ])  : _renewAuth = renewAuth,
        _relogin = relogin,
        _smartReferences = smartReferences,
        _prepareRequestUseCase = PrepareRequestUseCase(
          buildVariableResolverUseCase,
          collectionAuthRepository,
          settings: settingsRepository,
          requestSettings: requestSettingsRepository,
          specBuilder: specBuilder,
          defaults: defaults,
        );

  /// [cancelToken] abandons the send in flight; it then throws a
  /// `NetworkException` of kind `cancelled` and nothing is recorded.
  /// [dataVariables] are a collection run's data row: variables that beat
  /// every other scope for this send. [historyRun] is the budget of the collection
  /// run this send belongs to: once it is spent the send is no longer recorded.
  /// A request with OAuth 2.0 auth gets its token fetched or renewed first when it is missing or about to
  /// expire. A request that comes back rejected (401/403) is sent once more after the login request its
  /// collection or folder names has run, unless [reLogin] is off (it is for the login request itself).
  @override
  Future<ApiResponseEntity> call(
    ApiRequestEntity request, {
    ApiCancelToken? cancelToken,
    Map<String, String> dataVariables = const {},
    HistoryRunBudget? historyRun,
    bool reLogin = true,
  }) async {
    final sentAt = DateTime.now();
    final answer = await _sendOnce(request, cancelToken, dataVariables, historyRun);
    final relogin = _relogin;
    // Odoo 18 and older answer an expired session with 200 and an error in the body: for the re-login that is a 401.
    final expired = answer.statusCode < 400 && OdooSessionExpiry.isExpiredBytes(answer.bodyBytes);
    if (!reLogin || relogin == null || (answer.statusCode < 400 && !expired)) return answer;
    final rejected = expired
        ? ApiResponseEntity(
            statusCode: 401,
            statusMessage: answer.statusMessage,
            headers: answer.headers,
            bodyBytes: answer.bodyBytes,
            duration: answer.duration,
            truncated: answer.truncated,
            setCookies: answer.setCookies,
            authNotes: answer.authNotes,
          )
        : answer;
    final outcome = await relogin.afterFailure(
      request,
      rejected,
      sentAt: sentAt,
      dataVariables: dataVariables,
      cancelToken: cancelToken,
      login: (login) => call(login, cancelToken: cancelToken, dataVariables: dataVariables, historyRun: historyRun, reLogin: false),
      retry: () => _sendOnce(request, cancelToken, dataVariables, historyRun),
    );
    // The 401 only started the re-login. When nothing was sent again the answer Odoo really gave stands, with the notes.
    if (expired && identical(outcome.bodyBytes, answer.bodyBytes)) {
      return answer.withAuthNotes(outcome.authNotes.skip(answer.authNotes.length).toList());
    }
    return outcome;
  }

  Future<ApiResponseEntity> _sendOnce(
    ApiRequestEntity request,
    ApiCancelToken? cancelToken,
    Map<String, String> dataVariables,
    HistoryRunBudget? historyRun,
  ) async {
    var prepared = await _prepareRequestUseCase(request, dataVariables: dataVariables);
    var spec = prepared.spec;
    final plainUndefined = SmartReferences.ordinary(prepared.undefinedVariables);
    if (plainUndefined.isNotEmpty) {
      throw UndefinedVariables.exception(plainUndefined, spec.url);
    }
    // `{{xmlid:...}}` / `{{ref:...}}` are looked up on the Odoo server now, once nothing else is missing, and
    // join the data row's scope; a token that cannot be resolved stops the send like an undefined variable.
    var variables = dataVariables;
    final pending = SmartReferences.pendingKeys(prepared.undefinedVariables);
    if (pending.isNotEmpty) {
      variables = {...dataVariables, ...await _resolveSmartReferences(prepared, pending)};
      prepared = await _prepareRequestUseCase(request, dataVariables: variables);
      spec = prepared.spec;
    }
    _requireSendableUrl(spec.url);
    final authNotes = <String>[];
    final renewal = await _renewToken(request, prepared);
    if (renewal.replacesAuth) {
      prepared = await _prepareRequestUseCase(request, dataVariables: variables, authOverride: renewal.auth);
      spec = prepared.spec;
    }
    if (renewal.note case final note?) authNotes.add(note);
    final apiOptions = prepared.options.toApiOptions();

    ApiHttpResponse response;
    try {
      response = await _apiClient.send(
        ApiRequestSpec(
          method: spec.method,
          url: spec.url,
          headers: spec.headers,
          body: spec.wireBody,
          cancelToken: cancelToken,
          options: apiOptions,
        ),
      );

      if (prepared.auth.type == AuthType.digest && response.statusCode == 401) {
        response = await _retryWithDigest(prepared.auth, prepared.resolver, spec, apiOptions, response, cancelToken);
      }
    } on NetworkException catch (error) {
      // A send that got no answer (DNS, refused, timeout) is one worth finding again in History; one the
      // person cancelled is not.
      if (error.kind != NetworkErrorKind.cancelled) await _recordToHistory(request, prepared, null, historyRun, error);
      rethrow;
    }

    await _recordToHistory(request, prepared, response, historyRun);

    return _toEntity(response, authNotes);
  }

  Future<Map<String, String>> _resolveSmartReferences(PreparedRequest prepared, List<String> keys) async {
    final resolver = _smartReferences;
    if (resolver == null) throw InvalidRequestException(SmartReferences.unavailable(keys));
    try {
      return await resolver.resolve(
        SmartReferenceContext(url: prepared.spec.url, headers: prepared.spec.headers, variable: prepared.resolver.lookup),
        keys,
      );
    } on SmartReferenceException catch (e) {
      throw InvalidRequestException('${e.message} The request was not sent.');
    }
  }

  /// A missing or expiring OAuth 2.0 token is renewed before the send (see [RenewRequestAuthUseCase]). When it
  /// cannot be, the request is not sent: a request with a dead token would only come back 401.
  Future<TokenRenewal> _renewToken(ApiRequestEntity request, PreparedRequest prepared) async {
    final renew = _renewAuth;
    if (renew == null) return TokenRenewal.none(prepared.auth);
    try {
      return await renew(request, prepared);
    } on OAuth2RenewalException catch (e) {
      throw InvalidRequestException('${e.message} The request was not sent.');
    }
  }

  /// History is a convenience: a failure to write it (a full disk, a locked
  /// database) must not turn a response that was received into a failed send
  /// and throw that response away. Only the exception's type is logged: its
  /// text can quote the SQL and the URL it was bound to. Without a [response]
  /// the send failed with [failure]. A repository that keeps more than the
  /// summary (a [HistoryStore]) also gets the request as saved and the answer.
  Future<void> _recordToHistory(
    ApiRequestEntity request,
    PreparedRequest prepared,
    ApiHttpResponse? response,
    HistoryRunBudget? historyRun, [
    NetworkException? failure,
  ]) async {
    try {
      if (historyRun != null && !historyRun.admit(statusCode: response?.statusCode)) return;
      final history = _historyRepository;
      final url = _templateUrl(request);
      final durationMs = response?.duration.inMilliseconds;
      if (history is HistoryStore) {
        await history.recordCapture(
          method: prepared.spec.method,
          url: url,
          statusCode: response?.statusCode,
          durationMs: durationMs,
          capture: HistoryCapture(
            request: request,
            responseBytes: response?.bodyBytes ?? const [],
            responseContentType: response == null ? null : _header(response.headers, 'content-type'),
            statusMessage: response?.statusMessage ?? '',
            responseTruncated: response?.truncated ?? false,
            error: failure == null ? null : SecretMasker.maskMessage(failure.summary ?? failure.message),
            resolver: prepared.resolver,
          ),
        );
      } else {
        await history.record(
          method: prepared.spec.method,
          url: url,
          statusCode: response?.statusCode,
          durationMs: durationMs,
          responseHeaders: response?.headers ?? const {},
        );
      }
    } catch (error) {
      debugPrint('PostPilot: the request was sent but could not be added to History (${error.runtimeType}).');
    }
  }

  /// Only http(s) URLs with a host can be sent; anything else would fail
  /// deep inside the HTTP client with a message that doesn't name the URL.
  void _requireSendableUrl(String url) {
    final uri = Uri.tryParse(url);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null || uri.host.isEmpty || (scheme != 'http' && scheme != 'https') || _hostHasBraces(uri.host)) {
      // The URL is resolved, so a secret in it must not travel in the message.
      throw InvalidUrlException('Not a valid http(s) URL: "${SecretMasker.maskUrl(url)}"');
    }
  }

  /// `Uri` percent-escapes a brace in a host instead of rejecting it, so a
  /// `{{placeholder}}` that survived resolution still parses; no real host has one.
  static final _hostBrace = RegExp(r'[{}]|%7[bBdD]');
  bool _hostHasBraces(String host) => _hostBrace.hasMatch(host);

  /// The URL as written — `{{variables}}` unresolved, enabled query params
  /// appended. History records this rather than the resolved URL so secret
  /// values never reach the History list, and re-opening an entry keeps its
  /// `{{variable}}` links instead of freezing today's environment.
  String _templateUrl(ApiRequestEntity request) {
    final query = request.queryParams
        .where((p) => p.enabled && p.key.isNotEmpty)
        .map((p) => '${p.key}=${p.value}')
        .join('&');
    if (query.isEmpty) return request.url;
    return '${request.url}${request.url.contains('?') ? '&' : '?'}$query';
  }

  Future<ApiHttpResponse> _retryWithDigest(
    RequestAuth auth,
    VariableResolver resolver,
    ResolvedRequestSpec spec,
    ApiRequestOptions options,
    ApiHttpResponse challengeResponse,
    ApiCancelToken? cancelToken,
  ) async {
    final challenge = DigestAuthChallenge.parse(_header(challengeResponse.headers, 'www-authenticate'));
    if (challenge == null) return challengeResponse;

    final digestHeader = challenge.buildAuthorizationHeader(
      username: resolver.resolve(auth.basicUsername),
      password: resolver.resolve(auth.basicPassword),
      method: spec.method,
      digestUri: digestRequestUri(spec.url),
      body: spec.bodyBytes ?? const [],
    );

    return _apiClient.send(ApiRequestSpec(
      method: spec.method,
      url: spec.url,
      headers: {...spec.headers, 'Authorization': digestHeader},
      body: spec.wireBody,
      cancelToken: cancelToken,
      options: options,
    ));
  }

  String? _header(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  ApiResponseEntity _toEntity(ApiHttpResponse response, List<String> authNotes) => ApiResponseEntity(
        statusCode: response.statusCode,
        statusMessage: response.statusMessage,
        headers: response.headers,
        bodyBytes: Uint8List.fromList(response.bodyBytes),
        duration: response.duration,
        truncated: response.truncated,
        setCookies: response.setCookies,
        authNotes: authNotes,
      );
}

/// The Request-URI the Digest `uri` directive (and HA2) must cover, RFC 7616
/// §3.4: path plus query, exactly as it goes on the request line.
String digestRequestUri(String url) {
  final uri = Uri.parse(url);
  final path = uri.path.isEmpty ? '/' : uri.path;
  return uri.hasQuery ? '$path?${uri.query}' : path;
}
