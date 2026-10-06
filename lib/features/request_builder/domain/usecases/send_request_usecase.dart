import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../../../core/enums/auth_type.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_http_response.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../history/domain/repositories/history_repository.dart';
import '../../../history/domain/repositories/history_store.dart';
import '../../../history/domain/services/history_run_budget.dart';
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

  SendRequestUseCase(
    this._apiClient,
    BuildVariableResolverUseCase buildVariableResolverUseCase,
    this._historyRepository,
    CollectionAuthRepository collectionAuthRepository, [
    SettingsRepository? settingsRepository,
    RequestSettingsRepository? requestSettingsRepository,
    RequestSpecBuilder specBuilder = const RequestSpecBuilder(),
    ResolveRequestDefaultsUseCase? defaults,
  ]) : _prepareRequestUseCase = PrepareRequestUseCase(
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
  @override
  Future<ApiResponseEntity> call(
    ApiRequestEntity request, {
    ApiCancelToken? cancelToken,
    Map<String, String> dataVariables = const {},
    HistoryRunBudget? historyRun,
  }) async {
    final prepared = await _prepareRequestUseCase(request, dataVariables: dataVariables);
    final spec = prepared.spec;
    if (prepared.undefinedVariables.isNotEmpty) {
      throw UndefinedVariables.exception(prepared.undefinedVariables, spec.url);
    }
    _requireSendableUrl(spec.url);
    final apiOptions = prepared.options.toApiOptions();

    ApiHttpResponse response;
    try {
      response = await _apiClient.send(
        ApiRequestSpec(
          method: spec.method,
          url: spec.url,
          headers: spec.headers,
          body: spec.bodyBytes,
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

    return _toEntity(response);
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
      body: spec.bodyBytes,
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

  ApiResponseEntity _toEntity(ApiHttpResponse response) => ApiResponseEntity(
        statusCode: response.statusCode,
        statusMessage: response.statusMessage,
        headers: response.headers,
        bodyBytes: Uint8List.fromList(response.bodyBytes),
        duration: response.duration,
        truncated: response.truncated,
        setCookies: response.setCookies,
      );
}

/// The Request-URI the Digest `uri` directive (and HA2) must cover, RFC 7616
/// §3.4: path plus query, exactly as it goes on the request line.
String digestRequestUri(String url) {
  final uri = Uri.parse(url);
  final path = uri.path.isEmpty ? '/' : uri.path;
  return uri.hasQuery ? '$path?${uri.query}' : path;
}
