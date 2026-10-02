/// Decides which names (variable keys, header names, parameter names, JSON
/// keys) and values look like credentials. Names are split into words
/// (`db_pass`, `dbPass` and `DB-PASS` are all `db`, `pass`) and matched as
/// whole words, so `token_url` or `password_reset_path` are not credentials
/// while `db_pass`, `bearer` and `access_key` are.
abstract final class SecretNames {
  static final _word = RegExp(r'[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+');

  static const _secretWords = {
    'token',
    'tokens',
    'secret',
    'secrets',
    'password',
    'passwd',
    'pwd',
    'pass',
    'passphrase',
    'apikey',
    'accesskey',
    'secretkey',
    'privatekey',
    'signingkey',
    'bearer',
    'jwt',
    'auth',
    'authorization',
    'credential',
    'credentials',
    'cookie',
    'cookies',
    'session',
    'sessionid',
  };

  /// `<prefix>_key` is a credential (`api_key`, `access_key`, `private_key`).
  static const _keyPrefixes = {'api', 'access', 'private', 'secret', 'signing', 'encryption', 'master', 'subscription'};

  /// A name ending in one of these describes where or how a credential is used,
  /// not the credential itself (`token_url`, `auth_type`, `password_reset_path`).
  static const _neutralTails = {'url', 'uri', 'endpoint', 'path', 'host', 'type', 'name', 'mode', 'method', 'scheme'};

  static final _customKeyHeader = RegExp(r'^x-.+-key$', caseSensitive: false);
  static final _placeholder = RegExp(r'\{\{[^{}]*\}\}');
  static final _scheme = RegExp(r'\b(bearer|basic|token|digest|apikey)\b', caseSensitive: false);

  static List<String> words(String name) => [for (final m in _word.allMatches(name)) m.group(0)!.toLowerCase()];

  /// A collection variable, form field or JSON key that holds a credential.
  static bool looksSecretKey(String name) {
    final parts = words(name);
    if (parts.isEmpty || _neutralTails.contains(parts.last)) return false;
    for (var i = 0; i < parts.length; i++) {
      if (_secretWords.contains(parts[i])) return true;
      if (i > 0 && parts[i] == 'key' && _keyPrefixes.contains(parts[i - 1])) return true;
    }
    return false;
  }

  /// A request header that carries a credential: `Authorization`,
  /// `Proxy-Authorization`, `Cookie`, `X-Api-Key`, `X-Custom-Key` and the like.
  static bool isSecretHeader(String name) => looksSecretKey(name) || _customKeyHeader.hasMatch(name.trim());

  /// A URL query parameter that carries a credential. Also a bare `key`
  /// (Google style) and signatures of signed URLs.
  static bool isSecretQuery(String name) {
    if (looksSecretKey(name)) return true;
    final parts = words(name);
    return parts.length == 1 && parts.single == 'key' || parts.contains('signature') || parts.contains('sig');
  }

  /// A value made only of `{{variable}}` references (and an auth scheme word
  /// such as `Bearer`): it holds no credential itself, so it may be committed.
  static bool isTemplateOnly(String value) =>
      _placeholder.hasMatch(value) && value.replaceAll(_placeholder, '').replaceAll(_scheme, '').trim().isEmpty;

  /// [value] holds text that must not be committed as it is.
  static bool hasLiteralSecret(String value) => value.isNotEmpty && !isTemplateOnly(value);
}
