import '../entities/api_docs_model.dart';

/// Keeps credentials out of generated docs. Authentication never reaches the
/// model as anything but a type; on top of that, values are masked wherever
/// their name says they are secret (`Authorization`, `api_key`, `password`...),
/// and wherever the value itself gives it away (`user:password@host`, a JWT,
/// a Stripe, GitHub, AWS or Slack key, a Slack webhook), whatever the name.
/// A value made only of `{{variables}}` is a reference, not a secret, and stays.
abstract final class SecretMasker {
  static const mask = '••••••';

  /// Found anywhere in the name once separators are removed: `accessToken`,
  /// `x-api-key` and `client_secret` all contain one.
  static const _nameFragments = [
    'password',
    'passwd',
    'secret',
    'token',
    'apikey',
    'accesskey',
    'privatekey',
    'authorization',
    'cookie',
    'credential',
    'signature',
    'sessionid',
    'jwt',
    'bearer',
  ];

  /// Short words that only count as a whole word of the name, so `X-Auth`
  /// and `apiKey` match but `author`, `keyword` and `monkey` do not.
  static const _nameWords = {'auth', 'key', 'pwd', 'pass', 'sig', 'session'};

  static final _wordBoundary = RegExp(r'[^A-Za-z0-9]+|(?<=[a-z0-9])(?=[A-Z])');
  static final _nonAlphanumeric = RegExp(r'[^a-z0-9]');
  static final _authScheme = RegExp(r'^(?:Bearer|Basic|Digest|Token|ApiKey)\s+', caseSensitive: false);
  static final _onlyVariables = RegExp(
    r'^\s*(?:(?:Bearer|Basic|Digest|Token|ApiKey)\s+)?(?:\{\{[^{}]+\}\}\s*)+$',
    caseSensitive: false,
  );
  static final _urlPassword = RegExp(r'(://[^/?#@\s:]*:)([^/?#@\s]+)@');
  static final _jsonStringField = RegExp(r'"((?:[^"\\]|\\.)*)"(\s*:\s*)"((?:[^"\\]|\\.)*)"');

  // Each of the patterns below starts only where a name or a word starts, so a
  // long body is scanned once, not once per character.

  /// `name: "literal"` and `name="literal"` with a bare name: GraphQL
  /// arguments, XML attributes, JavaScript objects.
  static final _literalAssignment = RegExp(
    r'''(?<![\w.$"'-])([A-Za-z_][\w.-]*)(\s*[:=]\s*)("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')''',
  );

  /// `<Name>text</Name>`, prefix and attributes allowed (SOAP `wsse:Password`).
  static final _xmlElement = RegExp(r'(<((?:[\w.-]+:)?[\w.-]+)(?:\s[^<>]*)?>)([^<>]+)(</\2\s*>)');

  /// `name=value` of a urlencoded body sent as raw text, an `.env` file or a
  /// query string; the value runs to the next separator.
  static final _bareAssignment = RegExp(r'''(?<![\w.%\[\]-])([A-Za-z_][\w.%\[\]-]*)=([^&\s"'<>;]+)''');

  /// `name: value` on a line of its own, unquoted: a YAML or header-style body.
  static final _lineAssignment = RegExp(
    r'''^([ \t]*(?:-[ \t]+)?)([A-Za-z_][\w.-]*)([ \t]*:[ \t]*)([^\s"'{\[$][^\r\n]*)$''',
    multiLine: true,
  );

  /// Credentials that give themselves away: a JWT, a Stripe, GitHub, GitLab,
  /// AWS, Slack or Google key, and the secret path of a Slack or Discord webhook.
  static final _knownToken = RegExp(
    r'\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]*'
    r'|\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{10,}'
    r'|\bgh[pousr]_[A-Za-z0-9]{20,}'
    r'|\bgithub_pat_[A-Za-z0-9_]{20,}'
    r'|\bglpat-[A-Za-z0-9_-]{16,}'
    r'|\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'
    r'|\bxox[abposr]-[A-Za-z0-9-]{10,}'
    r'|\bAIza[A-Za-z0-9_-]{30,}'
    r'|(hooks\.slack\.com/services/|discord(?:app)?\.com/api/webhooks/)[A-Za-z0-9/_-]+',
  );

  /// A run of text without spaces that holds a `scheme://` or a query.
  static final _urlLike = RegExp(r'''(?<![^\s"'<>])[^\s"'<>]*(?:://|\?)[^\s"'<>]*''');

  static bool isSensitiveName(String name) {
    final normalised = name.toLowerCase().replaceAll(_nonAlphanumeric, '');
    if (_nameFragments.any(normalised.contains)) return true;
    return name.split(_wordBoundary).any((word) => _nameWords.contains(word.toLowerCase()));
  }

  static String maskValue(String name, String value) {
    if (value.isEmpty || _onlyVariables.hasMatch(value)) return value;
    if (!isSensitiveName(name)) return _maskByValue(value);
    final scheme = _authScheme.firstMatch(value);
    return scheme == null ? mask : '${scheme[0]}$mask';
  }

  /// Masks a `user:password@` part, the value of sensitive query parameters
  /// and a credential the text itself gives away.
  static String maskUrl(String url) => _maskKnownTokens(_maskUrlParts(url));

  static String _maskUrlParts(String url) {
    final withoutPassword = url.replaceAllMapped(
      _urlPassword,
      (m) => _onlyVariables.hasMatch(m[2]!) ? m[0]! : '${m[1]}$mask@',
    );
    final query = withoutPassword.indexOf('?');
    if (query == -1) return withoutPassword;
    final hash = withoutPassword.indexOf('#', query);
    final end = hash == -1 ? withoutPassword.length : hash;
    final pairs = withoutPassword.substring(query + 1, end).split('&').map(_maskQueryPair).join('&');
    return '${withoutPassword.substring(0, query + 1)}$pairs${withoutPassword.substring(end)}';
  }

  /// Masks the string value of sensitive keys in JSON-looking text.
  static String maskJson(String text) => text.replaceAllMapped(_jsonStringField, (m) {
        final value = m[3]!;
        if (value.isEmpty || !isSensitiveName(m[1]!) || _onlyVariables.hasMatch(value)) return m[0]!;
        return '"${m[1]}"${m[2]}"$mask"';
      });

  /// Masks credentials in a request or response body of any format: JSON
  /// (see [maskJson]), GraphQL arguments, XML/SOAP elements and attributes,
  /// and `name=value` or `name: value` text such as an urlencoded body sent as
  /// raw text, each by the name it sits under, plus known token shapes anywhere
  /// in the text. A number under a sensitive JSON key stays: counts such as
  /// `max_tokens` are far more common than numeric secrets.
  static String maskBody(String text) {
    if (text.isEmpty) return text;
    var masked = maskJson(text);
    masked = masked.replaceAllMapped(_literalAssignment, (m) {
      final literal = m[3]!;
      final value = literal.substring(1, literal.length - 1);
      if (value.isEmpty || !isSensitiveName(m[1]!) || _onlyVariables.hasMatch(value)) return m[0]!;
      final quote = literal[0];
      return '${m[1]}${m[2]}$quote$mask$quote';
    });
    masked = masked.replaceAllMapped(_xmlElement, (m) {
      final inner = m[3]!.trim();
      final safe = maskValue(m[2]!, inner);
      return inner.isEmpty || safe == inner ? m[0]! : '${m[1]}$safe${m[4]}';
    });
    masked = masked.replaceAllMapped(_bareAssignment, (m) => '${m[1]}=${maskValue(_decode(m[1]!), m[2]!)}');
    masked = masked.replaceAllMapped(_lineAssignment, (m) {
      final value = m[4]!;
      final trimmed = value.trimRight();
      return '${m[1]}${m[2]}${m[3]}${maskValue(m[2]!, trimmed)}${value.substring(trimmed.length)}';
    });
    return _maskKnownTokens(masked);
  }

  /// Masks credentials in a message that may quote a URL, such as the error
  /// shown after a failed send.
  static String maskMessage(String text) =>
      _maskKnownTokens(text.replaceAllMapped(_urlLike, (m) => _maskUrlParts(m[0]!)));

  static ApiDocsModel redact(ApiDocsModel model) => ApiDocsModel(
        name: model.name,
        description: model.description,
        tags: model.tags,
        authSummary: model.authSummary,
        variables: _fields(model.variables),
        folders: [for (final folder in model.folders) _folder(folder)],
        requests: [for (final request in model.requests) _request(request)],
      );

  static ApiDocsFolder _folder(ApiDocsFolder folder) => ApiDocsFolder(
        name: folder.name,
        description: folder.description,
        tags: folder.tags,
        folders: [for (final child in folder.folders) _folder(child)],
        requests: [for (final request in folder.requests) _request(request)],
      );

  static ApiDocsRequest _request(ApiDocsRequest request) {
    final body = request.body;
    return ApiDocsRequest(
      name: request.name,
      method: request.method,
      url: maskUrl(request.url),
      description: request.description,
      tags: request.tags,
      queryParams: _fields(request.queryParams),
      headers: _fields(request.headers),
      body: body == null
          ? null
          : ApiDocsBody(
              typeLabel: body.typeLabel,
              language: body.language,
              text: maskBody(body.text),
              variablesText: maskBody(body.variablesText),
              fields: _fields(body.fields),
            ),
      authSummary: request.authSummary,
      examples: [
        for (final example in request.examples)
          ApiDocsExample(name: example.name, statusCode: example.statusCode, body: maskBody(example.body)),
      ],
    );
  }

  static List<ApiDocsField> _fields(List<ApiDocsField> fields) =>
      [for (final field in fields) ApiDocsField(field.key, maskValue(field.key, field.value), origin: field.origin)];

  /// A value under an ordinary name: a URL keeps its host and path but loses
  /// its password and secret parameters; anything else loses a known token.
  static String _maskByValue(String value) => value.contains('://') ? maskUrl(value) : _maskKnownTokens(value);

  static String _maskKnownTokens(String text) => text.replaceAllMapped(_knownToken, (m) => '${m[1] ?? ''}$mask');

  static String _maskQueryPair(String pair) {
    final equals = pair.indexOf('=');
    if (equals == -1) return pair;
    return '${pair.substring(0, equals + 1)}${maskValue(_decode(pair.substring(0, equals)), pair.substring(equals + 1))}';
  }

  static String _decode(String name) {
    try {
      return Uri.decodeQueryComponent(name);
    } catch (_) {
      return name;
    }
  }
}
