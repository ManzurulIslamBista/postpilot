import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/code_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/csharp_httpclient_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/go_net_http_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/httpie_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/java_okhttp_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/kotlin_okhttp_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/node_axios_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/php_curl_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/powershell_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/r_httr_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/ruby_net_http_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/rust_reqwest_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/string_literals.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/swift_urlsession_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/wget_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/resolved_request_spec.dart';
import 'code_generator_fixtures.dart';

const _cafe = 'caf\u{e9} \u{1F600}';

// nastyBody up to its non-ASCII tail, as it is written inside "..." literals.
const _dq = r'''say \"hi\" it's a\\b $HOME ${x} #{y} {z} %s `t` \\(x)\nline2\r\n\t''';
const _dqDollar = r'''say \"hi\" it's a\\b \$HOME \${x} #{y} {z} %s `t` \\(x)\nline2\r\n\t''';
const _dqHash = r'''say \"hi\" it's a\\b $HOME ${x} \#{y} {z} %s `t` \\(x)\nline2\r\n\t''';

final class _Target {
  final CodeGenerator generator;
  final String basic;
  final String bare;
  final String nastyBody;
  final List<String> nastyWire;

  const _Target(this.generator, {required this.basic, required this.bare, required this.nastyBody, required this.nastyWire});
}

final _goBasic = [
  'package main',
  '',
  'import (',
  '\t"fmt"',
  '\t"io"',
  '\t"net/http"',
  '\t"strings"',
  ')',
  '',
  'func main() {',
  '\tpayload := strings.NewReader(`{"name":"John"}`)',
  '',
  '\treq, err := http.NewRequest("POST", "https://api.example.com/users", payload)',
  '\tif err != nil {',
  '\t\tfmt.Println(err)',
  '\t\treturn',
  '\t}',
  '\treq.Header.Set("Content-Type", "application/json")',
  '\treq.Header.Set("Authorization", "Bearer abc123")',
  '',
  '\tres, err := http.DefaultClient.Do(req)',
  '\tif err != nil {',
  '\t\tfmt.Println(err)',
  '\t\treturn',
  '\t}',
  '\tdefer res.Body.Close()',
  '',
  '\tbody, err := io.ReadAll(res.Body)',
  '\tif err != nil {',
  '\t\tfmt.Println(err)',
  '\t\treturn',
  '\t}',
  '\tfmt.Println(string(body))',
  '}',
].join('\n');

final _goBare = [
  'package main',
  '',
  'import (',
  '\t"fmt"',
  '\t"io"',
  '\t"net/http"',
  ')',
  '',
  'func main() {',
  '\treq, err := http.NewRequest("GET", "https://api.example.com/ping", nil)',
  '\tif err != nil {',
  '\t\tfmt.Println(err)',
  '\t\treturn',
  '\t}',
  '',
  '\tres, err := http.DefaultClient.Do(req)',
  '\tif err != nil {',
  '\t\tfmt.Println(err)',
  '\t\treturn',
  '\t}',
  '\tdefer res.Body.Close()',
  '',
  '\tbody, err := io.ReadAll(res.Body)',
  '\tif err != nil {',
  '\t\tfmt.Println(err)',
  '\t\treturn',
  '\t}',
  '\tfmt.Println(string(body))',
  '}',
].join('\n');

final _targets = <_Target>[
  _Target(
    const HttpieGenerator(),
    basic: r"""
http POST 'https://api.example.com/users' \
  'Content-Type:application/json' \
  'Authorization:Bearer abc123' \
  --raw='{"name":"John"}'""",
    bare: "http GET 'https://api.example.com/ping'",
    nastyBody: r"""--raw=$'say "hi" it\'s a\\b $HOME ${x} #{y} {z} %s `t` \\(x)\nline2\r\n\t""" '$_cafe' "'",
    nastyWire: [
      r"""'https://api.example.com/it'\''s/a$b?q="x"'""",
      r"""'X-Note:say "hi" it'\''s $HOME'""",
    ],
  ),
  _Target(
    const WgetGenerator(),
    basic: r"""
wget --quiet \
  --method POST \
  --header 'Content-Type: application/json' \
  --header 'Authorization: Bearer abc123' \
  --body-data '{"name":"John"}' \
  --output-document - \
  'https://api.example.com/users'""",
    bare: r"""
wget --quiet \
  --method GET \
  --output-document - \
  'https://api.example.com/ping'""",
    nastyBody: r"""--body-data $'say "hi" it\'s a\\b $HOME ${x} #{y} {z} %s `t` \\(x)\nline2\r\n\t""" '$_cafe' "'",
    nastyWire: [
      r"""'https://api.example.com/it'\''s/a$b?q="x"'""",
      r"""--header 'X-Note: say "hi" it'\''s $HOME'""",
    ],
  ),
  _Target(
    const NodeAxiosGenerator(),
    basic: r'''
const axios = require("axios");

const config = {
  method: "post",
  url: "https://api.example.com/users",
  headers: {
    "Content-Type": "application/json",
    "Authorization": "Bearer abc123"
  },
  data: "{\"name\":\"John\"}",
};

axios.request(config)
  .then((response) => console.log(response.data))
  .catch((error) => console.error(error));''',
    bare: r'''
const axios = require("axios");

const config = {
  method: "get",
  url: "https://api.example.com/ping",
};

axios.request(config)
  .then((response) => console.log(response.data))
  .catch((error) => console.error(error));''',
    nastyBody: '"$_dq$_cafe"',
    nastyWire: [jsString(nastyUrl), jsString(nastyHeaderValue)],
  ),
  _Target(
    const GoNetHttpGenerator(),
    basic: _goBasic,
    bare: _goBare,
    nastyBody: '"$_dq$_cafe"',
    nastyWire: [goString(nastyUrl), goString(nastyHeaderValue)],
  ),
  _Target(
    const JavaOkHttpGenerator(),
    basic: r'''
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

import java.io.IOException;

public class Main {
    public static void main(String[] args) throws IOException {
        OkHttpClient client = new OkHttpClient();

        RequestBody body = RequestBody.create("{\"name\":\"John\"}", null);
        Request request = new Request.Builder()
                .url("https://api.example.com/users")
                .method("POST", body)
                .addHeader("Content-Type", "application/json")
                .addHeader("Authorization", "Bearer abc123")
                .build();

        try (Response response = client.newCall(request).execute()) {
            System.out.println(response.body().string());
        }
    }
}''',
    bare: r'''
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;

import java.io.IOException;

public class Main {
    public static void main(String[] args) throws IOException {
        OkHttpClient client = new OkHttpClient();

        Request request = new Request.Builder()
                .url("https://api.example.com/ping")
                .method("GET", null)
                .build();

        try (Response response = client.newCall(request).execute()) {
            System.out.println(response.body().string());
        }
    }
}''',
    nastyBody: '"$_dq' 'caf${_bs}u00e9 ${_bs}ud83d${_bs}ude00"',
    nastyWire: [javaString(nastyUrl), javaString(nastyHeaderValue)],
  ),
  _Target(
    const KotlinOkHttpGenerator(),
    basic: r'''
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

fun main() {
    val client = OkHttpClient()

    val body = "{\"name\":\"John\"}".toRequestBody()
    val request = Request.Builder()
        .url("https://api.example.com/users")
        .method("POST", body)
        .addHeader("Content-Type", "application/json")
        .addHeader("Authorization", "Bearer abc123")
        .build()

    client.newCall(request).execute().use { response ->
        println(response.body?.string())
    }
}''',
    bare: r'''
import okhttp3.OkHttpClient
import okhttp3.Request

fun main() {
    val client = OkHttpClient()

    val request = Request.Builder()
        .url("https://api.example.com/ping")
        .method("GET", null)
        .build()

    client.newCall(request).execute().use { response ->
        println(response.body?.string())
    }
}''',
    nastyBody: '"$_dqDollar$_cafe"',
    nastyWire: [kotlinString(nastyUrl), kotlinString(nastyHeaderValue)],
  ),
  _Target(
    const CSharpHttpClientGenerator(),
    basic: r'''
using System;
using System.Net.Http;
using System.Text;

using var client = new HttpClient();
using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.example.com/users");
request.Headers.TryAddWithoutValidation("Authorization", "Bearer abc123");
request.Content = new ByteArrayContent(Encoding.UTF8.GetBytes("{\"name\":\"John\"}"));
request.Content.Headers.TryAddWithoutValidation("Content-Type", "application/json");

using var response = await client.SendAsync(request);
Console.WriteLine(await response.Content.ReadAsStringAsync());''',
    bare: r'''
using System;
using System.Net.Http;

using var client = new HttpClient();
using var request = new HttpRequestMessage(HttpMethod.Get, "https://api.example.com/ping");

using var response = await client.SendAsync(request);
Console.WriteLine(await response.Content.ReadAsStringAsync());''',
    nastyBody: '"$_dq$_cafe"',
    nastyWire: [csharpString(nastyUrl), csharpString(nastyHeaderValue)],
  ),
  _Target(
    const PhpCurlGenerator(),
    basic: r'''
<?php

$curl = curl_init();

curl_setopt_array($curl, [
    CURLOPT_URL => 'https://api.example.com/users',
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_CUSTOMREQUEST => 'POST',
    CURLOPT_HTTPHEADER => [
        'Content-Type: application/json',
        'Authorization: Bearer abc123',
    ],
    CURLOPT_POSTFIELDS => '{"name":"John"}',
]);

$response = curl_exec($curl);

if ($response === false) {
    echo 'cURL error: ' . curl_error($curl) . PHP_EOL;
} else {
    echo $response;
}''',
    bare: r'''
<?php

$curl = curl_init();

curl_setopt_array($curl, [
    CURLOPT_URL => 'https://api.example.com/ping',
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_CUSTOMREQUEST => 'GET',
]);

$response = curl_exec($curl);

if ($response === false) {
    echo 'cURL error: ' . curl_error($curl) . PHP_EOL;
} else {
    echo $response;
}''',
    nastyBody: '"$_dqDollar$_cafe"',
    nastyWire: [
      r"""'https://api.example.com/it\'s/a$b?q="x"'""",
      r"""'X-Note: say "hi" it\'s $HOME'""",
    ],
  ),
  _Target(
    const RubyNetHttpGenerator(),
    basic: r'''
require 'net/http'
require 'uri'

uri = URI.parse('https://api.example.com/users')

request = Net::HTTP::Post.new(uri)
request['Content-Type'] = 'application/json'
request['Authorization'] = 'Bearer abc123'
request.body = '{"name":"John"}'

response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
  http.request(request)
end

puts response.body''',
    bare: r'''
require 'net/http'
require 'uri'

uri = URI.parse('https://api.example.com/ping')

request = Net::HTTP::Get.new(uri)

response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
  http.request(request)
end

puts response.body''',
    nastyBody: '"$_dqHash$_cafe"',
    nastyWire: [
      r"""'https://api.example.com/it\'s/a$b?q="x"'""",
      r"""'say "hi" it\'s $HOME'""",
    ],
  ),
  _Target(
    const SwiftUrlSessionGenerator(),
    basic: r'''
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

var request = URLRequest(url: URL(string: "https://api.example.com/users")!)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.setValue("Bearer abc123", forHTTPHeaderField: "Authorization")
request.httpBody = "{\"name\":\"John\"}".data(using: .utf8)

let semaphore = DispatchSemaphore(value: 0)
let task = URLSession.shared.dataTask(with: request) { data, response, error in
    if let error = error {
        print(error)
    } else if let data = data {
        print(String(decoding: data, as: UTF8.self))
    }
    semaphore.signal()
}
task.resume()
semaphore.wait()''',
    bare: r'''
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

var request = URLRequest(url: URL(string: "https://api.example.com/ping")!)
request.httpMethod = "GET"

let semaphore = DispatchSemaphore(value: 0)
let task = URLSession.shared.dataTask(with: request) { data, response, error in
    if let error = error {
        print(error)
    } else if let data = data {
        print(String(decoding: data, as: UTF8.self))
    }
    semaphore.signal()
}
task.resume()
semaphore.wait()''',
    nastyBody: '"$_dq$_cafe"',
    nastyWire: [swiftString(nastyUrl), swiftString(nastyHeaderValue)],
  ),
  _Target(
    const RustReqwestGenerator(),
    basic: r'''
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = reqwest::Client::new();

    let response = client
        .request(reqwest::Method::POST, "https://api.example.com/users")
        .header("Content-Type", "application/json")
        .header("Authorization", "Bearer abc123")
        .body("{\"name\":\"John\"}")
        .send()
        .await?;

    println!("{}", response.text().await?);
    Ok(())
}''',
    bare: r'''
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = reqwest::Client::new();

    let response = client
        .request(reqwest::Method::GET, "https://api.example.com/ping")
        .send()
        .await?;

    println!("{}", response.text().await?);
    Ok(())
}''',
    nastyBody: '"$_dq$_cafe"',
    nastyWire: [rustString(nastyUrl), rustString(nastyHeaderValue)],
  ),
  _Target(
    const PowerShellGenerator(),
    basic: r'''
$headers = @{
    'Content-Type' = 'application/json'
    'Authorization' = 'Bearer abc123'
}

$body = '{"name":"John"}'

$response = Invoke-RestMethod -Uri 'https://api.example.com/users' -Method 'POST' -Headers $headers -Body $body
$response | ConvertTo-Json -Depth 10''',
    bare: r'''
$response = Invoke-RestMethod -Uri 'https://api.example.com/ping' -Method 'GET'
$response | ConvertTo-Json -Depth 10''',
    nastyBody: r'''$body = "say ""hi"" it's a\b `$HOME `${x} #{y} {z} %s ``t`` \(x)`nline2`r`n`t''' '$_cafe"',
    nastyWire: [
      r"""'https://api.example.com/it''s/a$b?q="x"'""",
      r"""'say "hi" it''s $HOME'""",
    ],
  ),
  _Target(
    const RHttrGenerator(),
    basic: r'''
library(httr)

response <- VERB(
  "POST",
  url = "https://api.example.com/users",
  add_headers(
    "Content-Type" = "application/json",
    "Authorization" = "Bearer abc123"
  ),
  body = "{\"name\":\"John\"}"
)

cat(content(response, "text", encoding = "UTF-8"), "\n")''',
    bare: r'''
library(httr)

response <- VERB(
  "GET",
  url = "https://api.example.com/ping"
)

cat(content(response, "text", encoding = "UTF-8"), "\n")''',
    nastyBody: '"$_dq' 'caf${_bs}u00e9 ${_bs}U0001f600"',
    nastyWire: [rString(nastyUrl), rString(nastyHeaderValue)],
  ),
];

final _bs = String.fromCharCode(0x5C);

ResolvedRequestSpec _spec(
  String method, {
  Map<String, String> headers = const {},
  String? body,
  String url = 'https://x.test/p',
}) =>
    ResolvedRequestSpec(method: method, url: url, headers: headers, bodyBytes: body == null ? null : utf8.encode(body));

void main() {
  for (final target in _targets) {
    group(target.generator.label, () {
      test('renders method, url, headers and body', () {
        expect(target.generator.generate(basicSpec), target.basic.trimLeft());
      });

      test('renders a bare request without body or header clauses', () {
        expect(target.generator.generate(getSpec), target.bare.trimLeft());
      });

      test('escapes a nasty body, url and header value for the language', () {
        final out = target.generator.generate(nastySpec);
        expect(out, contains(target.nastyBody));
        for (final fragment in target.nastyWire) {
          expect(out, contains(fragment));
        }
      });
    });
  }

  group('HTTPie', () {
    const generator = HttpieGenerator();

    test('passes a multipart body as --raw=... so its leading -- is not read as an option', () {
      expect(
        generator.generate(multipartSpec),
        endsWith(r"""--raw=$'--B\r\nContent-Disposition: form-data; name="a"\r\n\r\nx y\r\n--B--\r\n'"""),
      );
    });

    test('sends an empty header with `Name;` and escapes item separators', () {
      final out = generator.generate(
        _spec('GET', headers: const {'X-Empty': '', 'X:Odd': 'v', 'X-At': '@file', 'X-Eq': '=x', 'X-Path': r'C:\dir'}),
      );
      expect(out, contains("'X-Empty;'"));
      expect(out, contains(r"'X\:Odd:v'"));
      expect(out, contains(r"'X-At:\@file'"));
      expect(out, contains(r"'X-Eq:\=x'"));
      expect(out, contains(r"'X-Path:C:\dir'"));
    });
  });

  group('wget', () {
    test('uses --method for other verbs and keeps the url last', () {
      final out = const WgetGenerator().generate(_spec('PATCH', body: '{"a":1}'));
      expect(out, contains('--method PATCH'));
      expect(out, contains("--body-data '{\"a\":1}'"));
      expect(out, endsWith("--output-document - \\\n  'https://x.test/p'"));
    });
  });

  group('Node.js (axios)', () {
    const generator = NodeAxiosGenerator();

    test('does not rewrite a valid JSON body', () {
      final out = generator.generate(basicSpec);
      expect(out, isNot(contains('transformRequest')));
    });

    test('bypasses axios JSON re-encoding when the JSON Content-Type carries a body that is not valid JSON', () {
      final out = generator.generate(_spec('POST', headers: const {'Content-Type': 'application/json'}, body: '{oops'));
      expect(out, contains('transformRequest: [(data) => data],'));
    });

    test('leaves other content types alone', () {
      final out = generator.generate(_spec('POST', headers: const {'Content-Type': 'text/plain'}, body: '{oops'));
      expect(out, isNot(contains('transformRequest')));
    });

    test('matches the content type case-insensitively by header name', () {
      final out = generator.generate(_spec('POST', headers: const {'content-type': 'application/json'}, body: 'not json'));
      expect(out, contains('transformRequest'));
    });
  });

  group('Go (net/http)', () {
    const generator = GoNetHttpGenerator();

    test('sends Host through req.Host, which net/http honours instead of the header map', () {
      final out = generator.generate(_spec('GET', headers: const {'Host': 'internal.test', 'X-A': 'b'}));
      expect(out, contains('req.Host = "internal.test"'));
      expect(out, isNot(contains('Header.Set("Host"')));
      expect(out, contains('req.Header.Set("X-A", "b")'));
    });

    test('uses a raw string for quoted or multi-line text and an interpreted one when it cannot', () {
      expect(generator.generate(_spec('POST', body: '{\n  "a": 1\n}')), contains('strings.NewReader(`{\n  "a": 1\n}`)'));
      expect(generator.generate(_spec('POST', body: 'a `b` "c"')), contains(r'strings.NewReader("a `b` \"c\"")'));
      expect(generator.generate(_spec('POST', body: 'plain')), contains('strings.NewReader("plain")'));
    });

    test('imports strings only when there is a body', () {
      expect(generator.generate(_spec('POST', body: 'x')), contains('"strings"'));
      expect(generator.generate(_spec('POST')), isNot(contains('strings')));
    });
  });

  group('Java (OkHttp)', () {
    const generator = JavaOkHttpGenerator();

    test('gives POST, PUT and PATCH an empty body because OkHttp rejects null for them', () {
      for (final method in ['POST', 'PUT', 'PATCH']) {
        final out = generator.generate(_spec(method));
        expect(out, contains('RequestBody body = RequestBody.create(new byte[0], null);'), reason: method);
        expect(out, contains('.method("$method", body)'), reason: method);
        expect(out, contains('import okhttp3.RequestBody;'), reason: method);
      }
    });

    test('passes null for verbs that take no body', () {
      for (final method in ['GET', 'DELETE', 'HEAD', 'OPTIONS', 'PURGE']) {
        final out = generator.generate(_spec(method));
        expect(out, contains('.method("$method", null)'), reason: method);
        expect(out, isNot(contains('RequestBody')), reason: method);
      }
    });

    test('leaves Content-Type to the explicit header by giving the body no media type', () {
      final out = generator.generate(basicSpec);
      expect(out, contains('RequestBody.create("{\\"name\\":\\"John\\"}", null)'));
      expect(out, isNot(contains('MediaType')));
    });

    test('writes only ASCII so it compiles whatever charset javac assumes', () {
      final out = generator.generate(nastySpec);
      expect(out.runes.every((r) => r < 0x80), isTrue);
    });
  });

  group('Kotlin (OkHttp)', () {
    const generator = KotlinOkHttpGenerator();

    test('gives POST an empty body and passes null for verbs without one', () {
      expect(generator.generate(_spec('POST')), contains('val body = "".toRequestBody()'));
      expect(generator.generate(_spec('POST')), contains('.method("POST", body)'));
      expect(generator.generate(_spec('DELETE')), contains('.method("DELETE", null)'));
      expect(generator.generate(_spec('DELETE')), isNot(contains('toRequestBody')));
    });

    test(r'escapes `$` in the url and header values as well as the body', () {
      final out = generator.generate(_spec('GET', url: r'https://x.test/$a', headers: const {'X': r'${b}'}));
      expect(out, contains(r'.url("https://x.test/\$a")'));
      expect(out, contains(r'.addHeader("X", "\${b}")'));
    });
  });

  group('C# (HttpClient)', () {
    const generator = CSharpHttpClientGenerator();

    test('puts content headers on the content and the rest on the request', () {
      final out = generator.generate(
        _spec('POST', headers: const {'Content-Type': 'text/plain', 'X-Trace': '1', 'content-language': 'en'}, body: 'hi'),
      );
      expect(out, contains('request.Headers.TryAddWithoutValidation("X-Trace", "1");'));
      expect(out, contains('request.Content.Headers.TryAddWithoutValidation("Content-Type", "text/plain");'));
      expect(out, contains('request.Content.Headers.TryAddWithoutValidation("content-language", "en");'));
      expect(out, isNot(contains('request.Headers.TryAddWithoutValidation("Content-Type"')));
      expect(out.indexOf('request.Content = '), lessThan(out.indexOf('request.Content.Headers')));
    });

    test('adds an empty content when a content header has no body to ride on', () {
      final out = generator.generate(_spec('POST', headers: const {'Content-Type': 'application/json'}));
      expect(out, contains('request.Content = new ByteArrayContent(Array.Empty<byte>());'));
      expect(out, contains('request.Content.Headers.TryAddWithoutValidation("Content-Type", "application/json");'));
      expect(out, isNot(contains('using System.Text;')));
    });

    test('maps verbs to HttpMethod members and builds an HttpMethod for unknown ones', () {
      expect(generator.generate(_spec('PATCH')), contains('HttpMethod.Patch'));
      expect(generator.generate(_spec('DELETE')), contains('HttpMethod.Delete'));
      expect(generator.generate(_spec('PURGE')), contains('new HttpMethod("PURGE")'));
    });

    test('escapes the line breaks C# would otherwise see inside a literal', () {
      final out = generator.generate(_spec('POST', body: 'a\u{85}b\u{2028}c\u{2029}d'));
      expect(out, contains('"a${_bs}u0085b${_bs}u2028c${_bs}u2029d"'));
    });
  });

  group('PHP (cURL)', () {
    const generator = PhpCurlGenerator();

    test('uses CURLOPT_NOBODY for HEAD instead of a custom verb that would wait for a body', () {
      final out = generator.generate(_spec('HEAD'));
      expect(out, contains('CURLOPT_NOBODY => true,'));
      expect(out, isNot(contains('CURLOPT_CUSTOMREQUEST')));
    });

    test('sends an empty header as `Name;` and never calls the deprecated curl_close', () {
      final out = generator.generate(_spec('GET', headers: const {'X-Empty': ''}));
      expect(out, contains("'X-Empty;',"));
      expect(out, isNot(contains('curl_close')));
    });

    test('keeps plain multi-line text readable in single quotes and switches to double quotes for CR', () {
      expect(generator.generate(_spec('POST', body: '{\n  "a": 1\n}')), contains("CURLOPT_POSTFIELDS => '{\n  \"a\": 1\n}',"));
      expect(generator.generate(_spec('POST', body: 'a\r\nb')), contains(r'CURLOPT_POSTFIELDS => "a\r\nb",'));
    });
  });

  group('Ruby (Net::HTTP)', () {
    const generator = RubyNetHttpGenerator();

    test('maps verbs to Net::HTTP classes and builds a generic request for unknown ones', () {
      expect(generator.generate(_spec('DELETE')), contains('Net::HTTP::Delete.new(uri)'));
      expect(generator.generate(_spec('PATCH', body: 'x')), contains('Net::HTTP::Patch.new(uri)'));
      expect(generator.generate(_spec('PURGE', body: 'x')), contains("Net::HTTPGenericRequest.new('PURGE', true, true, uri)"));
      expect(generator.generate(_spec('PURGE')), contains("Net::HTTPGenericRequest.new('PURGE', false, true, uri)"));
    });

    test('escapes every # in double quotes because #{, #\$ and #@ all interpolate', () {
      final out = generator.generate(_spec('POST', body: 'a#b\r\n#\$x #@y'));
      expect(out, contains(r'request.body = "a\#b\r\n\#$x \#@y"'));
    });
  });

  group('Swift (URLSession)', () {
    test('escapes backslashes so a `\\(` in the body cannot interpolate', () {
      final out = const SwiftUrlSessionGenerator().generate(_spec('POST', body: r'\(secret)'));
      expect(out, contains(r'request.httpBody = "\\(secret)".data(using: .utf8)'));
    });
  });

  group('Rust (reqwest)', () {
    const generator = RustReqwestGenerator();

    test('maps verbs to reqwest::Method constants and parses unknown ones', () {
      expect(generator.generate(_spec('PUT')), contains('reqwest::Method::PUT'));
      expect(generator.generate(_spec('OPTIONS')), contains('reqwest::Method::OPTIONS'));
      expect(generator.generate(_spec('PURGE')), contains('reqwest::Method::from_bytes(b"PURGE")?'));
    });

    test('writes braces in the body as plain literal text, never through a format macro', () {
      final out = generator.generate(_spec('POST', body: '{}{{x}}'));
      expect(out, contains('.body("{}{{x}}")'));
      expect(RegExp(r'format!|println!\("[^{]*\{[^}]').hasMatch(out), isFalse);
    });
  });

  group('PowerShell (Invoke-RestMethod)', () {
    const generator = PowerShellGenerator();

    test('uses -CustomMethod for verbs Invoke-RestMethod does not know', () {
      expect(generator.generate(_spec('PATCH')), contains("-Method 'PATCH'"));
      expect(generator.generate(_spec('PURGE')), contains("-CustomMethod 'PURGE'"));
    });

    test('sends a non-ASCII body as UTF-8 bytes because Windows PowerShell 5.1 would send Latin-1', () {
      final out = generator.generate(_spec('POST', body: 'caf\u{e9}'));
      expect(out, contains(r'-Body ([System.Text.Encoding]::UTF8.GetBytes($body))'));
      expect(generator.generate(_spec('POST', body: 'cafe')), contains(r'-Body $body'));
    });

    test('doubles the typographic quotes PowerShell also accepts as string delimiters', () {
      final single = generator.generate(_spec('POST', body: 'it\u{2019}s \u{2018}q\u{201A} \u{201B}'));
      expect(single, contains("\$body = 'it\u{2019}\u{2019}s \u{2018}\u{2018}q\u{201A}\u{201A} \u{201B}\u{201B}'"));

      final double = generator.generate(_spec('POST', body: 'a\r\n\u{201C}b\u{201D} \u{201E}'));
      expect(double, contains('\$body = "a`r`n\u{201C}\u{201C}b\u{201D}\u{201D} \u{201E}\u{201E}"'));
    });

    test('keeps single quotes for readable text, including line feeds', () {
      final out = generator.generate(_spec('POST', body: 'a\nb \$c `d`'));
      expect(out, contains("\$body = 'a\nb \$c `d`'"));
    });
  });

  group('R (httr)', () {
    test('escapes non-ASCII as \\u / \\U so a Windows ANSI locale cannot garble it', () {
      final out = const RHttrGenerator().generate(_spec('POST', body: 'caf\u{e9} \u{1F600}'));
      expect(out, contains('body = "caf${_bs}u00e9 ${_bs}U0001f600"'));
      expect(out.runes.every((r) => r < 0x80), isTrue);
    });
  });
}
