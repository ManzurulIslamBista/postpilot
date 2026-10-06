import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/mock_server/data/mock_server_engine.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_log.dart';

void main() {
  group('what the log keeps of a request', () {
    test('headers: credentials are masked whatever their name, transport headers are dropped', () {
      final headers = MockLogMasking.headers({
        'Authorization': 'Bearer abcdefghijklmnopqrstuvwxyz',
        'Cookie': 'sid=abc123',
        'X-Api-Key': 'k-123456789012345678901234',
        'X-Trace': 'abc',
        'Accept': 'application/json',
        'Host': 'localhost:3001',
        'Content-Length': '12',
        'User-Agent': 'curl/8',
        'Accept-Encoding': 'gzip',
      });
      expect(headers['Authorization'], 'Bearer ••••••');
      expect(headers['Cookie'], '••••••');
      expect(headers['X-Api-Key'], '••••••');
      expect(headers['X-Trace'], 'abc');
      expect(headers['Accept'], 'application/json');
      for (final dropped in ['Host', 'Content-Length', 'User-Agent', 'Accept-Encoding']) {
        expect(headers.containsKey(dropped), isFalse, reason: dropped);
      }
    });

    test('the address: secret query values and a password in it are masked, the rest stays', () {
      expect(MockLogMasking.target('/x?api_key=abc123&page=2'), '/x?api_key=••••••&page=2');
      expect(MockLogMasking.target('/login?token=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig&user=ann'), '/login?token=••••••&user=ann');
      expect(MockLogMasking.target('/plain?a=1'), '/plain?a=1');
    });

    test('the body: secrets by name and by shape are masked, long bodies are cut', () {
      expect(MockLogMasking.body('{"name":"a","password":"p4ss","nested":{"client_secret":"s3"}}'),
          '{"name":"a","password":"••••••","nested":{"client_secret":"••••••"}}');
      expect(MockLogMasking.body('key sk_live_abcdefghijklmnopqrstuv here'), 'key •••••• here');
      final long = MockLogMasking.body('x' * 5000);
      expect(long.length, MockLogMasking.bodyLimit + 1);
      expect(long, endsWith('…'));
      expect(MockLogMasking.body(''), '');
    });

    test('the preview is one short line', () {
      expect(MockLogMasking.preview('  {\n  "a": 1,\n  "b":  2\n}  '), '{ "a": 1, "b": 2 }');
      final cut = MockLogMasking.preview('word ' * 40);
      expect(cut.length, 81);
      expect(cut, endsWith('…'));
    });
  });

  group('copy as cURL', () {
    test('method, address, headers and body, one option per line, quoted for a shell', () {
      final curl = MockCurl.build(
        method: 'POST',
        url: 'http://localhost:3001/a?b=1&c=two words',
        headers: {'content-type': 'application/json', 'x-empty': ''},
        body: '{"a":"it\'s"}',
      );
      expect(curl, '''
curl --request POST 'http://localhost:3001/a?b=1&c=two words' \\
  --header 'content-type: application/json' \\
  --header 'x-empty;' \\
  --data-raw '{"a":"it'\\''s"}\'''');
    });

    test('a request without headers or body is one line', () {
      expect(MockCurl.build(method: 'GET', url: 'http://localhost:3001/ping'), "curl --request GET 'http://localhost:3001/ping'");
    });

    test('a log entry builds it against the base URL it is given, without doubling the slash', () {
      final entry = MockLogEntry(
        at: DateTime(2026, 10, 6),
        method: 'DELETE',
        path: '/users/3',
        status: 204,
        route: 'DELETE /users/:id',
        duration: const Duration(milliseconds: 4),
        requestHeaders: const {'x-trace': 'abc'},
      );
      expect(entry.toCurl('http://10.0.2.2:3001/'), "curl --request DELETE 'http://10.0.2.2:3001/users/3' \\\n  --header 'x-trace: abc'");
    });
  });

  test('an entry that was never answered says so, and previews what was sent before what came back', () {
    final entry = MockLogEntry(
      at: DateTime(2026, 10, 6),
      method: 'POST',
      path: '/x',
      status: 0,
      route: null,
      duration: Duration.zero,
      requestBody: '{"a":1}',
      responseBody: '{"b":2}',
    );
    expect(entry.neverAnswered, isTrue);
    expect(entry.preview, '{"a":1}');
  });
}
