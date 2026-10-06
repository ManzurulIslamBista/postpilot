// The command line holds a request to its baseline the way the app's runner does, from a baseline file exported by
// the app: a request that turned on "Enforce baseline in runs" fails on a breaking change.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/cli/cli_main.dart';
import 'package:postpilot/features/cli/workspace_runner.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'package:postpilot/features/test_suggestions/domain/entities/baseline_settings.dart';
import 'package:postpilot/features/test_suggestions/domain/services/baseline_file.dart';
import 'package:postpilot/features/test_suggestions/domain/services/baseline_recorder.dart';
import 'response_fixtures.dart';

BackupRequest _request(String name, String url, {int? folderId, bool enforce = false}) => BackupRequest(
      request: ApiRequestEntity(
        id: 0,
        collectionId: 0,
        folderId: folderId,
        name: name,
        method: HttpMethod.get,
        url: url,
        headers: const [],
        queryParams: const [],
        body: RequestBody.empty,
        auth: const RequestAuth(),
      ),
      settings: enforce ? const RequestSettings(baseline: BaselineSettings(enforce: true)) : null,
    );

BackupSnapshot _workspace() => BackupSnapshot(
      exportedAt: DateTime.utc(2026),
      environments: const [],
      collections: [
        BackupCollection(
          name: 'Shop',
          folders: [const FolderEntity(id: 1, collectionId: 0, parentFolderId: null, name: 'Orders')],
          requests: [
            _request('List orders', 'https://shop.test/orders', folderId: 1, enforce: true),
            _request('Ping', 'https://shop.test/ping', enforce: true),
            _request('Free', 'https://shop.test/free'),
          ],
        ),
      ],
    );

CliResponse _answer(Object? body, {int status = 200}) => CliResponse(
      statusCode: status,
      statusMessage: status == 200 ? 'OK' : 'Error',
      headers: const {'content-type': 'application/json; charset=utf-8'},
      bodyBytes: utf8.encode(jsonEncode(body)),
      duration: const Duration(milliseconds: 15),
    );

const _orders = {'orders': [{'id': 1, 'total': 9.5}], 'page': 1};

BaselineFile _file({Object? orders = _orders, String folder = 'Orders'}) => BaselineFile([
      BaselineFileEntry(collection: 'Shop', folder: folder, name: 'List orders', method: 'GET', snapshot: BaselineRecorder.record(response(orders))),
    ]);

Future<RunSummary> _run(BaselineFile file, Map<String, CliResponse> answers) async {
  final runner = WorkspaceRunner(_workspace(), (r) async => answers[Uri.parse(r.url).path] ?? _answer({}), baselines: file);
  return runner.run(const RunOptions());
}

(IOSink, StringBuffer) _capture() {
  final controller = StreamController<List<int>>();
  final buffer = StringBuffer();
  controller.stream.transform(utf8.decoder).listen(buffer.write);
  return (IOSink(controller.sink), buffer);
}

void main() {
  group('the runner of the command line', () {
    test('an enforced request whose answer matches its baseline passes', () async {
      final summary = await _run(_file(), {'/orders': _answer(_orders), '/ping': _answer({})});
      final orders = summary.outcomes.firstWhere((o) => o.name == 'List orders');
      expect(orders.scripts.assertions.map((a) => '${a.name}|${a.passed}'), ['Baseline: 0 breaking changes|true']);
      expect(orders.passed, isTrue);
    });

    test('a breaking change fails it, and the failure names the change', () async {
      final summary = await _run(_file(), {
        '/orders': _answer({'orders': [{'id': 1, 'total': 'nine'}]}), // page removed, total became a string
        '/ping': _answer({}),
      });
      final orders = summary.outcomes.firstWhere((o) => o.name == 'List orders');
      expect(orders.passed, isFalse);
      expect(orders.scripts.assertions.single.name, 'Baseline: 2 breaking changes');
      expect(orders.failures.single, startsWith('Baseline: 2 breaking changes (got body.orders[*].total changed from number to string.'));
      expect(summary.ok, isFalse);
    });

    test('a change that cannot break a client passes', () async {
      final summary = await _run(_file(), {'/orders': _answer({..._orders, 'next': 'x'}), '/ping': _answer({})});
      expect(summary.outcomes.firstWhere((o) => o.name == 'List orders').passed, isTrue);
    });

    test('enforced but not in the file fails, and tells what to export', () async {
      final summary = await _run(_file(), {'/orders': _answer(_orders), '/ping': _answer({})});
      final ping = summary.outcomes.firstWhere((o) => o.name == 'Ping');
      expect(ping.scripts.assertions.single.name, 'Baseline: none recorded');
      expect(ping.passed, isFalse);
      expect(ping.failures.single, contains('The baseline file has no entry for this request'));
    });

    test('without a baseline file at all it says to pass one', () async {
      final summary = await _run(BaselineFile.empty, {'/orders': _answer(_orders), '/ping': _answer({})});
      expect(summary.outcomes.first.failures.single, contains('--baseline-file'));
    });

    test('a request that does not enforce a baseline is untouched', () async {
      final summary = await _run(_file(), {'/orders': _answer(_orders), '/ping': _answer({}), '/free': _answer({'anything': 1})});
      final free = summary.outcomes.firstWhere((o) => o.name == 'Free');
      expect(free.scripts.assertions, isEmpty);
      expect(free.passed, isTrue);
    });

    test('an entry is found by collection, folder, name and method: another folder is another request', () async {
      final summary = await _run(_file(folder: 'Archive'), {'/orders': _answer(_orders), '/ping': _answer({})});
      expect(summary.outcomes.first.scripts.assertions.single.name, 'Baseline: none recorded');
    });

    test('the setting travels in the workspace file: it is read back from the JSON the app writes', () {
      final text = BackupCodec.encode(_workspace());
      final settings = (jsonDecode(text) as Map)['collections'][0]['requests'][0]['settings'];
      expect(settings, {'baseline': {'enforce': true}});
      final back = BackupCodec.decode(text);
      expect(back.collections.single.requests[0].settings!.baseline.enforce, isTrue);
      expect(back.collections.single.requests[2].settings, isNull);
    });
  });

  group('postpilot run --baseline-file', () {
    late Directory dir;
    late String workspace;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('postpilot_baseline_');
      workspace = p.join(dir.path, 'workspace.json');
      File(workspace).writeAsStringSync(BackupCodec.encode(_workspace()));
    });

    tearDown(() => dir.deleteSync(recursive: true));

    Future<(int, String, String)> cli(List<String> extra, Map<String, CliResponse> answers) async {
      final (out, outText) = _capture();
      final (err, errText) = _capture();
      final code = await runCli(
        ['run', workspace, '--no-color', '--request', 'List orders', ...extra],
        sender: (r) async => answers[Uri.parse(r.url).path] ?? _answer({}),
        out: out,
        err: err,
        environment: const {},
      );
      await out.flush();
      await err.flush();
      return (code, outText.toString(), errText.toString());
    }

    test('reads the file the app exports and fails the run on a breaking change', () async {
      final path = p.join(dir.path, 'baselines.json');
      File(path).writeAsStringSync(_file().encode());
      final ok = await cli(['--baseline-file', path], {'/orders': _answer(_orders)});
      expect(ok.$1, 0, reason: ok.$2);
      final broken = await cli(['--baseline-file', path], {'/orders': _answer({'page': 1})});
      expect(broken.$1, 1);
      expect(broken.$2, contains('Baseline: 1 breaking change'));
    });

    test('a file that is missing or not a baseline file is a usage error, before anything is sent', () async {
      final missing = await cli(['--baseline-file', p.join(dir.path, 'nope.json')], {});
      expect(missing.$1, 2);
      expect(missing.$3, contains('Baseline file not found'));
      final junk = p.join(dir.path, 'junk.json');
      File(junk).writeAsStringSync('{"hello": 1}');
      final wrong = await cli(['--baseline-file', junk], {});
      expect(wrong.$1, 2);
      expect(wrong.$3, contains('not a PostPilot baseline file'));
    });

    test('the option is in the usage text', () async {
      final (out, outText) = _capture();
      await runCli(['--help'], out: out);
      await out.flush();
      expect(outText.toString(), contains('--baseline-file'));
    });
  });
}
