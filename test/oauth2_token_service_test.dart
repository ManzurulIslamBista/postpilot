import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/services/oauth2_token_service.dart';
import 'package:postpilot/features/settings/domain/entities/app_settings.dart';
import 'package:postpilot/features/settings/domain/entities/proxy_settings.dart';
import 'settings/fakes/fake_settings_repositories.dart';

final class _FakeApiClient implements ApiClient {
  final ApiHttpResponse response;
  ApiRequestSpec? lastSpec;

  _FakeApiClient(this.response);

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    lastSpec = spec;
    return response;
  }
}

ApiHttpResponse _response(int statusCode, String body) => ApiHttpResponse(
      statusCode: statusCode,
      statusMessage: '',
      headers: const {},
      bodyBytes: utf8.encode(body),
      duration: Duration.zero,
    );

String _bodyOf(ApiRequestSpec spec) => utf8.decode(spec.body as List<int>);

void main() {
  final now = DateTime.utc(2026, 1, 1, 12);
  const tokenJson = '{"access_token":"tok_123","token_type":"Bearer","expires_in":3600}';

  const clientCredentials = RequestAuth(
    type: AuthType.oauth2,
    oauth2GrantType: OAuth2GrantType.clientCredentials,
    oauth2AccessTokenUrl: 'https://auth.example.com/oauth/token',
    oauth2ClientId: 'my-client',
    oauth2ClientSecret: 's3cret',
    oauth2Scope: 'read write',
    oauth2Audience: 'https://api.example.com',
  );

  group('PKCE', () {
    test('challenge is base64url(sha256(verifier)) without padding (RFC 7636 Appendix B)', () {
      expect(
        OAuth2TokenService.pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('generated verifier is 43 unreserved characters and matches its challenge', () {
      final service = OAuth2TokenService(_FakeApiClient(_response(200, tokenJson)), random: Random(7));
      final pair = service.generatePkcePair();
      expect(pair.verifier, matches(RegExp(r'^[A-Za-z0-9\-._~]{43}$')));
      expect(pair.challenge, OAuth2TokenService.pkceChallenge(pair.verifier));
      expect(pair.challenge, isNot(contains('=')));
    });

    test('authorization URL carries PKCE params and keeps the existing query', () {
      final service = OAuth2TokenService(_FakeApiClient(_response(200, tokenJson)));
      final url = service.buildAuthorizationUrl(
        clientCredentials.copyWith(
          oauth2GrantType: OAuth2GrantType.authorizationCodePkce,
          oauth2AuthorizationUrl: 'https://auth.example.com/authorize?tenant=acme',
          oauth2RedirectUri: 'http://localhost:8080/callback',
        ),
        codeChallenge: 'CHALLENGE',
        state: 'STATE',
      );
      final q = url.queryParameters;
      expect(url.origin, 'https://auth.example.com');
      expect(url.path, '/authorize');
      expect(q['tenant'], 'acme');
      expect(q['response_type'], 'code');
      expect(q['client_id'], 'my-client');
      expect(q['redirect_uri'], 'http://localhost:8080/callback');
      expect(q['scope'], 'read write');
      expect(q['audience'], 'https://api.example.com');
      expect(q['state'], 'STATE');
      expect(q['code_challenge'], 'CHALLENGE');
      expect(q['code_challenge_method'], 'S256');
    });
  });

  group('form body construction', () {
    test('client_credentials posts a form body with client creds in a Basic header', () async {
      final client = _FakeApiClient(_response(200, tokenJson));
      await OAuth2TokenService(client, now: () => now).fetchToken(clientCredentials);

      final spec = client.lastSpec!;
      expect(spec.method, 'POST');
      expect(spec.url, 'https://auth.example.com/oauth/token');
      expect(spec.headers['Content-Type'], 'application/x-www-form-urlencoded');
      expect(spec.headers['Authorization'], 'Basic ${base64Encode(utf8.encode('my-client:s3cret'))}');
      expect(_bodyOf(spec), 'grant_type=client_credentials&scope=read+write&audience=https%3A%2F%2Fapi.example.com');
    });

    test('body client authentication moves client_id/client_secret into the form', () async {
      final client = _FakeApiClient(_response(200, tokenJson));
      await OAuth2TokenService(client, now: () => now).fetchToken(
        clientCredentials.copyWith(oauth2ClientAuthentication: OAuth2ClientAuthentication.body),
      );

      final spec = client.lastSpec!;
      expect(spec.headers.containsKey('Authorization'), isFalse);
      expect(_bodyOf(spec), contains('client_id=my-client'));
      expect(_bodyOf(spec), contains('client_secret=s3cret'));
    });

    test('password grant includes url-encoded username and password', () async {
      final client = _FakeApiClient(_response(200, tokenJson));
      await OAuth2TokenService(client, now: () => now).fetchToken(
        clientCredentials.copyWith(
          oauth2GrantType: OAuth2GrantType.password,
          oauth2Username: 'alice@example.com',
          oauth2Password: 'p@ss w&rd',
          oauth2Scope: '',
          oauth2Audience: '',
        ),
      );

      expect(_bodyOf(client.lastSpec!), 'grant_type=password&username=alice%40example.com&password=p%40ss+w%26rd');
    });

    test('authorization code exchange posts code, verifier, redirect_uri; a public client sends client_id in the body',
        () async {
      final client = _FakeApiClient(_response(200, tokenJson));
      await OAuth2TokenService(client, now: () => now).exchangeAuthorizationCode(
        clientCredentials.copyWith(
          oauth2GrantType: OAuth2GrantType.authorizationCodePkce,
          oauth2ClientSecret: '',
          oauth2RedirectUri: 'http://localhost:8080/callback',
          oauth2Scope: '',
          oauth2Audience: '',
        ),
        code: 'CODE',
        codeVerifier: 'VERIFIER',
      );

      final spec = client.lastSpec!;
      expect(spec.headers.containsKey('Authorization'), isFalse);
      expect(
        _bodyOf(spec),
        'grant_type=authorization_code&code=CODE&code_verifier=VERIFIER'
        '&redirect_uri=http%3A%2F%2Flocalhost%3A8080%2Fcallback&client_id=my-client',
      );
    });

    test('fetchToken refuses the PKCE grant, which needs the two-step flow', () {
      final service = OAuth2TokenService(_FakeApiClient(_response(200, tokenJson)));
      expect(
        service.fetchToken(clientCredentials.copyWith(oauth2GrantType: OAuth2GrantType.authorizationCodePkce)),
        throwsA(isA<OAuth2TokenException>()),
      );
    });
  });

  group('token response parsing', () {
    test('reads access_token, token_type and expires_in relative to now', () {
      final token = OAuth2TokenService.parseTokenResponse(_response(200, tokenJson), now);
      expect(token.accessToken, 'tok_123');
      expect(token.tokenType, 'Bearer');
      expect(token.expiresAt, now.add(const Duration(seconds: 3600)));
    });

    test('missing expires_in yields a null expiry and a Bearer default', () {
      final token = OAuth2TokenService.parseTokenResponse(_response(200, '{"access_token":"tok"}'), now);
      expect(token.expiresAt, isNull);
      expect(token.tokenType, 'Bearer');
    });

    test('form-encoded responses are parsed as a fallback', () {
      final token = OAuth2TokenService.parseTokenResponse(
        _response(200, 'access_token=form_tok&token_type=bearer&expires_in=60'),
        now,
      );
      expect(token.accessToken, 'form_tok');
      expect(token.expiresAt, now.add(const Duration(seconds: 60)));
    });

    test('error responses throw with the server-provided description', () {
      expect(
        () => OAuth2TokenService.parseTokenResponse(
          _response(400, '{"error":"invalid_client","error_description":"Client authentication failed"}'),
          now,
        ),
        throwsA(predicate((e) => e is OAuth2TokenException && e.message == 'Client authentication failed')),
      );
    });

    test('a 2xx without access_token still throws', () {
      expect(
        () => OAuth2TokenService.parseTokenResponse(_response(200, '<html>oops</html>'), now),
        throwsA(isA<OAuth2TokenException>()),
      );
    });

    test('fetched token lands on RequestAuth via withOAuth2Token and round-trips through JSON', () async {
      final client = _FakeApiClient(_response(200, tokenJson));
      final token = await OAuth2TokenService(client, now: () => now).fetchToken(clientCredentials);
      final updated = clientCredentials.withOAuth2Token(token.accessToken, token.expiresAt);

      expect(updated.hasOAuth2Token, isTrue);
      expect(updated.isOAuth2TokenExpiredAt(now), isFalse);
      expect(updated.isOAuth2TokenExpiredAt(now.add(const Duration(hours: 2))), isTrue);

      final restored = RequestAuth.fromJson(jsonDecode(jsonEncode(updated.toJson())) as Map<String, dynamic>);
      expect(restored.type, AuthType.oauth2);
      expect(restored.oauth2AccessToken, 'tok_123');
      expect(restored.oauth2TokenExpiry, updated.oauth2TokenExpiry);
      expect(restored.oauth2ClientSecret, 's3cret');
    });
  });

  group('authorization input', () {
    OAuth2AuthorizationResponse parse(String pasted) => OAuth2TokenService.parseAuthorizationInput(pasted);

    test('a bare code is trimmed and otherwise left alone', () {
      expect(parse('  abc123 \n').code, 'abc123');
      expect(parse('4/0AbCd+x').code, '4/0AbCd+x');
      expect(parse('abc123').state, isNull);
    });

    test('a code copied from the address bar is percent-decoded exactly once', () {
      expect(parse('4%2F0AbCd').code, '4/0AbCd');
    });

    test('the code and state are taken from a pasted redirect URL', () {
      final response = parse('http://localhost:8080/callback?state=xyz&code=4%2F0AbCd%2Bx&scope=read#frag');
      expect(response.code, '4/0AbCd+x');
      expect(response.state, 'xyz');
    });

    test('a pasted query string works without the URL in front of it', () {
      final response = parse('code=abc&state=xyz');
      expect(response.code, 'abc');
      expect(response.state, 'xyz');
    });

    test('a redirect whose code is empty yields an empty code', () {
      expect(parse('https://app.example/cb?code=&state=s').code, isEmpty);
    });

    test('malformed percent escapes are passed through instead of throwing', () {
      expect(parse('abc%').code, 'abc%');
      expect(parse('abc%zz').code, 'abc%zz');
    });
  });

  group('refresh token', () {
    test('refresh_token is read from the token response', () {
      final token = OAuth2TokenService.parseTokenResponse(
        _response(200, '{"access_token":"a","refresh_token":"r1","expires_in":60}'),
        now,
      );
      expect(token.refreshToken, 'r1');
    });

    test('a response without refresh_token keeps the previous one, if any', () {
      final response = _response(200, '{"access_token":"a"}');
      expect(OAuth2TokenService.parseTokenResponse(response, now).refreshToken, isNull);
      expect(OAuth2TokenService.parseTokenResponse(response, now, previousRefreshToken: 'old').refreshToken, 'old');
    });

    test('a rotated refresh_token replaces the previous one', () {
      final token = OAuth2TokenService.parseTokenResponse(
        _response(200, '{"access_token":"a","refresh_token":"new"}'),
        now,
        previousRefreshToken: 'old',
      );
      expect(token.refreshToken, 'new');
    });

    test('refreshToken posts the refresh grant with client credentials and keeps the old refresh token', () async {
      final client = _FakeApiClient(_response(200, tokenJson));
      final auth = clientCredentials.withOAuth2Token('stale', now, refreshToken: 'r/1');
      final token = await OAuth2TokenService(client, now: () => now).refreshToken(auth);

      final spec = client.lastSpec!;
      expect(spec.headers['Authorization'], 'Basic ${base64Encode(utf8.encode('my-client:s3cret'))}');
      expect(_bodyOf(spec), startsWith('grant_type=refresh_token&refresh_token=r%2F1'));
      expect(token.accessToken, 'tok_123');
      expect(token.refreshToken, 'r/1');
    });

    test('RequestAuth keeps the refresh token through copyWith and JSON; clearing the token drops it', () {
      final auth = clientCredentials.withOAuth2Token('acc', now, refreshToken: 'ref');
      expect(auth.hasOAuth2RefreshToken, isTrue);
      expect(auth.copyWith(oauth2Scope: 'other').oauth2RefreshToken, 'ref');

      final restored = RequestAuth.fromJson(jsonDecode(jsonEncode(auth.toJson())) as Map<String, dynamic>);
      expect(restored.oauth2RefreshToken, 'ref');

      expect(auth.clearOAuth2Token().hasOAuth2RefreshToken, isFalse);
      expect(RequestAuth.fromJson(const {'type': 'oauth2'}).oauth2RefreshToken, isEmpty);
    });
  });

  group('network options from the settings', () {
    const custom = AppSettings(
      requestTimeoutSeconds: 12,
      followRedirects: false,
      maxRedirects: 3,
      verifySsl: false,
      maxResponseSizeMb: 2,
      proxy: ProxySettings(mode: ProxyMode.custom, host: 'proxy.local', port: 3128, bypass: 'localhost'),
    );

    void expectCustom(ApiRequestOptions options) {
      expect(options.timeout, const Duration(seconds: 12));
      expect(options.followRedirects, isFalse);
      expect(options.maxRedirects, 3);
      expect(options.verifySsl, isFalse);
      expect(options.maxResponseBytes, 2 * 1024 * 1024);
      expect(options.proxy, const ProxyConfig(mode: ProxyMode.custom, host: 'proxy.local', port: 3128, bypass: ['localhost']));
    }

    test('a token fetch goes out with the proxy, SSL, timeout and redirect settings of a normal send', () async {
      final client = _FakeApiClient(_response(200, tokenJson));

      await OAuth2TokenService(client, settings: FakeSettingsRepository(custom), now: () => now)
          .fetchToken(clientCredentials);

      expectCustom(client.lastSpec!.options);
    });

    test('so do the authorization code exchange and the refresh', () async {
      final client = _FakeApiClient(_response(200, tokenJson));
      final service = OAuth2TokenService(client, settings: FakeSettingsRepository(custom), now: () => now);

      await service.exchangeAuthorizationCode(clientCredentials, code: 'CODE', codeVerifier: 'VERIFIER');
      expectCustom(client.lastSpec!.options);
      client.lastSpec = null;
      await service.refreshToken(clientCredentials.withOAuth2Token('stale', now, refreshToken: 'r1'));
      expectCustom(client.lastSpec!.options);
    });

    test('without settings the client defaults apply, as before', () async {
      final client = _FakeApiClient(_response(200, tokenJson));

      await OAuth2TokenService(client, now: () => now).fetchToken(clientCredentials);

      final options = client.lastSpec!.options;
      expect(options.timeout, const Duration(seconds: 30));
      expect(options.followRedirects, isTrue);
      expect(options.maxRedirects, 10);
      expect(options.verifySsl, isTrue);
      expect(options.proxy, ProxyConfig.system);
      expect(options.maxResponseBytes, isNull);
    });

    test('the settings are read on every request, so a change applies to the next token fetch', () async {
      final client = _FakeApiClient(_response(200, tokenJson));
      final settings = FakeSettingsRepository();
      final service = OAuth2TokenService(client, settings: settings, now: () => now);

      await service.fetchToken(clientCredentials);
      expect(client.lastSpec!.options.verifySsl, isTrue);
      settings.changeElsewhere(const AppSettings(verifySsl: false, requestTimeoutSeconds: 0, maxResponseSizeMb: 0));
      await service.fetchToken(clientCredentials);

      final options = client.lastSpec!.options;
      expect(options.verifySsl, isFalse);
      expect(options.timeout, isNull, reason: '0 seconds waits forever');
      expect(options.maxResponseBytes, isNull, reason: '0 MB keeps the whole body');
    });

    test('the settings change how the request is sent, never what it says', () async {
      final plain = _FakeApiClient(_response(200, tokenJson));
      final configured = _FakeApiClient(_response(200, tokenJson));

      await OAuth2TokenService(plain, now: () => now).fetchToken(clientCredentials);
      await OAuth2TokenService(configured, settings: FakeSettingsRepository(custom), now: () => now)
          .fetchToken(clientCredentials);

      expect(configured.lastSpec!.method, plain.lastSpec!.method);
      expect(configured.lastSpec!.url, plain.lastSpec!.url);
      expect(configured.lastSpec!.headers, plain.lastSpec!.headers);
      expect(_bodyOf(configured.lastSpec!), _bodyOf(plain.lastSpec!));
    });

    test('buildTokenRequest carries the options it is given and defaults to the client defaults', () {
      const options = ApiRequestOptions(timeout: Duration(seconds: 3), verifySsl: false);

      final given = OAuth2TokenService.buildTokenRequest(clientCredentials, const {'grant_type': 'client_credentials'}, options: options);
      final none = OAuth2TokenService.buildTokenRequest(clientCredentials, const {'grant_type': 'client_credentials'});

      expect(given.options, same(options));
      expect(none.options.verifySsl, isTrue);
      expect(none.options.timeout, const Duration(seconds: 30));
    });
  });
}
