// Twelve failures that are one expired token should read as one line. The fixture below is a run of 80 requests as a
// real collection produces them; the counts are worked out by hand from how it is built.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/run_triage/domain/entities/run_record_doc.dart';
import 'package:postpilot/features/run_triage/domain/services/failure_fingerprinter.dart';
import 'package:postpilot/features/run_triage/domain/services/failure_triage.dart';
import 'run_fixtures.dart';

/// 80 requests: 12 rejected with 401 (an expired token), 3 timing out against one host, 2 that answer 200 but break a
/// check at a different array index (one cause), 1 undefined variable, 1 answering 500, 5 skipped, the rest passing.
List<RunResultEntry> _eightyRequests() {
  final results = <RunResultEntry>[];
  for (var i = 1; i <= 80; i++) {
    final name = 'Request $i';
    results.add(switch (i) {
      <= 12 => entry(name, folder: 'Orders', status: 401, passed: false),
      20 || 21 || 22 => entry(name, status: null, ms: null, passed: false, error: 'The server at db.shop.test did not answer within 30 seconds. Raise the "Request timeout" in Settings if the server is just slow.'),
      30 => entry(name, status: 200, passed: false, failures: const ['data.items[0].price equals 9.99 (got 10.5)']),
      31 => entry(name, status: 200, passed: false, failures: const ['data.items[2].price equals 19.99 (got Missing)']),
      40 => entry(name, status: null, ms: null, passed: false, error: '{{orderId}} (used in the URL) is not defined. Select an environment, or add it to the collection variables or the globals.'),
      50 => entry(name, status: 500, passed: false),
      >= 70 && <= 74 => entry(name, skipped: 'Skipped: Run if did not hold', status: null, ms: null),
      _ => entry(name),
    });
  }
  return results;
}

void main() {
  late TriageReport report;
  setUp(() => report = FailureTriage.analyse(_eightyRequests()));

  test('counts every result, every failure and every skipped request', () {
    expect(report.totalResults, 80);
    expect(report.failedResults, 12 + 3 + 2 + 1 + 1);
    expect(report.skippedResults, 5);
    expect(report.hasFailures, isTrue);
  });

  test('groups the 19 failures into five causes, biggest first', () {
    expect(report.groups.map((g) => (g.fingerprint.key, g.count)).toList(), [
      ('http:401', 12),
      ('network:timeout:db.shop.test', 3),
      ('assert:jsonPathEquals:data.items[].price', 2),
      ('config:variable:orderId', 1),
      ('http:500', 1),
    ]);
    expect(report.headline, '19 failures, 5 causes');
  });

  test('every failed result is in exactly one group', () {
    final all = [for (final g in report.groups) ...g.results];
    expect(all, hasLength(report.failedResults));
    expect({for (final r in all) r.resultKey}, hasLength(report.failedResults));
    expect(all.every((r) => r.isFailed), isTrue);
  });

  test('the first example of a group is the first request that failed that way, in run order', () {
    expect(report.groups.first.first.name, 'Request 1');
    expect(report.groups[1].first.name, 'Request 20');
    expect(report.groups[2].first.name, 'Request 30');
  });

  test('ties are broken by kind (a rejected login or a dead host before a changed field), then by run order', () {
    final tie = FailureTriage.analyse([
      entry('a', status: 200, passed: false, failures: const ['Status equals 200 (got 201)']),
      entry('b', status: 500, passed: false),
      entry('c', status: 401, passed: false),
      entry('d', status: null, ms: null, passed: false, error: 'The server at x.test did not answer within 5 seconds.'),
    ]);
    expect(tie.groups.map((g) => g.fingerprint.kind).toList(), [FailureKind.auth, FailureKind.network, FailureKind.http, FailureKind.assertion]);
  });

  test('the hint for a rejected token says what probably happened and what to do', () {
    final hint = report.groups.first.hint;
    expect(hint, startsWith('12 requests failed with 401 (Unauthorized)'));
    expect(hint, contains('token or API key was probably rejected or has expired'));
    expect(hint, contains('Renew the auth'));
    expect(hint, contains('re-run the failed requests'));
  });

  test('every group has a hint that names the count and, where there is one, the host or the variable', () {
    expect(report.groups[1].hint, contains('3 requests timed out waiting for db.shop.test'));
    expect(report.groups[2].hint, contains('2 requests returned another value at data.items[].price'));
    expect(report.groups[3].hint, contains('1 request uses {{orderId}}'));
    expect(report.groups[4].hint, startsWith('1 request failed with 500 (Internal Server Error)'));
  });

  test('hints read correctly for one request and for many', () {
    String hint(List<RunResultEntry> results) => FailureTriage.analyse(results).groups.single.hint;
    expect(hint([failedWith('a', 404)]), startsWith('1 request failed with 404 (Not Found)'));
    expect(hint([failedWith('a', 404), failedWith('b', 404)]), startsWith('2 requests failed with 404 (Not Found)'));
    expect(hint([failedWith('a', 403)]), contains('credentials were accepted but are not allowed'));
    expect(hint([failedWith('a', 429)]), contains('rate limiting'));
    expect(hint([failedWith('a', 503)]), contains('down, overloaded or restarting'));
    expect(hint([failedWith('a', 422)]), contains('rejected what was sent'));
  });

  test('a data-driven run counts every pass, and says how many different requests are in a group', () {
    final results = [
      for (var pass = 1; pass <= 3; pass++) ...[
        failedWith('Login', 401, iteration: pass),
        entry('List', iteration: pass),
      ],
    ];
    final r = FailureTriage.analyse(results);
    expect(r.groups.single.count, 3);
    expect(r.groups.single.requestCount, 1);
    expect(r.failedResults, 3);
  });

  test('a run with nothing failing has no groups', () {
    final r = FailureTriage.analyse([entry('a'), entry('b'), entry('c', skipped: 'Run if', status: null)]);
    expect(r.groups, isEmpty);
    expect(r.hasFailures, isFalse);
    expect(r.headline, 'Nothing failed');
    expect(r.skippedResults, 1);
  });

  test('an empty run is fine', () {
    final r = FailureTriage.analyse(const []);
    expect((r.totalResults, r.failedResults), (0, 0));
    expect(r.groups, isEmpty);
  });

  test('network hints name the class of the failure', () {
    String hint(String error) => FailureTriage.analyse([entry('a', status: null, passed: false, error: error)]).groups.single.hint;
    expect(hint('Couldn\'t find the server "api.shop.test" — check the spelling'), contains('"api.shop.test" could not be found'));
    expect(hint('The server at localhost:3000 refused the connection — check'), contains('localhost:3000 refused the connection'));
    expect(hint('The secure connection to a.test failed: the server\'s certificate has expired.'), contains('certificate is untrusted, expired'));
    expect(hint('The server at a.test closed the connection without answering'), contains('lost the connection to a.test'));
  });

  test('a production-lock refusal and an extraction failure get their own advice', () {
    final blocked = FailureTriage.analyse([entry('a', status: null, passed: false, error: 'Refused by the production lock: POST x')]);
    expect(blocked.groups.single.hint, contains('refused by the production lock'));
    expect(blocked.groups.single.hint, contains('Nothing was sent'));
    final extract = FailureTriage.analyse([entry('a', status: 200, passed: false, failures: const ['variable token: Not found in response'])]);
    expect(extract.groups.single.hint, contains('could not save {{token}}'));
  });
}
