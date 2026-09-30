import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_http_response.dart';
import '../../../settings/domain/entities/effective_request_options.dart';
import '../../../settings/domain/repositories/settings_repository.dart';
import '../entities/request_auth.dart';

final class OAuth2Token {
  final String accessToken;
  final String tokenType;
  final DateTime? expiresAt;
  final String? refreshToken;

  const OAuth2Token({required this.accessToken, required this.tokenType, required this.expiresAt, this.refreshToken});
}

/// The part of the authorization redirect the token exchange needs. [state]
/// is only known when the user pasted the whole redirect URL.
final class OAuth2AuthorizationResponse {
  final String code;
  final String? state;

  const OAuth2AuthorizationResponse({required this.code, this.state});
}

final class OAuth2PkcePair {
  final String verifier;
  final String challenge;

  const OAuth2PkcePair({required this.verifier, required this.challenge});
}

final class OAuth2TokenException implements Exception {
  final String message;
  const OAuth2TokenException(this.message);

  @override
  String toString() => message;
}

/// Talks to an OAuth 2.0 authorization server for a [RequestAuth] of type
/// [AuthType.oauth2]. Fields are used verbatim — resolve `{{variables}}`
/// before calling. The Authorization Code + PKCE flow is split in two
/// because the app runs no redirect listener: the UI opens
/// [buildAuthorizationUrl] in a browser and the user pastes the `code` (or
/// the whole redirect URL, see [parseAuthorizationInput]) back into
/// [exchangeAuthorizationCode].
///
/// With [settings] a token request goes out with the same network options a
/// normal send has (proxy, SSL verification, timeout, redirects), read afresh
/// on every request; without them the client's defaults apply.
final class OAuth2TokenService {
  final ApiClient _apiClient;
  final SettingsRepository? _settings;
  final DateTime Function() _now;
  final Random _random;

  OAuth2TokenService(this._apiClient, {this._settings, DateTime Function()? now, Random? random})
      : _now = now ?? DateTime.now,
        _random = random ?? Random.secure();

  /// Client Credentials and Password grants complete in a single POST.
  Future<OAuth2Token> fetchToken(RequestAuth auth) async => switch (auth.oauth2GrantType) {
        OAuth2GrantType.clientCredentials => _requestToken(auth, {'grant_type': 'client_credentials'}),
        OAuth2GrantType.password => _requestToken(auth, {
            'grant_type': 'password',
            'username': auth.oauth2Username,
            'password': auth.oauth2Password,
          }),
        OAuth2GrantType.authorizationCodePkce => throw const OAuth2TokenException(
            'Authorization Code needs a browser round-trip: open the authorization URL, then exchange the code.',
          ),
      };

  OAuth2PkcePair generatePkcePair() {
    final verifier = _randomUrlSafe(32);
    return OAuth2PkcePair(verifier: verifier, challenge: pkceChallenge(verifier));
  }

  String generateState() => _randomUrlSafe(16);

  /// RFC 7636 S256: `base64url(sha256(ascii(verifier)))` without padding.
  static String pkceChallenge(String verifier) => _base64UrlNoPad(sha256.convert(ascii.encode(verifier)).bytes);

  Uri buildAuthorizationUrl(RequestAuth auth, {required String codeChallenge, required String state}) {
    final base = Uri.parse(auth.oauth2AuthorizationUrl);
    return base.replace(queryParameters: {
      ...base.queryParameters,
      'response_type': 'code',
      'client_id': auth.oauth2ClientId,
      if (auth.oauth2RedirectUri.isNotEmpty) 'redirect_uri': auth.oauth2RedirectUri,
      if (auth.oauth2Scope.isNotEmpty) 'scope': auth.oauth2Scope,
      if (auth.oauth2Audience.isNotEmpty) 'audience': auth.oauth2Audience,
      'state': state,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    });
  }

  Future<OAuth2Token> exchangeAuthorizationCode(
    RequestAuth auth, {
    required String code,
    required String codeVerifier,
  }) =>
      _requestToken(auth, {
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': codeVerifier,
        if (auth.oauth2RedirectUri.isNotEmpty) 'redirect_uri': auth.oauth2RedirectUri,
      });

  /// RFC 6749 §6. A response without a new `refresh_token` means the old one
  /// stays valid, so it is carried over.
  Future<OAuth2Token> refreshToken(RequestAuth auth) => _requestToken(
        auth,
        {'grant_type': 'refresh_token', 'refresh_token': auth.oauth2RefreshToken},
        previousRefreshToken: auth.oauth2RefreshToken,
      );

  Future<OAuth2Token> _requestToken(
    RequestAuth auth,
    Map<String, String> grantFields, {
    String? previousRefreshToken,
  }) async {
    final response = await _apiClient.send(buildTokenRequest(auth, grantFields, options: _networkOptions()));
    return parseTokenResponse(response, _now(), previousRefreshToken: previousRefreshToken);
  }

  /// A token request is no saved request, so no per-request overrides apply.
  ApiRequestOptions _networkOptions() {
    final settings = _settings;
    if (settings == null) return const ApiRequestOptions();
    return EffectiveRequestOptions.resolve(settings.current, null).toApiOptions();
  }

  /// The exact POST sent to `accessTokenUrl`, with the network [options] it is
  /// sent with. Client credentials go in either the Basic header or the body,
  /// never both — servers such as Okta reject a request that carries them
  /// twice. A client without a secret (public PKCE client) always identifies
  /// itself in the body.
  static ApiRequestSpec buildTokenRequest(
    RequestAuth auth,
    Map<String, String> grantFields, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) {
    final useBasicHeader =
        auth.oauth2ClientAuthentication == OAuth2ClientAuthentication.basicHeader && auth.oauth2ClientSecret.isNotEmpty;
    final fields = {
      ...grantFields,
      if (auth.oauth2Scope.isNotEmpty) 'scope': auth.oauth2Scope,
      if (auth.oauth2Audience.isNotEmpty) 'audience': auth.oauth2Audience,
      if (!useBasicHeader && auth.oauth2ClientId.isNotEmpty) 'client_id': auth.oauth2ClientId,
      if (!useBasicHeader && auth.oauth2ClientSecret.isNotEmpty) 'client_secret': auth.oauth2ClientSecret,
    };
    return ApiRequestSpec(
      method: 'POST',
      url: auth.oauth2AccessTokenUrl,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
        if (useBasicHeader)
          'Authorization': 'Basic ${base64Encode(utf8.encode('${auth.oauth2ClientId}:${auth.oauth2ClientSecret}'))}',
      },
      body: utf8.encode(encodeFormBody(fields)),
      options: options,
    );
  }

  static String encodeFormBody(Map<String, String> fields) => fields.entries
      .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');

  /// What the user pastes after signing in is often not the bare `code`: it
  /// may be the code as copied from the address bar (still percent-encoded)
  /// or the whole redirect URL. [encodeFormBody] would encode either a second
  /// time and the server would reject it as an invalid grant.
  static OAuth2AuthorizationResponse parseAuthorizationInput(String pasted) {
    final input = pasted.trim();
    try {
      if (input.contains('code=')) {
        final params = Uri.parse(input.contains('?') ? input : '?$input').queryParameters;
        return OAuth2AuthorizationResponse(code: params['code'] ?? '', state: params['state']);
      }
      return OAuth2AuthorizationResponse(code: input.contains('%') ? Uri.decodeComponent(input) : input);
    } on FormatException {
      return OAuth2AuthorizationResponse(code: input);
    } on ArgumentError {
      return OAuth2AuthorizationResponse(code: input);
    }
  }

  /// Accepts the JSON shape from RFC 6749 §5.1 and, as a fallback, the
  /// form-encoded shape some older providers still return. [previousRefreshToken]
  /// stands in when a refresh response does not issue a new `refresh_token`.
  static OAuth2Token parseTokenResponse(ApiHttpResponse response, DateTime now, {String? previousRefreshToken}) {
    final map = _decodeBody(utf8.decode(response.bodyBytes, allowMalformed: true));
    final accessToken = map['access_token'];
    if (!response.isSuccess || accessToken is! String || accessToken.isEmpty) {
      final error = map['error_description'] ?? map['error'];
      throw OAuth2TokenException(
        error is String && error.isNotEmpty
            ? error
            : 'Token endpoint returned ${response.statusCode} without an access_token.',
      );
    }
    final expiresIn = map['expires_in'];
    final seconds = expiresIn is num ? expiresIn.toInt() : int.tryParse('$expiresIn');
    final refreshToken = map['refresh_token'];
    return OAuth2Token(
      accessToken: accessToken,
      tokenType: '${map['token_type'] ?? 'Bearer'}',
      expiresAt: seconds == null ? null : now.add(Duration(seconds: seconds)),
      refreshToken: refreshToken is String && refreshToken.isNotEmpty ? refreshToken : previousRefreshToken,
    );
  }

  static Map<String, dynamic> _decodeBody(String text) {
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    if (decoded is Map<String, dynamic>) return decoded;
    try {
      return Uri.splitQueryString(text);
    } on ArgumentError {
      return const {};
    }
  }

  String _randomUrlSafe(int byteLength) =>
      _base64UrlNoPad(List<int>.generate(byteLength, (_) => _random.nextInt(256)));

  static String _base64UrlNoPad(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
}
