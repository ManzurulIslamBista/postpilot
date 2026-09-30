import '../entities/api_docs_model.dart';

/// Keeps credentials out of generated docs. Authentication never reaches the
/// model as anything but a type; on top of that, values are masked wherever
/// their name says they are secret (`Authorization`, `api_key`, `password`...).
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

  static bool isSensitiveName(String name) {
    final normalised = name.toLowerCase().replaceAll(_nonAlphanumeric, '');
    if (_nameFragments.any(normalised.contains)) return true;
    return name.split(_wordBoundary).any((word) => _nameWords.contains(word.toLowerCase()));
  }

  static String maskValue(String name, String value) {
    if (value.isEmpty || !isSensitiveName(name) || _onlyVariables.hasMatch(value)) return value;
    final scheme = _authScheme.firstMatch(value);
    return scheme == null ? mask : '${scheme[0]}$mask';
  }

  /// Masks a `user:password@` part and the value of sensitive query parameters.
  static String maskUrl(String url) {
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
              text: maskJson(body.text),
              variablesText: maskJson(body.variablesText),
              fields: _fields(body.fields),
            ),
      authSummary: request.authSummary,
      examples: [
        for (final example in request.examples)
          ApiDocsExample(name: example.name, statusCode: example.statusCode, body: maskJson(example.body)),
      ],
    );
  }

  static List<ApiDocsField> _fields(List<ApiDocsField> fields) =>
      [for (final field in fields) ApiDocsField(field.key, maskValue(field.key, field.value))];

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
