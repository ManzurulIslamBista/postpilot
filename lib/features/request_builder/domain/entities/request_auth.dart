import 'dart:convert';
import '../../../../core/enums/auth_type.dart';
import '../../../auth_renewal/domain/entities/relogin_config.dart';

final class RequestAuth {
  final AuthType type;

  // API Key
  final String apiKeyName;
  final String apiKeyValue;
  final ApiKeyLocation apiKeyLocation;

  // Bearer
  final String bearerToken;

  // Basic & Digest share the same username/password fields
  final String basicUsername;
  final String basicPassword;

  // AWS Signature v4
  final String awsAccessKey;
  final String awsSecretKey;
  final String awsRegion;
  final String awsService;
  final String awsSessionToken;

  // JWT Bearer
  final String jwtSecret;
  final JwtAlgorithm jwtAlgorithm;
  final String jwtPayload;
  final String jwtHeaderPrefix;

  // OAuth 2.0
  final OAuth2GrantType oauth2GrantType;
  final String oauth2AccessTokenUrl;
  final String oauth2AuthorizationUrl;
  final String oauth2RedirectUri;
  final String oauth2ClientId;
  final String oauth2ClientSecret;
  final OAuth2ClientAuthentication oauth2ClientAuthentication;
  final String oauth2Scope;
  final String oauth2Username;
  final String oauth2Password;
  final String oauth2Audience;
  final String oauth2AccessToken;
  final String oauth2RefreshToken;
  final DateTime? oauth2TokenExpiry;

  /// Whether a send gets (or renews) the OAuth 2.0 token by itself when it is missing or about to expire.
  /// On unless the user switched it off in the Auth tab.
  final bool oauth2AutoRenew;

  /// "On 401/403 run this login request first, then retry once", for every request below the level this
  /// auth belongs to (the collection, or a folder). Independent of [type]: it also serves a Bearer token
  /// that a login request writes into a variable. Null when none is set.
  final ReloginConfig? relogin;

  const RequestAuth({
    this.type = AuthType.inherit,
    this.apiKeyName = '',
    this.apiKeyValue = '',
    this.apiKeyLocation = ApiKeyLocation.header,
    this.bearerToken = '',
    this.basicUsername = '',
    this.basicPassword = '',
    this.awsAccessKey = '',
    this.awsSecretKey = '',
    this.awsRegion = 'us-east-1',
    this.awsService = 'execute-api',
    this.awsSessionToken = '',
    this.jwtSecret = '',
    this.jwtAlgorithm = JwtAlgorithm.hs256,
    this.jwtPayload = '{}',
    this.jwtHeaderPrefix = 'Bearer',
    this.oauth2GrantType = OAuth2GrantType.clientCredentials,
    this.oauth2AccessTokenUrl = '',
    this.oauth2AuthorizationUrl = '',
    this.oauth2RedirectUri = '',
    this.oauth2ClientId = '',
    this.oauth2ClientSecret = '',
    this.oauth2ClientAuthentication = OAuth2ClientAuthentication.basicHeader,
    this.oauth2Scope = '',
    this.oauth2Username = '',
    this.oauth2Password = '',
    this.oauth2Audience = '',
    this.oauth2AccessToken = '',
    this.oauth2RefreshToken = '',
    this.oauth2TokenExpiry,
    this.oauth2AutoRenew = true,
    this.relogin,
  });

  RequestAuth copyWith({
    AuthType? type,
    String? apiKeyName,
    String? apiKeyValue,
    ApiKeyLocation? apiKeyLocation,
    String? bearerToken,
    String? basicUsername,
    String? basicPassword,
    String? awsAccessKey,
    String? awsSecretKey,
    String? awsRegion,
    String? awsService,
    String? awsSessionToken,
    String? jwtSecret,
    JwtAlgorithm? jwtAlgorithm,
    String? jwtPayload,
    String? jwtHeaderPrefix,
    OAuth2GrantType? oauth2GrantType,
    String? oauth2AccessTokenUrl,
    String? oauth2AuthorizationUrl,
    String? oauth2RedirectUri,
    String? oauth2ClientId,
    String? oauth2ClientSecret,
    OAuth2ClientAuthentication? oauth2ClientAuthentication,
    String? oauth2Scope,
    String? oauth2Username,
    String? oauth2Password,
    String? oauth2Audience,
    bool? oauth2AutoRenew,
  }) =>
      RequestAuth(
        type: type ?? this.type,
        apiKeyName: apiKeyName ?? this.apiKeyName,
        apiKeyValue: apiKeyValue ?? this.apiKeyValue,
        apiKeyLocation: apiKeyLocation ?? this.apiKeyLocation,
        bearerToken: bearerToken ?? this.bearerToken,
        basicUsername: basicUsername ?? this.basicUsername,
        basicPassword: basicPassword ?? this.basicPassword,
        awsAccessKey: awsAccessKey ?? this.awsAccessKey,
        awsSecretKey: awsSecretKey ?? this.awsSecretKey,
        awsRegion: awsRegion ?? this.awsRegion,
        awsService: awsService ?? this.awsService,
        awsSessionToken: awsSessionToken ?? this.awsSessionToken,
        jwtSecret: jwtSecret ?? this.jwtSecret,
        jwtAlgorithm: jwtAlgorithm ?? this.jwtAlgorithm,
        jwtPayload: jwtPayload ?? this.jwtPayload,
        jwtHeaderPrefix: jwtHeaderPrefix ?? this.jwtHeaderPrefix,
        oauth2GrantType: oauth2GrantType ?? this.oauth2GrantType,
        oauth2AccessTokenUrl: oauth2AccessTokenUrl ?? this.oauth2AccessTokenUrl,
        oauth2AuthorizationUrl: oauth2AuthorizationUrl ?? this.oauth2AuthorizationUrl,
        oauth2RedirectUri: oauth2RedirectUri ?? this.oauth2RedirectUri,
        oauth2ClientId: oauth2ClientId ?? this.oauth2ClientId,
        oauth2ClientSecret: oauth2ClientSecret ?? this.oauth2ClientSecret,
        oauth2ClientAuthentication: oauth2ClientAuthentication ?? this.oauth2ClientAuthentication,
        oauth2Scope: oauth2Scope ?? this.oauth2Scope,
        oauth2Username: oauth2Username ?? this.oauth2Username,
        oauth2Password: oauth2Password ?? this.oauth2Password,
        oauth2Audience: oauth2Audience ?? this.oauth2Audience,
        oauth2AccessToken: oauth2AccessToken,
        oauth2RefreshToken: oauth2RefreshToken,
        oauth2TokenExpiry: oauth2TokenExpiry,
        oauth2AutoRenew: oauth2AutoRenew ?? this.oauth2AutoRenew,
        relogin: relogin,
      );

  /// [relogin] may be null here, which [copyWith] cannot express.
  RequestAuth withRelogin(ReloginConfig? relogin) => RequestAuth(
        type: type,
        apiKeyName: apiKeyName,
        apiKeyValue: apiKeyValue,
        apiKeyLocation: apiKeyLocation,
        bearerToken: bearerToken,
        basicUsername: basicUsername,
        basicPassword: basicPassword,
        awsAccessKey: awsAccessKey,
        awsSecretKey: awsSecretKey,
        awsRegion: awsRegion,
        awsService: awsService,
        awsSessionToken: awsSessionToken,
        jwtSecret: jwtSecret,
        jwtAlgorithm: jwtAlgorithm,
        jwtPayload: jwtPayload,
        jwtHeaderPrefix: jwtHeaderPrefix,
        oauth2GrantType: oauth2GrantType,
        oauth2AccessTokenUrl: oauth2AccessTokenUrl,
        oauth2AuthorizationUrl: oauth2AuthorizationUrl,
        oauth2RedirectUri: oauth2RedirectUri,
        oauth2ClientId: oauth2ClientId,
        oauth2ClientSecret: oauth2ClientSecret,
        oauth2ClientAuthentication: oauth2ClientAuthentication,
        oauth2Scope: oauth2Scope,
        oauth2Username: oauth2Username,
        oauth2Password: oauth2Password,
        oauth2Audience: oauth2Audience,
        oauth2AccessToken: oauth2AccessToken,
        oauth2RefreshToken: oauth2RefreshToken,
        oauth2TokenExpiry: oauth2TokenExpiry,
        oauth2AutoRenew: oauth2AutoRenew,
        relogin: relogin,
      );

  /// The cached tokens and their expiry always change together, and `null`
  /// expiry is meaningful (server reported none), so this sits outside
  /// [copyWith].
  RequestAuth withOAuth2Token(String accessToken, DateTime? expiry, {String refreshToken = ''}) => RequestAuth(
        type: type,
        apiKeyName: apiKeyName,
        apiKeyValue: apiKeyValue,
        apiKeyLocation: apiKeyLocation,
        bearerToken: bearerToken,
        basicUsername: basicUsername,
        basicPassword: basicPassword,
        awsAccessKey: awsAccessKey,
        awsSecretKey: awsSecretKey,
        awsRegion: awsRegion,
        awsService: awsService,
        awsSessionToken: awsSessionToken,
        jwtSecret: jwtSecret,
        jwtAlgorithm: jwtAlgorithm,
        jwtPayload: jwtPayload,
        jwtHeaderPrefix: jwtHeaderPrefix,
        oauth2GrantType: oauth2GrantType,
        oauth2AccessTokenUrl: oauth2AccessTokenUrl,
        oauth2AuthorizationUrl: oauth2AuthorizationUrl,
        oauth2RedirectUri: oauth2RedirectUri,
        oauth2ClientId: oauth2ClientId,
        oauth2ClientSecret: oauth2ClientSecret,
        oauth2ClientAuthentication: oauth2ClientAuthentication,
        oauth2Scope: oauth2Scope,
        oauth2Username: oauth2Username,
        oauth2Password: oauth2Password,
        oauth2Audience: oauth2Audience,
        oauth2AccessToken: accessToken,
        oauth2RefreshToken: refreshToken,
        oauth2TokenExpiry: expiry,
        oauth2AutoRenew: oauth2AutoRenew,
        relogin: relogin,
      );

  RequestAuth clearOAuth2Token() => withOAuth2Token('', null);

  /// This auth with the OAuth 2.0 token (and refresh token) of [latest] put in, when [latest] holds a newer
  /// one: this has none, or [latest] expires later. Null when there is nothing newer. How an open request
  /// picks up a token that was renewed behind its back without losing the edits made to the rest of its auth.
  RequestAuth? takeNewerOAuth2Token(RequestAuth latest) {
    if (type != AuthType.oauth2 || latest.type != AuthType.oauth2 || !latest.hasOAuth2Token) return null;
    if (latest.oauth2AccessToken == oauth2AccessToken) return null;
    final mine = oauth2TokenExpiry;
    final theirs = latest.oauth2TokenExpiry;
    final newer = !hasOAuth2Token || (theirs != null && (mine == null || theirs.isAfter(mine)));
    if (!newer) return null;
    return withOAuth2Token(latest.oauth2AccessToken, theirs, refreshToken: latest.oauth2RefreshToken);
  }

  bool get hasOAuth2Token => oauth2AccessToken.isNotEmpty;

  bool get hasOAuth2RefreshToken => oauth2RefreshToken.isNotEmpty;

  bool isOAuth2TokenExpiredAt(DateTime now) {
    final expiry = oauth2TokenExpiry;
    return expiry != null && !now.isBefore(expiry);
  }

  /// [AuthType.inherit] resolves to the collection's auth when one exists;
  /// every other type is already concrete.
  RequestAuth resolveInherited(RequestAuth? parent) => type == AuthType.inherit && parent != null ? parent : this;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'apiKeyName': apiKeyName,
        'apiKeyValue': apiKeyValue,
        'apiKeyLocation': apiKeyLocation.name,
        'bearerToken': bearerToken,
        'basicUsername': basicUsername,
        'basicPassword': basicPassword,
        'awsAccessKey': awsAccessKey,
        'awsSecretKey': awsSecretKey,
        'awsRegion': awsRegion,
        'awsService': awsService,
        'awsSessionToken': awsSessionToken,
        'jwtSecret': jwtSecret,
        'jwtAlgorithm': jwtAlgorithm.name,
        'jwtPayload': jwtPayload,
        'jwtHeaderPrefix': jwtHeaderPrefix,
        'oauth2GrantType': oauth2GrantType.name,
        'oauth2AccessTokenUrl': oauth2AccessTokenUrl,
        'oauth2AuthorizationUrl': oauth2AuthorizationUrl,
        'oauth2RedirectUri': oauth2RedirectUri,
        'oauth2ClientId': oauth2ClientId,
        'oauth2ClientSecret': oauth2ClientSecret,
        'oauth2ClientAuthentication': oauth2ClientAuthentication.name,
        'oauth2Scope': oauth2Scope,
        'oauth2Username': oauth2Username,
        'oauth2Password': oauth2Password,
        'oauth2Audience': oauth2Audience,
        'oauth2AccessToken': oauth2AccessToken,
        'oauth2RefreshToken': oauth2RefreshToken,
        'oauth2TokenExpiry': oauth2TokenExpiry?.toIso8601String(),
        // Written only when they differ from the defaults, so auth saved before they existed reads back identical.
        if (!oauth2AutoRenew) 'oauth2AutoRenew': false,
        if (relogin != null) 'relogin': relogin!.toJson(),
      };

  /// Tolerates JSON written before any given key existed: every field falls
  /// back to its constructor default. A missing `type` means "no auth".
  factory RequestAuth.fromJson(Map<String, dynamic> map) => RequestAuth(
        type: _enumByName(AuthType.values, map['type'], AuthType.none),
        apiKeyName: map['apiKeyName'] as String? ?? '',
        apiKeyValue: map['apiKeyValue'] as String? ?? '',
        apiKeyLocation: _enumByName(ApiKeyLocation.values, map['apiKeyLocation'], ApiKeyLocation.header),
        bearerToken: map['bearerToken'] as String? ?? '',
        basicUsername: map['basicUsername'] as String? ?? '',
        basicPassword: map['basicPassword'] as String? ?? '',
        awsAccessKey: map['awsAccessKey'] as String? ?? '',
        awsSecretKey: map['awsSecretKey'] as String? ?? '',
        awsRegion: map['awsRegion'] as String? ?? 'us-east-1',
        awsService: map['awsService'] as String? ?? 'execute-api',
        awsSessionToken: map['awsSessionToken'] as String? ?? '',
        jwtSecret: map['jwtSecret'] as String? ?? '',
        jwtAlgorithm: _enumByName(JwtAlgorithm.values, map['jwtAlgorithm'], JwtAlgorithm.hs256),
        jwtPayload: map['jwtPayload'] as String? ?? '{}',
        jwtHeaderPrefix: map['jwtHeaderPrefix'] as String? ?? 'Bearer',
        oauth2GrantType: _enumByName(OAuth2GrantType.values, map['oauth2GrantType'], OAuth2GrantType.clientCredentials),
        oauth2AccessTokenUrl: map['oauth2AccessTokenUrl'] as String? ?? '',
        oauth2AuthorizationUrl: map['oauth2AuthorizationUrl'] as String? ?? '',
        oauth2RedirectUri: map['oauth2RedirectUri'] as String? ?? '',
        oauth2ClientId: map['oauth2ClientId'] as String? ?? '',
        oauth2ClientSecret: map['oauth2ClientSecret'] as String? ?? '',
        oauth2ClientAuthentication: _enumByName(
          OAuth2ClientAuthentication.values,
          map['oauth2ClientAuthentication'],
          OAuth2ClientAuthentication.basicHeader,
        ),
        oauth2Scope: map['oauth2Scope'] as String? ?? '',
        oauth2Username: map['oauth2Username'] as String? ?? '',
        oauth2Password: map['oauth2Password'] as String? ?? '',
        oauth2Audience: map['oauth2Audience'] as String? ?? '',
        oauth2AccessToken: map['oauth2AccessToken'] as String? ?? '',
        oauth2RefreshToken: map['oauth2RefreshToken'] as String? ?? '',
        oauth2TokenExpiry: DateTime.tryParse(map['oauth2TokenExpiry'] as String? ?? ''),
        oauth2AutoRenew: map['oauth2AutoRenew'] as bool? ?? true,
        relogin: ReloginConfig.fromJson(map['relogin']),
      );

  String toJsonString() => jsonEncode(toJson());

  /// Decodes the string [CollectionAuthRepository] stores; null in, null out.
  static RequestAuth? fromJsonString(String? json) =>
      json == null ? null : RequestAuth.fromJson(jsonDecode(json) as Map<String, dynamic>);

  static T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback);

  static const none = RequestAuth(type: AuthType.none);
}
