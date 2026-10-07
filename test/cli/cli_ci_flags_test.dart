// The command-line options that CI needs: Markdown reports and the GitHub job summary, repeated runs (--iterations,
// --data) and run records the app can import. Each case is driven through runCli with a scripted server; the expected
// counts are worked out from the workspace below.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/cli/cli_main.dart';
import 'package:postpilot/features/cli/workspace_runner.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/run_triage/domain/services/run_record_codec.dart';

BackupRequest _req(String name, String url, {HttpMethod method = HttpMethod.get}) => BackupRequest(
      request: ApiRequestEntity(
        id: 0,
        collectionId: 0,
        folderId: null,
        name: name,
        method: method,
        url: url,
        headers: const [],
        queryParams: const [],
        body: method == HttpMethod.post ? const RequestBody(type: BodyType.raw, rawText: '{"x":1}') : RequestBody.empty,
        auth: const RequestAuth(type: AuthType.none),
      ),
    );

/// One collection "Shop" with three requests; `id` defaults to 1, a data column or --var overrides it.
String _workspace({bool secondCollection = false}) => BackupCodec.encode(BackupSnapshot(
      exportedAt: DateTime.utc(2026),
      environments: [
        BackupEnvironment(name: 'Staging', variables: [
          EnvironmentVariableEntity(id: 0, environmentId: 0, key: 'host', value: 'https://staging.shop.test', isSecret: false, enabled: true),
        ]),
      ],
      collections: [
        BackupCollection(
          name: 'Shop',
          variables: [CollectionVariableEntity(id: 0, collectionId: 0, key: 'id', value: '1', enabled: true)],
          requests: [
            _req('List orders', '{{host}}/orders?token=abc123secretvalue'),
            _req('Get order', '{{host}}/orders/{{id}}'),
            _req('Create order', '{{host}}/orders', method: HttpMethod.post),
          ],
        ),
        if (secondCollection) BackupCollection(name: 'Billing', requests: [_req('Invoices', '{{host}}/invoices')]),
      ],
    ));

/// Orders 3 and 7 do not exist; everything else answers 200.
final class _Server {
  final calls = <String>[];
  Future<CliResponse> call(CliRequest r) async {
    calls.add('${r.method} ${r.url}');
    final path = Uri.parse(r.url).path;
    final status = (path == '/orders/3' || path == '/orders/7') ? 404 : 200;
    return CliResponse(statusCode: status, statusMessage: status == 200 ? 'OK' : 'Not Found', headers: const {}, bodyBytes: utf8.encode('{}'), duration: const Duration(milliseconds: 15));
  }
}

(IOSink, StringBuffer) _capture() {
  final controller = StreamController<List<int>>();
  final buffer = StringBuffer();
  controller.stream.transform(utf8.decoder).listen(buffer.write);
  return (IOSink(controller.sink), buffer);
}

void main() {
  late Directory dir;
  late File workspace;
  late _Server server;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pp_cli_ci');
    workspace = File(p.join(dir.path, 'workspace.json'))..writeAsStringSync(_workspace());
    server = _Server();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<({int code, String out, String err})> cli(List<String> args, {Map<String, String> env = const {}}) async {
    final (out, outBuf) = _capture();
    final (err, errBuf) = _capture();
    final code = await runCli(
      ['run', workspace.path, '--env', 'Staging', '--no-color', ...args],
      sender: server.call,
      out: out,
      err: err,
      environment: env,
      now: () => DateTime.utc(2026, 10, 6, 10, 42, 7),
    );
    await out.flush();
    await err.flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return (code: code, out: outBuf.toString(), err: errBuf.toString());
  }

  File dataFile(String name, String text) => File(p.join(dir.path, name))..writeAsStringSync(text);

  group('--report markdown', () {
    test('a passing run says so, with the totals', () async {
      final r = await cli(['--report', 'markdown']);
      expect(r.code, 0, reason: r.out);
      expect(r.out, startsWith('## PostPilot: all 3 requests passed'));
      expect(r.out, contains('environment `Staging`'));
      expect(r.out, contains('| 3 | 3 | 0 | 0 |'));
      expect(r.out, isNot(contains('What broke')));
      expect(server.calls, hasLength(3));
    });

    test('a failing run groups the failure by cause, with a hint and the failing request in a table', () async {
      final r = await cli(['--report', 'markdown', '--var', 'id=3']);
      expect(r.code, 1);
      expect(r.out, startsWith('## PostPilot: 1 of 3 requests failed'));
      expect(r.out, contains('### What broke (1 failure, 1 cause)'));
      expect(r.out, contains('- **HTTP 404 Not Found**, 1 request: 1 request failed with 404 (Not Found): nothing was found at that address'));
      expect(r.out, contains('| GET Shop / Get order | 404 | HTTP 404 Not Found |'));
    });

    test('--out writes the Markdown to a file and the screen keeps the console summary', () async {
      final out = p.join(dir.path, 'summary.md');
      final r = await cli(['--report', 'markdown', '--out', out, '--var', 'id=3']);
      expect(File(out).readAsStringSync(), startsWith('## PostPilot: 1 of 3 requests failed'));
      expect(r.out, contains('Report written to $out'));
      expect(r.out, contains('3 requests, 2 passed, 1 failed'));
    });

    test('--markdown-out writes the summary in addition to the report that was asked for', () async {
      final md = p.join(dir.path, 'extra.md');
      final xml = p.join(dir.path, 'report.xml');
      final r = await cli(['--report', 'junit', '--out', xml, '--markdown-out', md, '--var', 'id=3']);
      expect(File(xml).readAsStringSync(), contains('<testsuites'));
      expect(File(md).readAsStringSync(), contains('## PostPilot: 1 of 3 requests failed'));
      expect(r.out, contains('Markdown summary written to $md'));
    });

    test('an unwritable path is reported on stderr and does not change the exit code', () async {
      final r = await cli(['--markdown-out', p.join(dir.path, 'no-such-folder', 'x.md'), '--var', 'id=3']);
      expect(r.code, 1, reason: 'the requests decide the exit code');
      expect(r.err, contains('Could not write the Markdown summary'));
    });

    test('the Markdown holds no secret value: the query secret of a URL is masked', () async {
      // The failing run reports the masked address of every request.
      final r = await cli(['--report', 'markdown', '--var', 'id=3', '--var', 'extra=hunter2hunter2']);
      expect(r.out, isNot(contains('abc123secretvalue')));
    });
  });

  group(r'$GITHUB_STEP_SUMMARY', () {
    test('the summary is appended to the file when the variable is set, whatever --report says', () async {
      final summary = File(p.join(dir.path, 'step-summary.md'))..writeAsStringSync('Earlier step\n');
      final r = await cli(['--var', 'id=3'], env: {'GITHUB_STEP_SUMMARY': summary.path});
      expect(r.code, 1);
      final text = summary.readAsStringSync();
      expect(text, startsWith('Earlier step\n'));
      expect(text, contains('## PostPilot: 1 of 3 requests failed'));
      expect(text.endsWith('\n'), isTrue);
      // The console report on screen is the usual one.
      expect(r.out, contains('✖ GET'));
    });

    test('two runs append two summaries', () async {
      final summary = File(p.join(dir.path, 'step-summary.md'));
      await cli([], env: {'GITHUB_STEP_SUMMARY': summary.path});
      await cli(['--var', 'id=3'], env: {'GITHUB_STEP_SUMMARY': summary.path});
      expect('## PostPilot:'.allMatches(summary.readAsStringSync()), hasLength(2));
    });

    test('without the variable nothing is written anywhere', () async {
      await cli(['--var', 'id=3']);
      expect(dir.listSync().map((e) => p.basename(e.path)), ['workspace.json']);
    });

    test('an empty variable counts as not set', () async {
      final r = await cli([], env: {'GITHUB_STEP_SUMMARY': ''});
      expect(r.code, 0);
      expect(r.err, isEmpty);
    });
  });

  group('--iterations', () {
    test('repeats the whole run, names each pass, and the exit code covers every pass', () async {
      final r = await cli(['--iterations', '3']);
      expect(r.code, 0, reason: r.out);
      expect(server.calls, hasLength(9));
      expect(r.out, contains('── Pass 1 of 3 ──'));
      expect(r.out, contains('── Pass 3 of 3 ──'));
      expect(r.out, contains('(iteration 2)'));
      expect(r.out, contains('9 requests, 9 passed'));
    });

    test('a failure in any pass fails the run; JUnit and JSON say which pass', () async {
      final xml = p.join(dir.path, 'r.xml');
      // Pass 1 and 3 use the id 1 and 2, pass 2 uses 3, which does not exist.
      final data = dataFile('rows.csv', 'id\n1\n3\n2\n');
      final r = await cli(['--data', data.path, '--report', 'junit', '--out', xml]);
      expect(r.code, 1);
      final junit = File(xml).readAsStringSync();
      expect(junit, contains('tests="9" failures="1"'));
      expect(junit, contains('name="GET Get order (iteration 2)"'));
      expect(junit, contains('name="GET Get order (iteration 1)"'));

      final json = jsonDecode((await cli(['--data', data.path, '--report', 'json'])).out) as Map<String, dynamic>;
      expect(json['iterations'], 3);
      final requests = (json['requests'] as List).cast<Map<String, dynamic>>();
      expect(requests.map((r) => r['iteration']), [1, 1, 1, 2, 2, 2, 3, 3, 3]);
      expect(requests.where((r) => r['passed'] == false).single['iteration'], 2);
    });

    test('must be a whole number from 1 to 1000', () async {
      for (final bad in ['0', '1001', 'many', '-2', '1.5']) {
        final r = await cli(['--iterations', bad]);
        expect(r.code, 2, reason: bad);
        expect(r.err, contains('--iterations needs a whole number from 1 to 1000'));
      }
      expect(server.calls, isEmpty, reason: 'nothing is sent before the options are accepted');
    });

    test('a run without the flag reports exactly as before: no pass headers, no iteration in the names', () async {
      final r = await cli([]);
      expect(r.out, isNot(contains('Pass 1')));
      expect(r.out, isNot(contains('iteration')));
    });
  });

  group('--data', () {
    test('each row is one pass and its columns are variables, beating --var and the collection', () async {
      final data = dataFile('rows.csv', 'id\n2\n7\n');
      final r = await cli(['--data', data.path, '--var', 'id=99']);
      expect(server.calls.where((c) => c.contains('/orders/')), ['GET https://staging.shop.test/orders/2', 'GET https://staging.shop.test/orders/7']);
      expect(r.code, 1, reason: 'order 7 does not exist');
    });

    test('a JSON array of objects works the same way', () async {
      final data = dataFile('rows.json', '[{"id": 1}, {"id": 2}]');
      final r = await cli(['--data', data.path]);
      expect(r.code, 0, reason: r.out);
      expect(server.calls.where((c) => c.contains('/orders/')), hasLength(2));
    });

    test('the data replaces --iterations, and says so', () async {
      final data = dataFile('rows.csv', 'id\n1\n2\n');
      final r = await cli(['--data', data.path, '--iterations', '5']);
      expect(server.calls, hasLength(6));
      expect(r.err, contains('--iterations is ignored: the data file has 2 rows'));
    });

    test('--bail ends the whole run after the first pass with a failure', () async {
      // Pass 1 is fine, pass 2 (id 3) fails at its second request, so pass 3 never starts.
      final data = dataFile('rows.csv', 'id\n1\n3\n2\n');
      final r = await cli(['--data', data.path, '--bail']);
      expect(r.code, 1);
      expect(server.calls, hasLength(3 + 2));
      expect(r.out, contains('── Pass 2 of 3 ──'));
      expect(r.out, isNot(contains('── Pass 3 of 3 ──')));
    });

    test('a data file that cannot be used is refused before anything is sent, with the reason', () async {
      final cases = <String, String>{
        'missing': 'Data file not found',
        'empty.csv': 'has no rows',
        'header-only.csv': 'needs a header row and at least one row',
        'dup.csv': 'appears more than once',
        'bad col.csv': "can't be used as a variable",
        'broken.json': 'Invalid JSON',
        'scalar.json': 'is not an object',
      };
      dataFile('empty.csv', '');
      dataFile('header-only.csv', 'id');
      dataFile('dup.csv', 'id,id\n1,2');
      dataFile('bad col.csv', 'a b\n1');
      dataFile('broken.json', '[{"id":1},');
      dataFile('scalar.json', '[1, 2]');
      for (final entry in cases.entries) {
        final path = entry.key == 'missing' ? p.join(dir.path, 'nope.csv') : p.join(dir.path, entry.key);
        final r = await cli(['--data', path]);
        expect(r.code, 2, reason: entry.key);
        expect(r.err, contains(entry.value), reason: entry.key);
      }
      expect(server.calls, isEmpty);
    });

    test('the data values never appear in the output', () async {
      final data = dataFile('rows.csv', 'id,password\n1,hunter2hunter2\n');
      final r = await cli(['--data', data.path, '--report', 'markdown']);
      expect(r.out, isNot(contains('hunter2hunter2')));
      expect(r.err, isNot(contains('hunter2hunter2')));
    });

    test('the production lock looks at every row: a row that points at a production host is refused as a whole', () async {
      final prod = BackupCodec.encode(BackupSnapshot(
        exportedAt: DateTime.utc(2026),
        environments: [
          BackupEnvironment(name: 'Staging', variables: [
            EnvironmentVariableEntity(id: 0, environmentId: 0, key: 'host', value: 'https://staging.shop.test', isSecret: false, enabled: true),
          ]),
        ],
        collections: [
          BackupCollection(name: 'Shop', requests: [_req('Create order', '{{host}}/orders', method: HttpMethod.post)]),
        ],
      ));
      workspace.writeAsStringSync(prod);
      final data = dataFile('hosts.csv', 'host\nhttps://staging.shop.test\nhttps://api.live.shop.test\n');
      final r = await cli(['--data', data.path, '--production-host', 'live.shop.test']);
      expect(r.code, 2);
      expect(r.err, contains('Production lock'));
      expect(r.err, contains('live.shop.test'));
      expect(server.calls, isEmpty, reason: 'sending the staging row and then stopping would be worse than sending nothing');
    });
  });

  group('--records-dir', () {
    test('writes one record per collection that the app can read back, masked, with the pass of each result', () async {
      workspace.writeAsStringSync(_workspace(secondCollection: true));
      final records = p.join(dir.path, 'records', 'nested');
      final data = dataFile('rows.csv', 'id\n1\n3\n');
      final r = await cli(['--data', data.path, '--records-dir', records]);
      expect(r.code, 1);
      final files = Directory(records).listSync().map((e) => p.basename(e.path)).toList()..sort();
      expect(files, [
        'postpilot-run-20261006T104207Z-Billing.json',
        'postpilot-run-20261006T104207Z-Shop.json',
      ]);
      expect(r.out, contains('Run record written to ${p.join(records, 'postpilot-run-20261006T104207Z-Shop.json')}'));

      final shop = RunRecordCodec.parseFile(File(p.join(records, files.last)).readAsStringSync());
      expect(shop.collection, 'Shop');
      expect(shop.environment, 'Staging');
      expect(shop.source, 'cli');
      expect(shop.iterations, 2);
      expect((shop.passed, shop.failed, shop.skipped), (5, 1, 0));
      expect(shop.results.map((e) => (e.iteration, e.name)), [
        (1, 'List orders'),
        (1, 'Get order'),
        (1, 'Create order'),
        (2, 'List orders'),
        (2, 'Get order'),
        (2, 'Create order'),
      ]);
      final failed = shop.results.singleWhere((e) => e.isFailed);
      expect((failed.iteration, failed.name, failed.status), (2, 'Get order', 404));
      expect(failed.url, 'https://staging.shop.test/orders/3');

      final billing = RunRecordCodec.parseFile(File(p.join(records, files.first)).readAsStringSync());
      expect((billing.collection, billing.failed, billing.iterations), ('Billing', 0, 2));
      expect(billing.results.map((e) => (e.iteration, e.name)), [(1, 'Invoices'), (2, 'Invoices')]);
    });

    test('the file holds no query string and no secret', () async {
      final records = p.join(dir.path, 'records');
      await cli(['--records-dir', records, '--var', 'id=3']);
      final text = Directory(records).listSync().whereType<File>().map((f) => f.readAsStringSync()).join();
      expect(text, isNot(contains('abc123secretvalue')));
      expect(text, isNot(contains('token=')));
      expect(text, contains('https://staging.shop.test/orders'));
    });

    test('a second run in the same second does not overwrite the first record', () async {
      final records = p.join(dir.path, 'records');
      await cli(['--records-dir', records]);
      await cli(['--records-dir', records]);
      expect(Directory(records).listSync(), hasLength(2));
    });

    test('--bail marks the record as stopped at the first failure', () async {
      final records = p.join(dir.path, 'records');
      await cli(['--records-dir', records, '--var', 'id=3', '--bail']);
      final doc = RunRecordCodec.parseFile(Directory(records).listSync().whereType<File>().single.readAsStringSync());
      expect(doc.stoppedOnFailure, isTrue);
      expect(doc.results.map((e) => e.name), ['List orders', 'Get order']);
    });

    test('a folder that cannot be created is reported and does not change the exit code', () async {
      final blocker = File(p.join(dir.path, 'file-not-folder'))..writeAsStringSync('x');
      final r = await cli(['--records-dir', p.join(blocker.path, 'inside')]);
      expect(r.code, 0);
      expect(r.err, contains('Could not write the run records'));
    });
  });

  test('every new option is in the usage text', () async {
    final (out, buf) = _capture();
    await runCli(['--help'], out: out);
    await out.flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final usage = buf.toString();
    for (final option in ['--report <kind>', 'markdown', '--markdown-out', '--iterations', '--data', '--records-dir', 'GITHUB_STEP_SUMMARY']) {
      expect(usage, contains(option));
    }
  });
}
