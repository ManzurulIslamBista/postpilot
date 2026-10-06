import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/curl_parser.dart';

ParsedCurlRequest _parse(String command) {
  final parsed = CurlParser.parse(command);
  expect(parsed, isNotNull, reason: command);
  return parsed!;
}

List<(String, String)> _headers(ParsedCurlRequest request) => [for (final h in request.headers) (h.key, h.value)];

void main() {
  group('flags that take a value never leave it behind as the URL', () {
    // Each command is "curl <flag and value> https://x.test"; the URL must be the only positional.
    const flags = {
      '-o /dev/null': 'output',
      '--output /tmp/out.json': 'output',
      '-m 30': 'max time',
      '--max-time 10': 'max time',
      '--connect-timeout 5': 'connect timeout',
      "-w '%{http_code}'": 'write-out',
      '--write-out %{time_total}': 'write-out',
      '--retry 3': 'retry',
      '--retry-delay 2': 'retry delay',
      '--proxy http://proxy.test:8080': 'proxy',
      '-x socks5://127.0.0.1:1080': 'proxy short',
      '--cacert /etc/ssl/ca.pem': 'cacert',
      '--max-redirs 5': 'max redirs',
      '-c /tmp/jar.txt': 'cookie jar',
      '--resolve x.test:443:127.0.0.1': 'resolve',
    };

    for (final entry in flags.entries) {
      test('${entry.value}: ${entry.key}', () {
        final request = _parse('curl ${entry.key} https://x.test');
        expect(request.url, 'https://x.test');
        expect(request.method, HttpMethod.get);
        expect(request.body, isNull);
      });
    }

    test('the value may come before the URL or after it, and several can be mixed', () {
      expect(_parse('curl -s -o /dev/null https://x.test').url, 'https://x.test');
      expect(_parse('curl https://x.test -o /dev/null').url, 'https://x.test');
      expect(_parse('curl -m 30 --retry 3 -o out.json -w "%{http_code}" https://x.test/a').url, 'https://x.test/a');
    });

    test('an option this parser has never heard of cannot hide the URL, because a URL with a scheme wins', () {
      expect(_parse('curl --some-future-flag somevalue https://x.test').url, 'https://x.test');
    });

    test('without a scheme the first bare word is the URL', () {
      expect(_parse('curl -s localhost:3000/health').url, 'localhost:3000/health');
    });

    test('--url names the URL', () {
      expect(_parse('curl --url https://x.test/a -s').url, 'https://x.test/a');
    });
  });

  group('headers from value flags', () {
    test('-A, -e and -r become User-Agent, Referer and Range headers', () {
      final request = _parse("curl -A 'My Agent/1.0' -e 'https://ref.test/page;auto' -r 0-99 https://x.test");
      expect(request.url, 'https://x.test');
      expect(_headers(request), [('User-Agent', 'My Agent/1.0'), ('Referer', 'https://ref.test/page'), ('Range', 'bytes=0-99')]);
    });

    test('-b with cookies is a Cookie header; -b with a file name is reported', () {
      expect(_headers(_parse("curl -b 'a=1; b=2' https://x.test")), [('Cookie', 'a=1; b=2')]);
      final fromFile = _parse('curl -b cookies.txt https://x.test');
      expect(fromFile.headers, isEmpty);
      expect(fromFile.notes, ['The cookies are read from a file ("cookies.txt"), which cannot be imported.']);
    });
  });

  group('authentication', () {
    test('-u is basic, --digest -u is digest, --oauth2-bearer is a bearer token', () {
      final basic = _parse('curl -u ann:pw https://x.test');
      expect((basic.auth.type, basic.auth.basicUsername, basic.auth.basicPassword), (AuthType.basic, 'ann', 'pw'));
      final digest = _parse('curl --digest -u ann:pw https://x.test');
      expect((digest.auth.type, digest.auth.basicUsername, digest.auth.basicPassword), (AuthType.digest, 'ann', 'pw'));
      final bearer = _parse('curl --oauth2-bearer abc.def https://x.test');
      expect((bearer.auth.type, bearer.auth.bearerToken), (AuthType.bearer, 'abc.def'));
    });

    test('-u with only a user name has an empty password', () {
      final request = _parse('curl -u ann https://x.test');
      expect((request.auth.basicUsername, request.auth.basicPassword), ('ann', ''));
    });
  });

  group('data', () {
    test('repeated -d pieces are joined with & like curl does, whatever the data flag', () {
      final request = _parse("curl -d a=1 --data b=2 --data-raw 'c=3' --data-binary d=4 https://x.test/f");
      expect(request.body, 'a=1&b=2&c=3&d=4');
      expect(request.method, HttpMethod.post);
    });

    test('a body without a Content-Type is sent as a form, like curl: the header is added', () {
      final request = _parse("curl -d 'a=1&b=2' https://x.test/f");
      expect(_headers(request), [('Content-Type', 'application/x-www-form-urlencoded')]);
      final body = request.requestBody;
      expect((body.type, body.rawContentType, body.rawText), (BodyType.raw, RawContentType.text, 'a=1&b=2'));
    });

    test('a JSON-looking body without a Content-Type stays JSON and gets no extra header', () {
      final request = _parse('curl -d \'{"a":1}\' https://x.test/j');
      expect(request.headers, isEmpty);
      expect(request.requestBody.rawContentType, RawContentType.json);
    });

    test('a declared Content-Type is kept and decides the raw type', () {
      final xml = _parse("curl -H 'Content-Type: application/xml' -d '<a/>' https://x.test");
      expect(_headers(xml), [('Content-Type', 'application/xml')]);
      expect(xml.requestBody.rawContentType, RawContentType.xml);

      final json = _parse('curl -H "content-type: application/vnd.api+json" -d \'{"a":1}\' https://x.test');
      expect(json.headers, hasLength(1));
      expect(json.requestBody.rawContentType, RawContentType.json);

      final plain = _parse("curl -H 'Content-Type: text/plain' -d 'a=1' https://x.test");
      expect(plain.headers, hasLength(1));
      expect(plain.requestBody.rawContentType, RawContentType.text);
    });

    test('-d with an empty string is an empty body, and does not swallow the URL', () {
      final request = _parse("curl -d '' https://x.test");
      expect(request.url, 'https://x.test');
      expect(request.body, '');
      expect(request.method, HttpMethod.post);
    });

    test('--data-urlencode encodes the content: name=content, =content and bare content', () {
      final request = _parse("curl --data-urlencode 'q=hello world&x' --data-urlencode '=a b' --data-urlencode 'plain text' https://x.test");
      // Hand-derived: space is %20, & is %26; the name is kept as it is.
      expect(request.body, 'q=hello%20world%26x&a%20b&plain%20text');
    });

    test('--data-urlencode encodes non-ASCII as UTF-8 and leaves unreserved characters alone', () {
      final request = _parse("curl --data-urlencode 'n=é-._~' https://x.test");
      // é is C3 A9 in UTF-8.
      expect(request.body, 'n=%C3%A9-._~');
    });

    test('a body read from a file is reported, still POSTs, and sends no invented body', () {
      final request = _parse('curl -d @payload.json https://x.test/up');
      expect(request.method, HttpMethod.post);
      expect(request.body, isNull);
      expect(request.notes, ['The body is read from a file or standard input ("@payload.json"), which cannot be imported.']);

      final fromStdin = _parse('curl --data-binary @- https://x.test/up');
      expect(fromStdin.notes, hasLength(1));
    });

    test('--data-raw keeps a leading @ as text', () {
      final request = _parse('curl --data-raw @literal https://x.test');
      expect(request.body, '@literal');
      expect(request.notes, isEmpty);
    });

    test('-G turns the data into the query string and keeps the method GET', () {
      final request = _parse("curl -G -d a=1 -d 'b=2 3' https://x.test/s");
      expect(request.url, 'https://x.test/s?a=1&b=2 3');
      expect(request.method, HttpMethod.get);
      expect(request.body, isNull);
      expect(_parse('curl -G -d a=1 "https://x.test/s?z=0"').url, 'https://x.test/s?z=0&a=1');
    });

    test('an explicit -X wins over the method the data implies', () {
      expect(_parse('curl -X GET -d a=1 https://x.test').method, HttpMethod.get);
      expect(_parse('curl -d a=1 -X PUT https://x.test').method, HttpMethod.put);
    });

    test('--json sets the body, both JSON headers and POST', () {
      final request = _parse('curl --json \'{"a":1}\' https://x.test');
      expect(request.body, '{"a":1}');
      expect(request.method, HttpMethod.post);
      expect(_headers(request), [('Content-Type', 'application/json'), ('Accept', 'application/json')]);
    });
  });

  group('multipart form (-F)', () {
    test('text fields, a file field with its type, quotes and ;type= stripped from text', () {
      final request = _parse(
        "curl -F 'name=Ann' -F 'avatar=@/tmp/a.png;type=image/png' -F 'note=\"hi there\";type=text/plain' https://x.test/up",
      );
      expect(request.method, HttpMethod.post);
      expect(request.body, isNull);
      expect(request.formFields.map((f) => (f.key, f.value, f.enabled, f.isFile, f.contentType)), [
        ('name', 'Ann', true, false, ''),
        ('avatar', '/tmp/a.png', true, true, 'image/png'),
        ('note', 'hi there', true, false, ''),
      ]);
      expect(request.notes, [
        '1 file path points to this machine, so it will not work for a teammate. '
            'Replace the start of the path with a variable, for example {{uploadDir}}/avatar.png.',
      ]);
      final body = request.requestBody;
      expect(body.type, BodyType.formData);
      expect(body.formFields, hasLength(3));
      expect(request.headers, isEmpty, reason: 'the multipart boundary header is the app\'s to set');
    });

    test('--form-string never reads a file', () {
      final request = _parse("curl --form-string 'a=@not-a-file' https://x.test");
      expect(request.formFields.single.value, '@not-a-file');
      expect(request.formFields.single.enabled, isTrue);
      expect(request.notes, isEmpty);
    });
  });

  group('method flags', () {
    test('-I is HEAD, -T is a PUT of that file as a binary body, -X still wins', () {
      expect(_parse('curl -I https://x.test').method, HttpMethod.head);
      expect(_parse('curl --head https://x.test').method, HttpMethod.head);
      final upload = _parse('curl -T report.csv https://x.test/up');
      expect(upload.method, HttpMethod.put);
      expect(upload.notes, isEmpty);
      expect(upload.requestBody.type, BodyType.binary);
      expect(upload.requestBody.binaryFile!.value, 'report.csv');
      expect(_parse('curl -I -X GET https://x.test').method, HttpMethod.get);
    });
  });

  group('incomplete commands', () {
    test('a trailing option with no value is a null result, not a RangeError', () {
      for (final command in [
        'curl https://x.test -H',
        'curl https://x.test -d',
        'curl https://x.test -X',
        'curl https://x.test -o',
        'curl https://x.test --header',
        'curl -sH',
      ]) {
        expect(() => CurlParser.parse(command), returnsNormally, reason: command);
        expect(CurlParser.parse(command), isNull, reason: command);
      }
    });
  });

  group('shell quoting', () {
    test(r"ANSI-C quotes $'...' decode \n, \t, \', \\, octal, \x, \u", () {
      final request = _parse(r"""curl https://x.test -d $'{"a":"l1\nl2","q":"it\'s","t":"\t","b":"\\","o":"\101","x":"\x42","u":"\u00e9"}'""");
      expect(request.body, '{"a":"l1\nl2","q":"it\'s","t":"\t","b":"\\","o":"A","x":"B","u":"é"}');
    });

    test(r'ANSI-C \x bytes that spell a UTF-8 character read as that character', () {
      final request = _parse(r"curl https://x.test --data-raw $'caf\xc3\xa9'");
      expect(request.body, 'café');
    });

    test(r'a header in $-quotes and an unknown escape left as typed', () {
      final request = _parse(r"curl https://x.test -H $'X-Tab: a\tb' -H $'X-Odd: \q'");
      expect(_headers(request), [('X-Tab', 'a\tb'), ('X-Odd', r'\q')]);
    });

    test('inside double quotes only \\ " \$ and backtick are escapes; other backslashes stay', () {
      final request = _parse(r'''curl https://x.test -d "{\"a\":\"b\\c\",\"n\":\"x\ny\",\"m\":\"cost \$5\"}"''');
      expect(request.body, r'{"a":"b\c","n":"x\ny","m":"cost $5"}');
    });

    test('a shell variable is kept as typed, not expanded', () {
      final request = _parse(r'curl https://x.test -H "Authorization: Bearer $TOKEN"');
      expect(_headers(request), [('Authorization', r'Bearer $TOKEN')]);
    });

    test('a backslash outside quotes escapes the next character (an escaped space stays in the URL)', () {
      expect(_parse(r'curl https://x.test/a\ b').url, 'https://x.test/a b');
    });

    test('the single-quote idiom \'\\\'\' keeps its apostrophe', () {
      final request = _parse(r"""curl https://x.test -d 'it'\''s'""");
      expect(request.body, "it's");
    });

    test('bundled short flags, attached values and flags in any order', () {
      final request = _parse("curl -sSLk -XPOST -H'X-A: 1' -d@- https://x.test");
      expect(request.method, HttpMethod.post);
      expect(_headers(request), [('X-A', '1')]);
      expect(request.notes, hasLength(1), reason: '-d@- reads standard input');
      expect(_parse('curl -sSLo /dev/null https://x.test').url, 'https://x.test');
    });

    test('a pipe, a semicolon and a comment end the command', () {
      expect(_parse('curl -s https://x.test/a | jq .items').url, 'https://x.test/a');
      expect(_parse('curl https://x.test/b; echo done').url, 'https://x.test/b');
      final commented = _parse('curl https://x.test/c # fetch the list');
      expect((commented.url, commented.method), ('https://x.test/c', HttpMethod.get));
    });

    test('a prompt word before curl, and curl.exe', () {
      expect(_parse('sudo curl https://x.test').url, 'https://x.test');
      expect(_parse('curl.exe https://x.test').url, 'https://x.test');
    });
  });
}
