enum AuthType {
  none,
  inherit,
  apiKey,
  bearer,
  basic,
  digest,
  awsSignatureV4,
  jwtBearer,
  oauth2;

  String get label => switch (this) {
        AuthType.none => 'No Auth',
        AuthType.inherit => 'Inherit from parent',
        AuthType.apiKey => 'API Key',
        AuthType.bearer => 'Bearer Token',
        AuthType.basic => 'Basic Auth',
        AuthType.digest => 'Digest Auth',
        AuthType.awsSignatureV4 => 'AWS Signature v4',
        AuthType.jwtBearer => 'JWT Bearer',
        AuthType.oauth2 => 'OAuth 2.0',
      };
}

enum ApiKeyLocation { header, query }

enum JwtAlgorithm {
  hs256,
  hs384,
  hs512;

  String get label => name.toUpperCase();
}

enum OAuth2GrantType {
  clientCredentials,
  password,
  authorizationCodePkce;

  String get label => switch (this) {
        OAuth2GrantType.clientCredentials => 'Client Credentials',
        OAuth2GrantType.password => 'Password Credentials',
        OAuth2GrantType.authorizationCodePkce => 'Authorization Code (PKCE)',
      };
}

/// How `client_id`/`client_secret` reach the token endpoint (RFC 6749 §2.3.1).
enum OAuth2ClientAuthentication {
  basicHeader,
  body;

  String get label => switch (this) {
        OAuth2ClientAuthentication.basicHeader => 'Basic Auth header',
        OAuth2ClientAuthentication.body => 'Request body',
      };
}
