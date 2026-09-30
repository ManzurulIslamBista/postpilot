import '../../../../../core/enums/auth_type.dart';
import '../../../../../core/enums/http_method.dart';
import '../../entities/key_value_item.dart';
import '../../entities/request_auth.dart';

final class ParsedCurlRequest {
  final HttpMethod method;
  final String url;
  final List<KeyValueItem> headers;
  final String? body;
  final RequestAuth auth;

  const ParsedCurlRequest({required this.method, required this.url, required this.headers, this.body, required this.auth});
}

/// Parses a `curl ...` command line into a request. Covers the flags people
/// actually paste from browser dev tools / API docs: -X, -H, -d/--data*,
/// -u (basic auth), -b (cookie header). Anything else (--compressed, -k,
/// -L, -G, --form) is accepted and ignored rather than rejected, since a
/// user pasting a real cURL command shouldn't get an import failure over a
/// flag we don't model yet.
abstract final class CurlParser {
  static ParsedCurlRequest? parse(String command) {
    final tokens = _tokenize(command.trim());
    if (tokens.isEmpty) return null;

    var i = tokens.first.toLowerCase() == 'curl' ? 1 : 0;
    String? method;
    String? url;
    final headers = <KeyValueItem>[];
    String? body;
    String? basicUserPass;

    while (i < tokens.length) {
      final token = tokens[i];
      switch (token) {
        case '-X':
        case '--request':
          method = tokens[++i];
        case '-H':
        case '--header':
          final header = tokens[++i];
          final sep = header.indexOf(':');
          if (sep != -1) {
            headers.add(KeyValueItem(key: header.substring(0, sep).trim(), value: header.substring(sep + 1).trim()));
          }
        case '-d':
        case '--data':
        case '--data-raw':
        case '--data-binary':
        case '--data-urlencode':
          body = tokens[++i];
          method ??= 'POST';
        case '-u':
        case '--user':
          basicUserPass = tokens[++i];
        case '-b':
        case '--cookie':
          headers.add(KeyValueItem(key: 'Cookie', value: tokens[++i]));
        case '-A':
        case '--user-agent':
          headers.add(KeyValueItem(key: 'User-Agent', value: tokens[++i]));
        case '--compressed':
        case '-k':
        case '--insecure':
        case '-L':
        case '--location':
        case '-s':
        case '--silent':
        case '-G':
        case '-i':
        case '--include':
          break; // accepted, no request-shape effect we model
        default:
          if (!token.startsWith('-') && url == null) url = token;
      }
      i++;
    }

    if (url == null) return null;

    final auth = basicUserPass == null
        ? const RequestAuth(type: AuthType.inherit)
        : _basicAuthFrom(basicUserPass);

    return ParsedCurlRequest(
      method: HttpMethod.fromString(method ?? 'GET'),
      url: url,
      headers: headers,
      body: body,
      auth: auth,
    );
  }

  static RequestAuth _basicAuthFrom(String userPass) {
    final sep = userPass.indexOf(':');
    return RequestAuth(
      type: AuthType.basic,
      basicUsername: sep == -1 ? userPass : userPass.substring(0, sep),
      basicPassword: sep == -1 ? '' : userPass.substring(sep + 1),
    );
  }

  /// Splits on whitespace, honoring single/double quotes and `\`-line
  /// continuations (common when a cURL command is pasted multi-line).
  static List<String> _tokenize(String input) {
    final normalized = input.replaceAll(RegExp(r'\\\r?\n'), ' ');
    final tokens = <String>[];
    final buffer = StringBuffer();
    String? quote;

    void flush() {
      if (buffer.isNotEmpty) {
        tokens.add(buffer.toString());
        buffer.clear();
      }
    }

    for (var i = 0; i < normalized.length; i++) {
      final char = normalized[i];
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else if (char == r'\' && quote == '"' && i + 1 < normalized.length) {
          buffer.write(normalized[++i]);
        } else {
          buffer.write(char);
        }
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (char == ' ' || char == '\t' || char == '\n') {
        flush();
      } else {
        buffer.write(char);
      }
    }
    flush();
    return tokens;
  }
}
