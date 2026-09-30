import 'dart:convert';
import 'package:postpilot/features/request_builder/domain/services/resolved_request_spec.dart';

ResolvedRequestSpec _spec(String method, String url, Map<String, String> headers, String? body) => ResolvedRequestSpec(
      method: method,
      url: url,
      headers: headers,
      bodyBytes: body == null ? null : utf8.encode(body),
    );

final basicSpec = _spec(
  'POST',
  'https://api.example.com/users',
  const {'Content-Type': 'application/json', 'Authorization': 'Bearer abc123'},
  '{"name":"John"}',
);

final getSpec = _spec('GET', 'https://api.example.com/ping', const {}, null);

/// Every hazard at once: both quote kinds, a backslash, `$`, `${`, `#{`, braces,
/// `%s`, a backtick, `\(`, LF, CRLF, a tab, and non-ASCII (BMP and astral).
const nastyBody = 'say "hi" it\'s a\\b \$HOME \${x} #{y} {z} %s `t` \\(x)\nline2\r\n\tcaf\u{e9} \u{1F600}';

const nastyUrl = 'https://api.example.com/it\'s/a\$b?q="x"';

const nastyHeaderValue = 'say "hi" it\'s \$HOME';

final nastySpec = _spec(
  'POST',
  nastyUrl,
  const {'Content-Type': 'text/plain', 'X-Note': nastyHeaderValue},
  nastyBody,
);

/// What RequestSpecBuilder produces for a form-data body: CRLF line breaks
/// and a first line that starts with `--`.
final multipartSpec = _spec(
  'POST',
  'https://api.example.com/upload',
  const {'Content-Type': 'multipart/form-data; boundary=B'},
  '--B\r\nContent-Disposition: form-data; name="a"\r\n\r\nx y\r\n--B--\r\n',
);
