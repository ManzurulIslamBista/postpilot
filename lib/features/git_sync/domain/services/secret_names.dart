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
    'passcode',
    'pin',
    'otp',
  };

  /// Names whose value is a credential even when it is a bare number in JSON
  /// (`"pin": 1234`). Narrower than [_secretWords]: counts such as `max_tokens`
  /// are far more common than numeric tokens, so those stay.
  static const _numericSecretWords = {'password', 'passwd', 'pwd', 'passphrase', 'passcode', 'pin', 'otp', 'secret'};

  /// A name ending in one of these is a quantity or an identifier of the credential, not the credential.
  static const _numericNeutralTails = {'ttl', 'expires', 'expiry', 'age', 'id', 'min', 'max'};

  /// `<prefix>_key` is a credential (`api_key`, `access_key`, `private_key`).
  static const _keyPrefixes = {'api', 'access', 'private', 'secret', 'signing', 'encryption', 'master', 'subscription'};

  /// A name ending in one of these describes where or how a credential is used,
  /// not the credential itself (`token_url`, `auth_type`, `password_reset_path`,
  /// `password_hint`, `password_length`).
  static const _neutralTails = {
    'url',
    'uri',
    'endpoint',
    'path',
    'host',
    'type',
    'name',
    'mode',
    'method',
    'scheme',
    'hint',
    'label',
    'placeholder',
    'length',
    'policy',
    'pattern',
    'regex',
    'strength',
    'count',
    'size',
    'limit',
  };

  static final _customKeyHeader = RegExp(r'^x-.+-key$', caseSensitive: false);
  static final _placeholder = RegExp(r'\{\{[^{}]*\}\}');
  static final _scheme = RegExp(r'\b(bearer|basic|token|digest|apikey)\b', caseSensitive: false);

  /// A credential that gives itself away, whatever it is called: a JWT, a
  /// Stripe, GitHub, GitLab, AWS, Slack or Google key, and the secret path of a
  /// Slack or Discord webhook.
  static final _knownToken = RegExp(
    r'\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]*'
    r'|\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{10,}'
    r'|\bgh[pousr]_[A-Za-z0-9]{20,}'
    r'|\bgithub_pat_[A-Za-z0-9_]{20,}'
    r'|\bglpat-[A-Za-z0-9_-]{16,}'
    r'|\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'
    r'|\bxox[abposr]-[A-Za-z0-9-]{10,}'
    r'|\bAIza[A-Za-z0-9_-]{30,}'
    r'|(?<=hooks\.slack\.com/services/)[A-Za-z0-9/_-]+'
    r'|(?<=discord\.com/api/webhooks/)[A-Za-z0-9/_-]+'
    r'|(?<=discordapp\.com/api/webhooks/)[A-Za-z0-9/_-]+',
  );
  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static final _opaque = RegExp(r'^[A-Za-z0-9_\-+/=.~]{20,}$');

  /// `my-collection-2024` and `report_final_v2`: words joined by one separator, which names things, not secrets.
  static final _slug = RegExp(r'^[a-z0-9]+(?:[-_][a-z0-9]+)+$');

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

  /// Whether a bare number under [name] is a credential (`"pin": 1234`).
  static bool isNumericSecretKey(String name) {
    final parts = words(name);
    if (parts.isEmpty || _neutralTails.contains(parts.last) || _numericNeutralTails.contains(parts.last)) return false;
    return parts.any(_numericSecretWords.contains);
  }

  /// A body key that holds a credential. A bare `key` (Google style) is one
  /// only when its [value] looks like a credential: `{"key": "color"}` is data.
  static bool isSecretBodyKey(String name, String value) {
    if (looksSecretKey(name)) return true;
    final parts = words(name);
    return parts.length == 1 && parts.single == 'key' && looksLikeCredential(value);
  }

  /// [value] looks like a generated credential: a known token shape, or a long
  /// opaque run of letters and digits. Ordinary words, UUIDs and short ids are not.
  static bool looksLikeCredential(String value) {
    final v = value.trim();
    if (v.isEmpty || isTemplateOnly(v)) return false;
    if (_knownToken.hasMatch(v)) return true;
    return _opaque.hasMatch(v) &&
        !_uuid.hasMatch(v) &&
        !_slug.hasMatch(v) &&
        v.contains(RegExp(r'[A-Za-z]')) &&
        v.contains(RegExp(r'[0-9]'));
  }

  /// Every place in [text] where a known credential shape sits (JWT, `ghp_...`, ...).
  static Iterable<Match> knownTokens(String text) => _knownToken.allMatches(text);

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
