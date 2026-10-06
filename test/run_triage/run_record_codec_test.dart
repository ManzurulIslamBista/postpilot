// A run record is kept on disk, shown, exported and pasted into issues, so it must never hold a secret, whatever column
// it is in, and must stay small however long the run was.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/run_triage/domain/entities/run_record_doc.dart';
import 'package:postpilot/features/run_triage/domain/services/run_record_codec.dart';
import 'run_fixtures.dart';

// Secrets in the shapes the masker knows by themselves; each must be gone from every column.
const _jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U';
const _stripe = 'sk_live_4eC39HqLyjWDarjtT1zdp7dc';
const _github = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789';
const _aws = 'AKIAABCDEFGHIJKLMNOP';
const _password = 'hunter2hunter2';
const _plain = 'plainSecretValue9876';

void main() {
  group('masking', () {
    RunRecordDoc dirty() => RunRecordDoc(
          source: 'cli',
          trigger: 'cli',
          collection: 'Shop',
          // Not a place a secret belongs, but the column is scanned like the others.
          environment: 'Staging $_github',
          startedAt: DateTime.utc(2026, 10, 6),
          passed: 1,
          failed: 2,
          skipped: 1,
          results: [
            entry(
              'Get order $_stripe',
              folder: 'Orders $_aws',
              url: 'https://admin:$_password@api.shop.test/orders/42?api_key=$_plain&token=$_jwt#frag',
              status: null,
              passed: false,
              error: 'The server at api.shop.test rejected GET https://api.shop.test/orders?access_token=$_plain&x=1 with $_jwt',
              failures: [
                'Header Authorization equals Bearer $_plain',
                'data.apiKey equals $_plain (got $_stripe) (from folder "Auth")',
                'Body contains "$_github"',
              ],
            ),
            entry('Slack hook', url: 'https://hooks.slack.com/services/T0000/B0000/$_plain', skipped: 'Skipped: key $_aws not set', status: null),
            entry('Fine', url: 'https://api.shop.test/health?secret=$_plain'),
            failedWith('Other', 500),
          ],
        );

    test('no column of the stored record holds a secret', () {
      final p = RunRecordCodec.prepare(dirty());
      final columns = {
        'environmentName': p.environmentName,
        'source': p.source,
        'summaryJson': p.summaryJson,
        'resultsJson': p.resultsJson,
        'passed': '${p.passed}',
        'failed': '${p.failed}',
        'skipped': '${p.skipped}',
        'durationMs': '${p.durationMs}',
        'startedAt': p.startedAt.toIso8601String(),
      };
      for (final secret in [_jwt, _stripe, _github, _aws, _password, _plain]) {
        columns.forEach((column, value) {
          expect(value, isNot(contains(secret)), reason: 'column $column holds a secret');
        });
      }
    });

    test('the file the command line writes holds no secret either', () {
      final text = jsonEncode(RunRecordCodec.sanitize(dirty()).toJson());
      for (final secret in [_jwt, _stripe, _github, _aws, _password, _plain]) {
        expect(text, isNot(contains(secret)));
      }
    });

    test('an address loses its credentials, query and fragment but keeps host and path', () {
      expect(RunRecordCodec.safeUrl('https://admin:$_password@api.shop.test/orders/42?api_key=$_plain#frag'), 'https://api.shop.test/orders/42');
      expect(RunRecordCodec.safeUrl('{{baseUrl}}/orders/{{id}}?token={{t}}'), '{{baseUrl}}/orders/{{id}}');
      expect(RunRecordCodec.safeUrl('  https://api.shop.test/a  '), 'https://api.shop.test/a');
      expect(RunRecordCodec.safeUrl('https://user@api.shop.test/a'), 'https://api.shop.test/a');
    });

    test('a check on a credential keeps what it looks at but not what it expects or saw', () {
      expect(RunRecordCodec.safeFailure('Header Authorization equals Bearer $_plain', 300), 'Header Authorization equals ••••••');
      expect(
        RunRecordCodec.safeFailure('data.apiKey equals $_plain (got $_stripe) (from folder "Auth")', 300),
        'data.apiKey equals •••••• (from folder "Auth")',
      );
      expect(RunRecordCodec.safeFailure('Header Set-Cookie equals session=abc (got x)', 300), 'Header Set-Cookie equals ••••••');
    });

    test('an ordinary check is kept whole', () {
      expect(RunRecordCodec.safeFailure('Status equals 200 (got 500)', 300), 'Status equals 200 (got 500)');
      expect(RunRecordCodec.safeFailure('data.items[0].price equals 9.99 (got 10.5)', 300), 'data.items[0].price equals 9.99 (got 10.5)');
      expect(RunRecordCodec.safeFailure('variable token: Not found in response', 300), 'variable token: Not found in response');
    });

    test('masking keeps what triage needs: the status, the class of an error, the check type and target', () {
      final p = RunRecordCodec.prepare(dirty());
      final back = RunRecordCodec.fromColumns(
        collectionName: 'Shop',
        environmentName: p.environmentName,
        source: p.source,
        passed: p.passed,
        failed: p.failed,
        skipped: p.skipped,
        durationMs: p.durationMs,
        summaryJson: p.summaryJson,
        resultsJson: p.resultsJson,
        startedAt: p.startedAt,
      );
      final first = back.results.first;
      expect(first.url, startsWith('https://api.shop.test/orders/42'));
      expect(first.error, contains('The server at api.shop.test rejected GET'));
      expect(first.failures.first, startsWith('Header Authorization equals'));
    });
  });

  group('size cap', () {
    RunRecordDoc big({required int passing, required int failing, int textLength = 200}) {
      final results = [
        for (var i = 0; i < passing; i++) entry('Passing request number $i', folder: 'Folder ${i % 7}', url: 'https://api.shop.test/pass/$i'),
        for (var i = 0; i < failing; i++)
          entry('Failing $i', status: 500, passed: false, error: null, failures: ['x' * textLength, 'y' * textLength, 'z' * textLength]),
      ];
      return run(results);
    }

    test('a normal run is stored whole', () {
      final doc = big(passing: 80, failing: 12, textLength: 40);
      final p = RunRecordCodec.prepare(doc);
      expect(p.resultsJson.length, lessThan(RunRecordCodec.maxResultsChars));
      final back = RunRecordCodec.fromColumns(
        collectionName: 'Shop',
        environmentName: p.environmentName,
        source: p.source,
        passed: p.passed,
        failed: p.failed,
        skipped: p.skipped,
        durationMs: p.durationMs,
        summaryJson: p.summaryJson,
        resultsJson: p.resultsJson,
        startedAt: p.startedAt,
      );
      expect(back.results, hasLength(92));
      expect(back.truncated, isFalse);
    });

    test('a huge run fits under the cap, keeps every failure that fits and counts everything in the totals', () {
      final doc = big(passing: 6000, failing: 40);
      final p = RunRecordCodec.prepare(doc, maxChars: 60000);
      expect(p.resultsJson.length, lessThanOrEqualTo(60000));
      final results = (jsonDecode(p.resultsJson) as List).cast<Map<String, dynamic>>();
      final failures = results.where((r) => r['passed'] == false).toList();
      expect(failures, hasLength(40), reason: 'failures are kept before passing requests');
      expect(results.length, lessThan(6040));
      // The totals still say what really happened.
      expect((p.passed, p.failed), (6000, 40));
      expect(jsonDecode(p.summaryJson)['truncated'], isTrue);
    });

    test('passing requests lose their address before anything is dropped', () {
      final doc = big(passing: 700, failing: 0);
      final full = jsonEncode([for (final r in doc.results) r.toJson()]).length;
      final p = RunRecordCodec.prepare(doc, maxChars: full - 1000);
      final results = (jsonDecode(p.resultsJson) as List).cast<Map<String, dynamic>>();
      expect(results, hasLength(700));
      expect(results.every((r) => !r.containsKey('url')), isTrue);
      expect(jsonDecode(p.summaryJson).containsKey('truncated'), isFalse);
    });

    test('a record of nothing but failures with long texts still fits, shortening the texts', () {
      final doc = big(passing: 0, failing: 400, textLength: 290);
      final p = RunRecordCodec.prepare(doc, maxChars: 80000);
      expect(p.resultsJson.length, lessThanOrEqualTo(80000));
      expect(p.resultsJson, isNotEmpty);
      final results = (jsonDecode(p.resultsJson) as List);
      expect(results, isNotEmpty);
    });

    test('whatever the cap, the output is valid JSON', () {
      for (final cap in [500, 5000, 50000]) {
        final p = RunRecordCodec.prepare(big(passing: 300, failing: 30), maxChars: cap);
        expect(() => jsonDecode(p.resultsJson), returnsNormally, reason: 'cap $cap');
        expect(p.resultsJson.length, lessThanOrEqualTo(cap), reason: 'cap $cap');
      }
    });
  });

  group('reading', () {
    test('a record file survives a round trip', () {
      final doc = run([
        entry('A', folder: 'F', ms: 30, requestId: 5),
        failedWith('B', 401),
        entry('C', skipped: 'Run if', status: null, ms: null),
      ], source: 'cli', trigger: 'cli');
      final text = jsonEncode(doc.toJson());
      final back = RunRecordCodec.parseFile(text);
      expect(back.collection, 'Shop');
      expect(back.environment, 'Staging');
      expect(back.results.map((r) => (r.name, r.folder, r.status, r.passed, r.skipped != null)), [
        ('A', 'F', 200, true, false),
        ('B', '', 401, false, false),
        ('C', '', null, true, true),
      ]);
      expect((back.passed, back.failed, back.skipped), (1, 1, 1));
    });

    test('a file that is not a run record says so', () {
      expect(() => RunRecordCodec.parseFile('{"hello":1}'), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('not a PostPilot run record'))));
      expect(() => RunRecordCodec.parseFile('[1,2]'), throwsFormatException);
      expect(() => RunRecordCodec.parseFile('nope'), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('not valid JSON'))));
      expect(
        () => RunRecordCodec.parseFile('{"format":"postpilot-run-record","version":99,"results":[]}'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('newer format'))),
      );
      expect(() => RunRecordCodec.parseFile('{"format":"postpilot-run-record","version":1}'), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('"results"'))));
    });

    test('a hand-edited file with wrongly typed fields is read as far as it makes sense', () {
      final back = RunRecordCodec.parseFile(
        jsonEncode({
          'format': 'postpilot-run-record',
          'version': 1,
          'collection': 'Shop',
          'results': [
            {'name': 5, 'passed': 'yes', 'status': '200', 'failures': 'nope'},
            'not an object',
            {'name': 'Ok', 'passed': true, 'status': 200.0},
          ],
        }),
      );
      expect(back.results, hasLength(2));
      expect(back.results.first.name, '(unnamed)');
      expect(back.results.first.passed, isFalse);
      expect(back.results.first.status, isNull);
      expect(back.results.last.status, 200);
      expect(back.startedAt, isNotNull);
    });

    test('a damaged row reads as an empty run instead of throwing', () {
      final back = RunRecordCodec.fromColumns(
        collectionName: 'Shop',
        environmentName: 'Staging',
        source: 'app',
        passed: 3,
        failed: 1,
        skipped: 0,
        durationMs: 10,
        summaryJson: '{not json',
        resultsJson: 'also not json',
        startedAt: DateTime.utc(2026),
      );
      expect(back.results, isEmpty);
      expect((back.passed, back.failed), (3, 1));
      expect(back.collection, 'Shop');
    });
  });
}
