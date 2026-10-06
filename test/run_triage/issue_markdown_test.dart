// "Copy as GitHub issue": the failing causes of a run as Markdown that is safe to paste into a ticket.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/run_triage/domain/entities/run_record_doc.dart';
import 'package:postpilot/features/run_triage/domain/services/issue_markdown.dart';
import 'package:postpilot/features/run_triage/domain/services/run_record_codec.dart';
import 'package:postpilot/features/run_triage/domain/services/triage_analysis.dart';
import 'run_fixtures.dart';

const _jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U';

RunRecordDoc _failingRun() => run(
      [
        for (var i = 1; i <= 8; i++)
          entry('List $i', folder: 'Orders', method: 'GET', url: 'https://api.shop.test/orders/$i', status: 401, passed: false),
        entry('Create order', method: 'POST', url: '{{baseUrl}}/orders', status: null, ms: null, passed: false, error: 'The server at db.shop.test did not answer within 30 seconds. Raise the timeout.'),
        entry('Health'),
        entry('Metrics', skipped: 'Run if did not hold', status: null),
      ],
      environment: 'Staging',
      at: DateTime.utc(2026, 10, 6, 10, 42),
      durationMs: 14200,
    );

void main() {
  test('the title and the summary say what failed, where and when', () {
    final a = TriageAnalysis.of(_failingRun(), const []);
    final md = IssueMarkdown.build(a);
    expect(IssueMarkdown.title(a), 'PostPilot: 9 of 11 requests failed in Shop on Staging');
    expect(md, startsWith('## PostPilot: 9 of 11 requests failed in Shop (Staging)'));
    expect(md, contains('- **Environment:** Staging'));
    expect(md, contains('- **Run:** 2026-10-06 10:42 UTC, 14.2 s, from the app'));
    expect(md, contains('- **Result:** 1 passed, 9 failed, 1 skipped'));
  });

  test('lists each cause with its count, its hint and example requests, biggest first', () {
    final md = IssueMarkdown.build(TriageAnalysis.of(_failingRun(), const []));
    expect(md, contains('### 2 causes'));
    expect(md.indexOf('#### 1. HTTP 401 Unauthorized: 8 requests'), lessThan(md.indexOf('#### 2. Timeout (db.shop.test): 1 request')));
    expect(md, contains('8 requests failed with 401 (Unauthorized): the token or API key was probably rejected or has expired.'));
    // Five examples, then the rest are counted.
    expect(md, contains('- `GET https://api.shop.test/orders/1` (Orders / List 1): status 401'));
    expect(md, contains('- `GET https://api.shop.test/orders/5` (Orders / List 5): status 401'));
    expect(md, isNot(contains('/orders/6`')));
    expect(md, contains('- and 3 more'));
    expect(md, contains('- `POST {{baseUrl}}/orders` (Create order): The server at db.shop.test did not answer within 30 seconds.'));
  });

  test('says what changed since the earlier run in the same environment', () {
    final earlier = run([
      for (var i = 1; i <= 8; i++) entry('List $i', folder: 'Orders', url: 'https://api.shop.test/orders/$i'),
      entry('Create order', method: 'POST', url: '{{baseUrl}}/orders', status: 500, passed: false),
      entry('Health'),
      entry('Metrics', skipped: 'Run if did not hold', status: null),
    ], at: DateTime.utc(2026, 10, 5, 10, 40));
    final md = IssueMarkdown.build(TriageAnalysis.of(_failingRun(), [earlier]));
    expect(md, contains('### Since the earlier run (2026-10-05 10:40 UTC)'));
    expect(md, contains('8 new failures, 1 still failing'));
    expect(md, contains('- new: Orders / List 1'));
  });

  test('names the flaky requests', () {
    final history = [
      run([entry('Create order', method: 'POST', url: '{{baseUrl}}/orders'), entry('Health')]),
      run([entry('Create order', method: 'POST', url: '{{baseUrl}}/orders', status: 500, passed: false), entry('Health')]),
      run([entry('Create order', method: 'POST', url: '{{baseUrl}}/orders'), entry('Health')]),
    ];
    final md = IssueMarkdown.build(TriageAnalysis.of(_failingRun(), history));
    expect(md, contains('### Flaky'));
    expect(md, contains('Create order: passed 2 times and failed 2 of the last 4 runs'));
  });

  test('a run that passed says so', () {
    final md = IssueMarkdown.build(TriageAnalysis.of(run([entry('A'), entry('B')]), const []));
    expect(md, contains('Nothing failed in this run.'));
    expect(md, isNot(contains('### ')));
  });

  test('the monitor and the command line are named as the source', () {
    String where(RunRecordDoc d) => IssueMarkdown.build(TriageAnalysis.of(d, const []));
    expect(where(run([failedWith('A', 500)], trigger: 'monitor')), contains('by the monitor'));
    expect(where(run([failedWith('A', 500)], source: 'cli', trigger: 'cli')), contains('from the command line'));
  });

  test('a run that stopped at the first failure says so', () {
    final doc = RunRecordDoc(
      collection: 'Shop',
      startedAt: DateTime.utc(2026),
      passed: 1,
      failed: 1,
      stoppedOnFailure: true,
      results: [entry('A'), failedWith('B', 500)],
    );
    expect(IssueMarkdown.build(TriageAnalysis.of(doc, const [])), contains('stopped at the first failure'));
  });

  test('a name or a message cannot break the Markdown open', () {
    final doc = run([
      entry('Evil `name`\n## injected', status: null, passed: false, error: 'line one\n```\n## heading'),
    ], environment: 'Stag`ing');
    final md = IssueMarkdown.build(TriageAnalysis.of(doc, const []));
    expect(md.split('\n').where((l) => l.startsWith('## injected')), isEmpty);
    expect(md.split('\n').where((l) => l.trim() == '```'), isEmpty);
    expect(md, isNot(contains('Stag`ing')));
  });

  test('it holds no secret: masked texts, addresses without a query, nothing resolved', () {
    // A record made the way the app and the CLI make them: masked and shortened before it is stored.
    final raw = run([
      entry(
        'Get order',
        url: 'https://admin:hunter2pass@api.shop.test/orders?api_key=plainSecret9876&sig=$_jwt',
        status: null,
        passed: false,
        error: 'The server at api.shop.test rejected GET https://api.shop.test/o?access_token=plainSecret9876 with $_jwt',
        failures: const ['Header Authorization equals Bearer plainSecret9876'],
      ),
    ]);
    final md = IssueMarkdown.build(TriageAnalysis.of(RunRecordCodec.sanitize(raw), const []));
    for (final secret in ['hunter2pass', 'plainSecret9876', _jwt, 'api_key=']) {
      expect(md, isNot(contains(secret)));
    }
    expect(md, contains('https://api.shop.test/orders'));
  });

  test('very many causes are capped and the rest counted', () {
    final doc = run([for (var i = 0; i < 20; i++) failedWith('R$i', 400 + i)]);
    final md = IssueMarkdown.build(TriageAnalysis.of(doc, const []));
    expect(md, contains('### 20 causes'));
    expect(md, contains('#### 12.'));
    expect(md, isNot(contains('#### 13.')));
    expect(md, contains('8 more causes not listed.'));
  });
}
