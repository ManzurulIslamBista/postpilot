import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/curl_parser.dart';

void main() {
  test('parses a simple GET with a header', () {
    final result = CurlParser.parse("curl -H 'Accept: application/json' https://api.example.com/users");
    expect(result, isNotNull);
    expect(result!.method, HttpMethod.get);
    expect(result.url, 'https://api.example.com/users');
    expect(result.headers, hasLength(1));
    expect(result.headers.first.key, 'Accept');
    expect(result.headers.first.value, 'application/json');
  });

  test('a -d flag defaults the method to POST and captures the body', () {
    final result = CurlParser.parse("curl https://api.example.com/users -d '{\"name\":\"John\"}'");
    expect(result!.method, HttpMethod.post);
    expect(result.body, '{"name":"John"}');
  });

  test('-X overrides the method even when -d is present', () {
    final result = CurlParser.parse("curl -X PUT https://api.example.com/users/1 -d '{}'");
    expect(result!.method, HttpMethod.put);
  });

  test('-u produces basic auth split on the first colon', () {
    final result = CurlParser.parse('curl -u alice:s3cr3t:with:colons https://api.example.com');
    expect(result!.auth.type, AuthType.basic);
    expect(result.auth.basicUsername, 'alice');
    expect(result.auth.basicPassword, 's3cr3t:with:colons');
  });

  test('multiple headers are all captured', () {
    final result = CurlParser.parse(
      "curl -H 'Content-Type: application/json' -H 'Authorization: Bearer xyz' https://api.example.com",
    );
    expect(result!.headers, hasLength(2));
    expect(result.headers.map((h) => h.key), containsAll(['Content-Type', 'Authorization']));
  });

  test('unknown flags like --compressed and -k do not break parsing', () {
    final result = CurlParser.parse('curl --compressed -k -L https://api.example.com/ping');
    expect(result, isNotNull);
    expect(result!.url, 'https://api.example.com/ping');
  });

  test('multi-line commands with backslash continuations parse correctly', () {
    const command = "curl https://api.example.com \\\n  -H 'Accept: application/json' \\\n  -X DELETE";
    final result = CurlParser.parse(command);
    expect(result!.method, HttpMethod.delete);
    expect(result.headers.first.key, 'Accept');
  });

  test('returns null when there is no URL', () {
    expect(CurlParser.parse('curl -X GET'), isNull);
  });
}
