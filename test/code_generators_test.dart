import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/code_generator_registry.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/curl_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/dart_http_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/javascript_fetch_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/python_requests_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/resolved_request_spec.dart';
import 'code_generator_fixtures.dart';

const _cafe = 'caf\u{e9} \u{1F600}';

void main() {
  final spec = ResolvedRequestSpec(
    method: 'POST',
    url: 'https://api.example.com/users',
    headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer abc123'},
    bodyBytes: utf8.encode('{"name":"John"}'),
  );

  test('CurlGenerator includes method, url, headers and body', () {
    final out = const CurlGenerator().generate(spec);
    expect(out, contains('--request POST'));
    expect(out, contains("'https://api.example.com/users'"));
    expect(out, contains("--header 'Content-Type: application/json'"));
    expect(out, contains("--header 'Authorization: Bearer abc123'"));
    expect(out, contains('--data-raw'));
    expect(out, contains('{"name":"John"}'));
  });

  test('JavaScriptFetchGenerator produces a fetch call with method, headers and body', () {
    final out = const JavaScriptFetchGenerator().generate(spec);
    expect(out, contains('fetch("https://api.example.com/users"'));
    expect(out, contains('method: "POST"'));
    expect(out, contains('"Content-Type": "application/json"'));
    expect(out, contains('body:'));
  });

  test('PythonRequestsGenerator produces a requests.request call', () {
    final out = const PythonRequestsGenerator().generate(spec);
    expect(out, contains('import requests'));
    expect(out, contains("requests.request('POST', 'https://api.example.com/users'"));
    expect(out, contains('headers=headers'));
    expect(out, contains('data=payload'));
  });

  test('DartHttpGenerator maps POST to http.post with headers and body', () {
    final out = const DartHttpGenerator().generate(spec);
    expect(out, contains("import 'package:http/http.dart' as http;"));
    expect(out, contains('http.post(uri, headers: headers, body:'));
  });

  test('generators omit body clauses when there is no body', () {
    final noBodySpec = ResolvedRequestSpec(method: 'GET', url: 'https://api.example.com/ping', headers: const {}, bodyBytes: null);
    expect(const CurlGenerator().generate(noBodySpec), isNot(contains('--data-raw')));
    expect(const JavaScriptFetchGenerator().generate(noBodySpec), isNot(contains('body:')));
    expect(const PythonRequestsGenerator().generate(noBodySpec), isNot(contains('data=payload')));
    expect(const DartHttpGenerator().generate(noBodySpec), isNot(contains('body:')));
  });

  group('CodeGeneratorRegistry', () {
    final all = CodeGeneratorRegistry.all;

    test('ids and labels are unique', () {
      expect({for (final g in all) g.id}.length, all.length);
      expect({for (final g in all) g.label}.length, all.length);
    });

    test('keeps cURL first (the dialog default) followed by the menu in a fixed order', () {
      expect([for (final g in all) g.id], [
        'curl',
        'httpie',
        'wget',
        'javascript_fetch',
        'nodejs_axios',
        'python_requests',
        'go_net_http',
        'java_okhttp',
        'kotlin_okhttp',
        'csharp_httpclient',
        'php_curl',
        'ruby_net_http',
        'swift_urlsession',
        'rust_reqwest',
        'dart_http',
        'powershell_invoke_restmethod',
        'r_httr',
      ]);
    });

    test('every generator emits the method, url and every header for a plain request', () {
      for (final g in all) {
        final out = g.generate(basicSpec);
        expect(out.toLowerCase(), contains('post'), reason: g.id);
        expect(out, contains('https://api.example.com/users'), reason: g.id);
        expect(out, contains('Content-Type'), reason: g.id);
        expect(out, contains('application/json'), reason: g.id);
        expect(out, contains('Authorization'), reason: g.id);
        expect(out, contains('Bearer abc123'), reason: g.id);
        expect(out, contains('John'), reason: g.id);
      }
    });

    test('every generator drops the body and header clauses for a bare GET', () {
      for (final g in all) {
        final out = g.generate(getSpec);
        expect(out, contains('https://api.example.com/ping'), reason: g.id);
        expect(out, isNot(contains('Content-Type')), reason: g.id);
        expect(out, isNot(contains('John')), reason: g.id);
        expect(out.trimRight(), out, reason: '${g.id} must not end in whitespace or a dangling continuation');
        expect(out, isNot(endsWith(r'\')), reason: g.id);
      }
    });

    test('no generator leaves a raw CR or control character in its output', () {
      for (final g in all) {
        for (final s in [nastySpec, multipartSpec]) {
          expect(g.generate(s), isNot(matches(RegExp(r'[\x00-\x08\x0B-\x1F\x7F]'))), reason: g.id);
        }
      }
    });

    test('generation is deterministic', () {
      for (final g in all) {
        expect(g.generate(nastySpec), g.generate(nastySpec), reason: g.id);
      }
    });
  });

  group('cURL escaping', () {
    const generator = CurlGenerator();

    test('escapes single quotes in the url, headers and body', () {
      final out = generator.generate(nastySpec);
      expect(out, contains(r"""'https://api.example.com/it'\''s/a$b?q="x"'"""));
      expect(out, contains(r"""--header 'X-Note: say "hi" it'\''s $HOME'"""));
    });

    test('by default keeps CR, LF and tab raw inside plain single quotes, the only form the in-app importer reads back', () {
      final out = generator.generate(nastySpec);
      expect(
        out,
        contains("--data-raw 'say \"hi\" it'\\''s a\\b \$HOME \${x} #{y} {z} %s `t` \\(x)\nline2\r\n\t$_cafe'"),
      );
      expect(out, isNot(contains(r"$'")));
    });

    test('with ansiC writes a body holding CR/LF/tab as an ANSI-C string so pasting it cannot submit the command early', () {
      final out = const CurlGenerator(ansiC: true).generate(nastySpec);
      expect(
        out,
        contains(
          r"""--data-raw $'say "hi" it\'s a\\b $HOME ${x} #{y} {z} %s `t` \\(x)\nline2\r\n\t""" '$_cafe' "'",
        ),
      );
    });

    test('the menu entry is the ansiC one, and a multipart body keeps its CRLFs as escapes', () {
      final menuEntry = CodeGeneratorRegistry.all.first;
      expect(menuEntry.id, 'curl');
      expect(
        menuEntry.generate(multipartSpec),
        endsWith(r"""--data-raw $'--B\r\nContent-Disposition: form-data; name="a"\r\n\r\nx y\r\n--B--\r\n'"""),
      );
    });

    test('keeps a plain multi-line body readable in single quotes', () {
      final spec = ResolvedRequestSpec(
        method: 'POST',
        url: 'https://x.test',
        headers: const {},
        bodyBytes: utf8.encode('{\n  "a": 1\n}'),
      );
      expect(generator.generate(spec), endsWith("--data-raw '{\n  \"a\": 1\n}'"));
    });

    test('sends an empty header value as `Name;` because `Name:` would remove it', () {
      final spec = ResolvedRequestSpec(method: 'GET', url: 'https://x.test', headers: const {'X-Empty': ''}, bodyBytes: null);
      expect(generator.generate(spec), contains("--header 'X-Empty;'"));
    });

    test('quotes an unusual method instead of splicing it into the command', () {
      final spec = ResolvedRequestSpec(method: 'PU RGE', url: 'https://x.test', headers: const {}, bodyBytes: null);
      expect(generator.generate(spec), contains("--request 'PU RGE'"));
    });
  });

  group('JavaScript fetch escaping', () {
    test('JSON-encodes the body, url and headers', () {
      final out = const JavaScriptFetchGenerator().generate(nastySpec);
      expect(
        out,
        contains(r'''body: "say \"hi\" it's a\\b $HOME ${x} #{y} {z} %s `t` \\(x)\nline2\r\n\t''' '$_cafe",'),
      );
      expect(out, contains(r'''fetch("https://api.example.com/it's/a$b?q=\"x\""'''));
      expect(out, contains(r'''"X-Note": "say \"hi\" it's $HOME"'''));
    });

    test('escapes the line separators old engines reject inside a string', () {
      final spec = ResolvedRequestSpec(
        method: 'POST',
        url: 'https://x.test',
        headers: const {},
        bodyBytes: utf8.encode('a\u{2028}b\u{2029}c'),
      );
      expect(const JavaScriptFetchGenerator().generate(spec), contains('"a\\u2028b\\u2029c"'));
    });
  });

  group('Python escaping', () {
    const generator = PythonRequestsGenerator();

    test('escapes quotes, backslashes and CR/LF/tab, and encodes a non-ASCII body as UTF-8', () {
      final out = generator.generate(nastySpec);
      expect(
        out,
        contains(
          r"""payload = 'say "hi" it\'s a\\b $HOME ${x} #{y} {z} %s `t` \\(x)\nline2\r\n\t""" + _cafe + r"""'.encode('utf-8')""",
        ),
      );
      expect(out, contains(r"""'https://api.example.com/it\'s/a$b?q="x"'"""));
      expect(out, contains(r"""'X-Note': 'say "hi" it\'s $HOME'"""));
    });

    test('sends an ASCII body as a plain str', () {
      final out = generator.generate(basicSpec);
      expect(out, contains("payload = '{\"name\":\"John\"}'\n"));
      expect(out, isNot(contains('.encode')));
    });

    test('never leaves a raw CR inside a literal, which Python would read as the end of the line', () {
      final out = generator.generate(multipartSpec);
      expect(out, contains(r"""payload = '--B\r\nContent-Disposition: form-data; name="a"\r\n\r\nx y\r\n--B--\r\n'"""));
    });
  });

  group('Dart escaping', () {
    const generator = DartHttpGenerator();

    test(r'escapes `$` so nothing is interpolated, plus quotes, backslashes and CR/LF/tab', () {
      final out = generator.generate(nastySpec);
      expect(
        out,
        contains(r"""body: 'say "hi" it\'s a\\b \$HOME \${x} #{y} {z} %s `t` \\(x)\nline2\r\n\t""" '$_cafe' "'"),
      );
      expect(out, contains(r"""Uri.parse('https://api.example.com/it\'s/a\$b?q="x"')"""));
      expect(out, contains(r"""'X-Note': 'say "hi" it\'s \$HOME'"""));
    });

    test('uses the shortcut methods that accept what the request holds', () {
      String gen(String method, {String? body, Map<String, String> headers = const {}}) => generator.generate(
            ResolvedRequestSpec(
              method: method,
              url: 'https://x.test',
              headers: headers,
              bodyBytes: body == null ? null : utf8.encode(body),
            ),
          );
      expect(gen('GET'), contains('http.get(uri)'));
      expect(gen('HEAD', headers: const {'A': 'b'}), contains('http.head(uri, headers: headers)'));
      expect(gen('PUT', body: 'x'), contains("http.put(uri, body: 'x')"));
      expect(gen('PATCH', body: 'x'), contains("http.patch(uri, body: 'x')"));
      expect(gen('DELETE', body: 'x'), contains("http.delete(uri, body: 'x')"));
    });

    test('falls back to http.Request for verbs and bodies the shortcuts cannot carry', () {
      final options = generator.generate(
        ResolvedRequestSpec(method: 'OPTIONS', url: 'https://x.test', headers: const {'A': 'b'}, bodyBytes: null),
      );
      expect(options, contains("http.Request('OPTIONS', uri)"));
      expect(options, contains('request.headers.addAll(headers);'));
      expect(options, contains('http.Response.fromStream(await request.send())'));
      expect(options, isNot(contains('request.body')));

      final getWithBody = generator.generate(
        ResolvedRequestSpec(method: 'GET', url: 'https://x.test', headers: const {}, bodyBytes: utf8.encode('q')),
      );
      expect(getWithBody, contains("http.Request('GET', uri)"));
      expect(getWithBody, contains("request.body = 'q';"));
    });
  });
}
