// A small fake world for the self-renewing auth tests: an authorization server and an API that live in
// memory (no sockets, no real clock), and the real use cases over a real in-memory SQLite database.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/auth_renewal/data/repository_oauth2_token_store.dart';
import 'package:postpilot/features/auth_renewal/domain/services/oauth2_token_manager.dart';
import 'package:postpilot/features/auth_renewal/domain/usecases/relogin_usecase.dart';
import 'package:postpilot/features/auth_renewal/domain/usecases/renew_request_auth_usecase.dart';
import 'package:postpilot/features/cli/workspace_runner.dart';
import 'package:postpilot/features/defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/services/collection_runner_service.dart';
import 'package:postpilot/features/request_builder/domain/services/oauth2_token_service.dart';
import 'package:postpilot/features/request_builder/domain/services/request_spec_builder.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/scripting/domain/evaluator/assertion_evaluator.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import '../support/drift_repos.dart';
import '../support/shop_seed.dart';

const tokenUrl = 'https://auth.test/oauth/token';
const apiHost = 'https://api.test';

/// One request the authorization server answered.
final class TokenCall {
  final String grant;
  final Map<String, String> form;
  final String? authorization;
  const TokenCall(this.grant, this.form, this.authorization);
}

/// The authorization server at [tokenUrl] and an API at [apiHost] that accepts the tokens it issued.
///
///  * `client_credentials` and `password` hand out `at-N`;
///  * `refresh_token` accepts only a refresh token it handed out (or was told about with [validRefresh]),
///    and with [rotateRefresh] retires it and issues a new one, as a server with rotation does, so a second
///    use of the old one is `invalid_grant`;
///  * the API answers 200 to `Authorization: Bearer <a token in [validTokens]>` and 401 to anything else;
///    `POST /login` answers `{"token":"login-N"}` and makes that token valid.
final class FakeAuthServer implements ApiClient {
  FakeAuthServer({this.clientId = 'cid', this.clientSecret = 'csecret'});

  final String clientId;
  final String clientSecret;

  /// `expires_in` of the tokens it issues.
  int expiresIn = 3600;

  /// Appended to every token it issues (`at-1<suffix>`): a realistic length for the tests that look for tokens in
  /// stored and shown text, where a four-character token could hide among ordinary words.
  String tokenSuffix = '';
  bool rotateRefresh = false;

  /// Also issue a refresh token with the access token of the first two grants.
  bool issueRefreshWithGrant = false;
  final Set<String> validRefresh = {};
  final Set<String> validTokens = {};

  final List<TokenCall> tokenCalls = [];
  final List<ApiRequestSpec> apiCalls = [];
  int _issued = 0;
  int _logins = 0;
  int _refreshes = 0;

  /// Held until completed, so a test can make several requests overlap on the token endpoint.
  Future<void>? tokenGate;

  /// Held until completed before a login request is answered.
  Future<void>? loginGate;

  /// Answers every token request with this instead of the normal behaviour.
  ApiHttpResponse Function(TokenCall call)? tokenOverride;
  Object? tokenFailure;

  /// Replaces the API's own answer for a request.
  ApiHttpResponse? Function(ApiRequestSpec spec)? apiOverride;

  /// How many logins ran: `POST /login`.
  int get logins => _logins;
  int get refreshes => _refreshes;

  List<String> get apiAuthorizations => [for (final c in apiCalls) c.headers['Authorization'] ?? ''];

  ApiHttpResponse reply(int status, Object body) => ApiHttpResponse(
        statusCode: status,
        statusMessage: status == 200 ? 'OK' : 'Error',
        headers: const {'content-type': 'application/json'},
        bodyBytes: utf8.encode(body is String ? body : jsonEncode(body)),
        duration: const Duration(milliseconds: 5),
      );

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    if (spec.url.startsWith(tokenUrl)) return _token(spec);
    apiCalls.add(spec);
    final override = apiOverride?.call(spec);
    if (override != null) return override;
    final uri = Uri.parse(spec.url);
    if (uri.path.startsWith('/login')) {
      if (loginGate case final gate?) await gate;
      final token = 'login-${++_logins}$tokenSuffix';
      validTokens.add(token);
      return reply(200, {'token': token});
    }
    final header = spec.headers['Authorization'] ?? '';
    final token = header.startsWith('Bearer ') ? header.substring(7) : '';
    return validTokens.contains(token) ? reply(200, {'ok': true, 'path': uri.path}) : reply(401, {'error': 'unauthorized'});
  }

  Future<ApiHttpResponse> _token(ApiRequestSpec spec) async {
    final form = Uri.splitQueryString(utf8.decode(spec.body as List<int>));
    final call = TokenCall(form['grant_type'] ?? '', form, spec.headers['Authorization']);
    tokenCalls.add(call);
    final gate = tokenGate;
    if (gate != null) await gate;
    if (tokenFailure case final failure?) throw failure;
    if (tokenOverride case final override?) return override(call);

    final basic = 'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}';
    final clientOk = call.authorization == basic || (form['client_id'] == clientId && form['client_secret'] == clientSecret);
    if (!clientOk) {
      return reply(401, {'error': 'invalid_client', 'error_description': 'Client authentication failed'});
    }
    switch (call.grant) {
      case 'client_credentials':
        return _issue(withRefresh: issueRefreshWithGrant);
      case 'password':
        if (form['username'] == 'ann' && form['password'] == 'pw') return _issue(withRefresh: issueRefreshWithGrant);
        return reply(400, {'error': 'invalid_grant', 'error_description': 'Invalid user credentials'});
      case 'refresh_token':
        _refreshes++;
        final presented = form['refresh_token'] ?? '';
        if (!validRefresh.contains(presented)) {
          return reply(400, {'error': 'invalid_grant', 'error_description': 'Invalid refresh token: $presented'});
        }
        if (rotateRefresh) validRefresh.remove(presented);
        return _issue(withRefresh: rotateRefresh);
    }
    return reply(400, {'error': 'unsupported_grant_type'});
  }

  ApiHttpResponse _issue({required bool withRefresh}) {
    final access = 'at-${++_issued}$tokenSuffix';
    validTokens.add(access);
    final refresh = withRefresh ? 'rt-$_issued$tokenSuffix' : null;
    if (refresh != null) validRefresh.add(refresh);
    return reply(200, {
      'access_token': access,
      'token_type': 'Bearer',
      'expires_in': expiresIn,
      'refresh_token': ?refresh,
    });
  }

  /// Makes `at-N`-style tokens stop working, as when a server revokes them before their expiry.
  void revokeAll() => validTokens.clear();
}

/// The command line's sender over a [FakeAuthServer].
Future<CliResponse> Function(CliRequest) cliSendOver(FakeAuthServer server, {void Function(CliRequest)? onSend}) =>
    (request) async {
      onSend?.call(request);
      final response = await server.send(ApiRequestSpec(
        method: request.method,
        url: request.url,
        headers: request.headers,
        body: request.body,
      ));
      return CliResponse(
        statusCode: response.statusCode,
        statusMessage: response.statusMessage,
        headers: response.headers,
        bodyBytes: response.bodyBytes,
        duration: response.duration,
      );
    };

/// A client-credentials OAuth 2.0 auth for [FakeAuthServer], as typed into the Auth tab.
RequestAuth oauthAuth({
  OAuth2GrantType grant = OAuth2GrantType.clientCredentials,
  String secret = 'csecret',
  String clientIdValue = 'cid',
  String tokenEndpoint = tokenUrl,
  bool autoRenew = true,
  String token = '',
  DateTime? expiry,
  String refresh = '',
}) {
  final base = RequestAuth(
    type: AuthType.oauth2,
    oauth2GrantType: grant,
    oauth2AccessTokenUrl: tokenEndpoint,
    oauth2ClientId: clientIdValue,
    oauth2ClientSecret: secret,
    oauth2Username: grant == OAuth2GrantType.password ? 'ann' : '',
    oauth2Password: grant == OAuth2GrantType.password ? 'pw' : '',
    oauth2AutoRenew: autoRenew,
  );
  return token.isEmpty && refresh.isEmpty ? base : base.withOAuth2Token(token, expiry, refreshToken: refresh);
}

/// A recording history that keeps only the summary.
final class RecordingHistory implements HistoryRepository {
  final List<({String method, String url, int? status})> calls = [];

  @override
  Future<void> record({
    required String method,
    required String url,
    required int? statusCode,
    required int? durationMs,
    required Map<String, String> responseHeaders,
  }) async =>
      calls.add((method: method, url: url, status: statusCode));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

/// The real use cases over a real in-memory database and a [FakeAuthServer], with a clock the test moves.
final class AuthWorld {
  AuthWorld._(this.db, this.repos, this.server);

  final AppDatabase db;
  final DriftRepos repos;
  final FakeAuthServer server;

  /// The clock of the token logic; move it to expire tokens.
  DateTime now = DateTime.utc(2026, 10, 6, 12);
  DateTime clock() => now;

  late final RecordingHistory history = RecordingHistory();
  late final BuildVariableResolverUseCase resolver = BuildVariableResolverUseCase(
    repos.collectionVariableRepository,
    repos.environmentRepository,
    repos.globalVariableRepository,
    repos.defaultsRepository,
  );
  late final ResolveRequestDefaultsUseCase defaults = ResolveRequestDefaultsUseCase(repos.defaultsRepository);
  late final OAuth2TokenManager manager = OAuth2TokenManager(
    OAuth2TokenService(server, now: clock),
    RepositoryOAuth2TokenStore(repos.requestRepository, repos.collectionAuthRepository, repos.defaultsRepository),
    now: clock,
  );
  late final RunRequestScriptsUseCase scripts = RunRequestScriptsUseCase(
    repos.scriptsRepository,
    resolver,
    repos.environmentRepository,
    repos.globalVariableRepository,
    const AssertionEvaluator(),
    defaults,
  );
  late final ReloginUseCase relogin = ReloginUseCase(
    repos.requestRepository,
    repos.collectionAuthRepository,
    scripts,
    collections: repos.collectionRepository,
    defaults: defaults,
  );
  late final SendRequestUseCase send = SendRequestUseCase(
    server,
    resolver,
    history,
    repos.collectionAuthRepository,
    null,
    null,
    const RequestSpecBuilder(),
    defaults,
    RenewRequestAuthUseCase(manager),
    relogin,
  );
  late final CollectionRunnerService runner = CollectionRunnerService.withFolders(
    repos.requestRepository,
    send,
    scripts,
    repos.collectionRepository,
    // A run's "wait between requests" costs no real time here: it moves the clock the tokens expire by.
    (wait) async => now = now.add(wait),
  );

  static Future<AuthWorld> create({FakeAuthServer? server}) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    return AuthWorld._(db, DriftRepos(db), server ?? FakeAuthServer());
  }

  Future<void> close() => db.close();

  Future<int> collection([String name = 'API']) => repos.collectionRepository.createCollection(name);

  Future<void> setCollectionAuth(int collectionId, RequestAuth auth) =>
      repos.collectionAuthRepository.setAuthJson(collectionId, auth.toJsonString());

  Future<RequestAuth> storedCollectionAuth(int collectionId) async =>
      RequestAuth.fromJsonString(await repos.collectionAuthRepository.getAuthJson(collectionId))!;

  /// A request inheriting its auth, GET [path] on [apiHost].
  Future<ApiRequestEntity> request(
    int collectionId,
    String name,
    String path, {
    int? folderId,
    HttpMethod method = HttpMethod.get,
    RequestAuth auth = const RequestAuth(type: AuthType.inherit),
  }) async {
    final id = await addRequest(repos, collectionId, name, folderId: folderId, method: method, url: '$apiHost$path', auth: auth);
    return (await repos.requestRepository.findById(id))!;
  }

  /// A login request: `POST /login`, saving `$.token` into the global variable [variable].
  Future<ApiRequestEntity> loginRequest(int collectionId, {String name = 'Login', int? folderId, String variable = 'token'}) async {
    final login = await request(collectionId, name, '/login', folderId: folderId, method: HttpMethod.post, auth: const RequestAuth(type: AuthType.none));
    await repos.scriptsRepository.save(RequestScriptsEntity(
      requestId: login.id,
      extractorsJson: ScriptsJsonCodec.encodeExtractors([
        ExtractorEntity(path: r'$.token', variableKey: variable, scope: ExtractorScope.global),
      ]),
    ));
    return login;
  }
}
