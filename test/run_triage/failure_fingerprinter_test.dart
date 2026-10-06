// What caused a failure, told from the status, the error text and the check lines a record keeps. The texts below are
// the ones the app and the command line really write (see NetworkFailure, UndefinedVariables, RequestOutcome and the
// assertion names), so a record from either is told apart the same way.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/run_triage/domain/services/failure_fingerprinter.dart';
import 'run_fixtures.dart';

FailureFingerprint _of({int? status, String? error, List<String> failures = const []}) =>
    FailureFingerprinter.of(entry('r', status: status, error: error, failures: failures, passed: false));

void main() {
  group('the answer itself', () {
    test('401 and 403 are the auth-looking ones, told apart', () {
      final a = _of(status: 401);
      expect((a.key, a.kind, a.status), ('http:401', FailureKind.auth, 401));
      expect(a.title, 'HTTP 401 Unauthorized');
      final b = _of(status: 403);
      expect((b.key, b.kind), ('http:403', FailureKind.auth));
    });

    test('other statuses keep their exact code, 4xx and 5xx apart', () {
      expect(_of(status: 404).key, 'http:404');
      expect(_of(status: 404).kind, FailureKind.http);
      expect(_of(status: 500).key, 'http:500');
      expect(_of(status: 503).title, 'HTTP 503 Service Unavailable');
      expect(_of(status: 418).title, 'HTTP 418');
      expect(_of(status: 302).key, 'http:302');
    });

    test('a failing check on a non-2xx answer is the answer\'s fault: the status wins', () {
      final f = _of(status: 500, failures: const ['data.id equals 42 (got Missing)', 'Status equals 200 (got 500)']);
      expect(f.key, 'http:500');
    });

    test('the same code gives the same key whatever the failure lines say', () {
      expect(_of(status: 502, failures: const ['HTTP 502 Bad Gateway']).key, _of(status: 502).key);
    });
  });

  group('network errors, by class and host', () {
    test('timeouts: the app\'s two wordings and the command line\'s', () {
      final slow = _of(error: 'The server at api.shop.test did not answer within 30 seconds. Raise the "Request timeout" in Settings (or in this request\'s Settings tab) if the server is just slow.');
      expect(slow.key, 'network:timeout:api.shop.test');
      expect(slow.kind, FailureKind.network);
      expect(slow.host, 'api.shop.test');
      final connect = _of(error: 'Could not connect to api.shop.test:8443 within 5 seconds — the server may be down or blocked by a firewall. Raise the "Request timeout" in Settings.');
      expect(connect.key, 'network:timeout:api.shop.test:8443');
      final noLimit = _of(error: 'The connection to api.shop.test timed out — the server may be down or blocked by a firewall.');
      expect(noLimit.key, 'network:timeout:api.shop.test');
      expect(_of(error: 'Timed out after 30s').key, 'network:timeout:');
    });

    test('host not found', () {
      final f = _of(error: 'Couldn\'t find the server "api.shop.test" — check the spelling of the host name, and your network, DNS or VPN.');
      expect((f.key, f.detail, f.host), ('network:dns:api.shop.test', 'dns', 'api.shop.test'));
      expect(_of(error: "Can't reach the server: Failed host lookup: 'api.shop.test'").key, 'network:dns:api.shop.test');
    });

    test('connection refused or unreachable', () {
      expect(_of(error: 'The server at localhost:3000 refused the connection — check that it is running and that the port is right.').key,
          'network:refused:localhost:3000');
      expect(_of(error: "Can't reach the server: Connection refused, address = 127.0.0.1, port = 8080").key, 'network:refused:127.0.0.1:8080');
      expect(_of(error: 'api.shop.test can\'t be reached from this network — check your connection, VPN or proxy.').key, 'network:refused:api.shop.test');
    });

    test('TLS problems, the connection dropping', () {
      expect(_of(error: 'The secure connection to api.shop.test failed: the server\'s certificate has expired. If you trust this server, turn off "Verify SSL certificates" in Settings.').key,
          'network:tls:api.shop.test');
      expect(_of(error: 'TLS error: Handshake error in client. Use --insecure to skip certificate checks.').key, 'network:tls:');
      expect(_of(error: 'The server at api.shop.test closed the connection without answering — it may have crashed.').key,
          'network:dropped:api.shop.test');
    });

    test('requests that failed the same way to one host share a key; another host is another cause', () {
      final a = _of(error: 'The server at a.shop.test did not answer within 30 seconds. x');
      final b = _of(error: 'The server at a.shop.test did not answer within 10 seconds. y');
      final c = _of(error: 'The server at b.shop.test did not answer within 30 seconds. x');
      expect(a.key, b.key);
      expect(a.key, isNot(c.key));
    });

    test('a word that merely contains tls or ssl is not a TLS problem', () {
      final f = _of(error: 'The classless widget settled: 5 outlets failed');
      expect(f.kind, FailureKind.other);
    });
  });

  group('configuration', () {
    test('an undefined variable, by name: the app\'s wording and the command line\'s', () {
      expect(_of(error: '{{baseUrl}} (used in the URL) is not defined. Select an environment, or add it to the collection variables or the globals.').key,
          'config:variable:baseUrl');
      expect(_of(error: 'The URL still contains {{orderId}}: pass --env or --var orderId=...').key, 'config:variable:orderId');
      final many = _of(error: 'These variables are not defined: {{b}} (used in the URL), {{a}} (used in the "X-Token" header). Select an environment, or add them to the collection variables or the globals.');
      expect(many.key, 'config:variable:a+b');
      expect(many.title, 'Undefined variables {{a}}, {{b}}');
      expect(many.kind, FailureKind.config);
    });

    test('the production lock', () {
      final f = _of(error: 'Refused by the production lock: POST Shop / Orders / Create. This request changes data; read-only requests still run.');
      expect((f.key, f.kind), ('blocked:production-lock', FailureKind.blocked));
    });

    test('a token that could not be renewed', () {
      final f = _of(error: 'The token request to https://auth.shop.test/token answered 400 (invalid_client). The request was not sent.');
      expect((f.key, f.kind), ('auth:renewal', FailureKind.auth));
    });

    test('a request that could not be built', () {
      expect(_of(error: 'Could not build the request: Invalid header').key, 'config:build');
    });
  });

  group('checks and variable saves', () {
    FailureFingerprint check(String line) => _of(status: 200, failures: [line]);

    test('status checks', () {
      expect(check('Status equals 200 (got 201)').key, 'assert:statusEquals:status');
      expect(check('Status equals 204 (got 200)').key, 'assert:statusEquals:status');
      expect(check('Status is 2xx (got 404)').key, 'assert:statusIn2xx:status');
    });

    test('a JSON path keeps its path, not the expected value, and not the array index', () {
      final a = check('data.items[0].price equals 9.99 (got 10.5)');
      final b = check('data.items[3].price equals 19.99 (got Missing)');
      expect(a.key, 'assert:jsonPathEquals:data.items[].price');
      expect(a.key, b.key);
      expect(a.target, 'data.items[].price');
      expect(check('data.items exists (got Missing)').key, 'assert:jsonPathExists:data.items');
    });

    test('headers are told apart by name, case-insensitively', () {
      expect(check('Header Content-Type equals application/json (got text/html)').key, 'assert:headerEquals:content-type');
      expect(check('Header X-Request-Id exists (got Missing)').key, 'assert:headerExists:x-request-id');
    });

    test('body, time and schema checks', () {
      expect(check('Body contains "ok" (got Not found in body)').key, 'assert:bodyContains:body');
      expect(check('Response time below 500 ms (got 812 ms)').key, 'assert:responseTimeBelowMs:response time');
      expect(check('Body matches the JSON Schema (got /id: required)').key, 'assert:jsonSchema:body');
      expect(check('data matches the JSON Schema (got /id: required)').key, 'assert:jsonSchema:data');
    });

    test('where an inherited check was set does not change its cause', () {
      expect(check('Status equals 200 (got 500) (from folder "Auth")').key, 'assert:statusEquals:status');
      expect(check('Status equals 200 (from collection "Shop")').key, 'assert:statusEquals:status');
    });

    test('a variable that could not be saved', () {
      final f = check('variable token: Not found in response');
      expect((f.key, f.kind, f.target), ('extract:token', FailureKind.extraction, 'token'));
      expect(check('variable token: Not found in response (from collection "Shop")').key, 'extract:token');
    });

    test('the first line that says something is the cause; a size-limit hint alone says nothing', () {
      expect(
        _of(status: 200, failures: const ['The response was cut off at the size limit (see Settings), so tests ran on part of it.', 'Status equals 200 (got 201)']).key,
        'assert:statusEquals:status',
      );
    });

    test('any other message is normalised: numbers, ids and quoted values do not split the group', () {
      final a = _of(status: 200, failures: const ['Polling gave up after 10 tries: "pending" is not "done" (order 1234)']);
      final b = _of(status: 200, failures: const ['Polling gave up after 3 tries: "queued" is not "done" (order 99)']);
      expect(a.kind, FailureKind.other);
      expect(a.key, b.key);
    });
  });

  test('an error beats the status, and a failure with nothing to say is still a group', () {
    expect(_of(status: 500, error: 'The server at x.test did not answer within 5 seconds.').key, 'network:timeout:x.test');
    final blank = FailureFingerprinter.of(entry('r', status: 200, passed: false));
    expect(blank.key, 'other:unknown');
  });
}
