enum AuthType {
  none,
  inherit,
  apiKey,
  bearer,
  basic,
  digest,
  awsSignatureV4,
  jwtBearer,
  hmac,
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
        AuthType.hmac => 'HMAC signature',
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

/// The hash behind an [AuthType.hmac] signature.
enum HmacAlgorithm {
  sha1,
  sha256,
  sha512;

  String get label => switch (this) {
        HmacAlgorithm.sha1 => 'HMAC-SHA1',
        HmacAlgorithm.sha256 => 'HMAC-SHA256',
        HmacAlgorithm.sha512 => 'HMAC-SHA512',
      };
}

/// How the raw HMAC bytes are written into the header.
enum HmacEncoding {
  hex,
  base64;

  String get label => switch (this) {
        HmacEncoding.hex => 'Hex',
        HmacEncoding.base64 => 'Base64',
      };
}

/// Where the `{timestamp}` of an [AuthType.hmac] signature comes from.
enum HmacTimestampSource {
  /// The unix time, in seconds, at the moment of the send.
  now,

  /// A value typed in, so a signature can be repeated and compared.
  fixed;

  String get label => switch (this) {
        HmacTimestampSource.now => 'Current time (unix seconds)',
        HmacTimestampSource.fixed => 'Fixed value',
      };
}

/// The webhook scheme an [AuthType.hmac] auth was started from. A preset only fills the fields in;
/// [generic] is a scheme of one's own and keeps whatever is set.
enum HmacPreset {
  github,
  stripe,
  shopify,
  slack,
  generic;

  String get label => switch (this) {
        HmacPreset.github => 'GitHub webhook',
        HmacPreset.stripe => 'Stripe webhook',
        HmacPreset.shopify => 'Shopify webhook',
        HmacPreset.slack => 'Slack request',
        HmacPreset.generic => 'Generic (custom)',
      };
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
