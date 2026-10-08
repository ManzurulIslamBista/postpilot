// Pure Dart (no Flutter, no database).

/// One challenge of a `WWW-Authenticate` (or `Proxy-Authenticate`) header: the scheme the server wants and its
/// parameters.
final class AuthChallenge {
  /// `Bearer`, `Basic`, `Digest`, `Negotiate`... as the server wrote it.
  final String scheme;

  /// The parameters, names lower-cased, quoted strings unquoted.
  final Map<String, String> params;

  /// The bare credential of schemes that carry one instead of parameters (`Negotiate YIIB...`).
  final String? token68;

  const AuthChallenge(this.scheme, this.params, [this.token68]);

  bool isScheme(String name) => scheme.toLowerCase() == name.toLowerCase();

  String? get realm => params['realm'];

  /// The RFC 6750 error code: `invalid_token`, `insufficient_scope`, `invalid_request`.
  String? get error => params['error'];
  String? get errorDescription => params['error_description'];

  /// The scopes the resource asks for, as a list.
  List<String> get scopes => [
        for (final s in (params['scope'] ?? '').split(RegExp(r'[\s,]+')))
          if (s.isNotEmpty) s,
      ];
}

/// Reads a `WWW-Authenticate` header, which may hold several challenges (`Basic realm="a", Bearer error="invalid_token"`).
abstract final class WwwAuthenticate {
  static List<AuthChallenge> parse(String? header) {
    if (header == null || header.trim().isEmpty) return const [];
    final out = <_Builder>[];
    _Builder? current;
    var sawComma = true;
    final n = header.length;
    var i = 0;

    bool isBlank(String c) => c == ' ' || c == '\t' || c == '\r' || c == '\n';
    void skipBlanks() {
      while (i < n && isBlank(header[i])) {
        i++;
      }
    }

    while (i < n) {
      skipBlanks();
      while (i < n && header[i] == ',') {
        sawComma = true;
        i++;
        skipBlanks();
      }
      if (i >= n) break;
      final start = i;
      while (i < n && header[i] != '=' && header[i] != ',' && !isBlank(header[i])) {
        i++;
      }
      final word = header.substring(start, i);
      if (word.isEmpty) {
        i++; // a stray '=' or similar: skip it rather than loop
        continue;
      }
      skipBlanks();
      if (i < n && header[i] == '=') {
        final equalsAt = i;
        while (i < n && header[i] == '=') {
          i++;
        }
        // `YIIB==`: the equals signs are the padding of a token68, not the start of a parameter.
        final padding = i - equalsAt;
        if (i >= n || header[i] == ',' || (padding > 1 && isBlank(header[i]))) {
          final owner = current;
          if (owner != null) owner.token68 = '${owner.token68 ?? ''}$word${'=' * padding}';
          sawComma = false;
          continue;
        }
        i = equalsAt + 1;
        skipBlanks();
        final value = StringBuffer();
        if (i < n && header[i] == '"') {
          i++;
          while (i < n && header[i] != '"') {
            if (header[i] == r'\' && i + 1 < n) i++;
            value.write(header[i]);
            i++;
          }
          i++; // the closing quote
        } else {
          while (i < n && header[i] != ',' && !isBlank(header[i])) {
            value.write(header[i]);
            i++;
          }
        }
        current?.params[word.toLowerCase()] = value.toString();
        sawComma = false;
      } else if (current != null && !sawComma && current.params.isEmpty && current.token68 == null) {
        // `Negotiate YIIBhg`: a word right after a scheme, with no comma between, is the scheme's own token.
        current.token68 = word;
      } else {
        current = _Builder(word);
        out.add(current);
        sawComma = false;
      }
    }
    return [for (final b in out) AuthChallenge(b.scheme, Map.unmodifiable(b.params), b.token68)];
  }
}

final class _Builder {
  final String scheme;
  final Map<String, String> params = {};
  String? token68;
  _Builder(this.scheme);
}
