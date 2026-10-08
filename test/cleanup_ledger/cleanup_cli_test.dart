// `postpilot run --cleanup`: the flag is parsed, the records a run created are deleted newest first through the runner,
// a failed delete is printed and counts against the exit code, and the production lock stays in force for the deletes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/cleanup_ledger/data/cli_cleanup.dart';
import 'package:postpilot/features/cleanup_ledger/domain/entities/cleanup_settings.dart';
import 'package:postpilot/features/cli/cli_main.dart';
import 'package:postpilot/features/cli/iterated_run.dart';
import 'package:postpilot/features/cli/mcp_server.dart';
import 'package:postpilot/features/cli/production_lock.dart';
import 'package:postpilot/features/cli/workspace_runner.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';

const _on = CleanupSettings(enabled: true);

BackupRequest _req(
  String name,
  String url, {
  HttpMethod method = HttpMethod.post,
  RequestBody body = const RequestBody(type: BodyType.raw, rawText: '{"name": "Ann"}'),
  CleanupSettings? cleanup,
  int? folderId,
  RequestScriptsEntity? scripts,
}) =>
    BackupRequest(
      request: ApiRequestEntity(
        id: 0,
        collectionId: 0,
        folderId: folderId,
        name: name,
        method: method,
        url: url,
        headers: const [],
        queryParams: const [],
        body: body,
        auth: const RequestAuth(type: AuthType.inherit),
      ),
      scripts: scripts,
      settings: cleanup == null ? null : RequestSettings(flow: FlowSettings(cleanup: cleanup)),
    );

EnvironmentVariableEntity _var(String key, String value) => EnvironmentVariableEntity(id: 0, environmentId: 0, key: key, value: value, isSecret: false, enabled: true);

String _workspace(List<BackupRequest> requests, {RequestAuth? auth, List<FolderEntity> folders = const []}) => BackupCodec.encode(BackupSnapshot(
      exportedAt: DateTime.utc(2026),
      environments: [
        BackupEnvironment(name: 'Staging', variables: [_var('baseUrl', 'https://staging.test'), _var('odooUrl', 'https://odoo-staging.test')]),
        BackupEnvironment(name: 'Production', variables: [_var('baseUrl', 'https://api.test'), _var('odooUrl', 'https://odoo.test')]),
      ],
      collections: [BackupCollection(name: 'Shop', auth: auth, folders: folders, requests: requests)],
    ));

/// A server: answers by method and path, remembers every call.
final class _Server {
  final calls = <CliRequest>[];
  final Map<String, CliResponse> fixed = {};
  var _next = 100;

  CliResponse reply(Object? json, {int status = 200}) => CliResponse(
        statusCode: status,
        statusMessage: status == 200 ? 'OK' : '',
        headers: const {'content-type': 'application/json'},
        bodyBytes: utf8.encode(jsonEncode(json)),
        duration: const Duration(milliseconds: 4),
      );

  Future<CliResponse> call(CliRequest r) async {
    calls.add(r);
    final line = '${r.method} ${r.url}';
    final canned = fixed[line];
    if (canned != null) return canned;
    final path = Uri.parse(r.url).path;
    if (r.method == 'POST' && path == '/partners') return reply({'id': ++_next, 'name': 'Ann'});
    if (r.method == 'POST' && path == '/login') return reply({'token': 'tok-abc'});
    if (r.url.endsWith('/create')) return reply([++_next, ++_next]);
    return reply({'ok': true});
  }

  List<String> get lines => [for (final c in calls) '${c.method} ${c.url}'];
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
    dir = Directory.systemTemp.createTempSync('pp_cli_cleanup');
    workspace = File(p.join(dir.path, 'workspace.json'));
    server = _Server();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<({int code, String out, String err})> cli(List<String> args, String json) async {
    workspace.writeAsStringSync(json);
    final (out, outBuf) = _capture();
    final (err, errBuf) = _capture();
    final code = await runCli(args, sender: server.call, out: out, err: err, environment: const {});
    await out.flush();
    await err.flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return (code: code, out: outBuf.toString(), err: errBuf.toString());
  }

  group('the flag', () {
    test('is part of the usage text and is accepted by run', () async {
      final help = await cli(['--help'], _workspace([_req('Create', '{{baseUrl}}/partners')]));
      expect(help.out, contains('--cleanup'));
      expect(help.out, contains('Cleanup: a request with "Clean up what this request creates"'));

      final r = await cli(['run', workspace.path, '--env', 'Staging', '--cleanup', '--no-color'], _workspace([_req('Create', '{{baseUrl}}/partners')]));
      expect(r.code, 0, reason: r.err);
      expect(r.err, isNot(contains('Unknown option')));
    });

    test('a misspelt flag is still an error, and a value after the flag is a file, not part of it', () async {
      final json = _workspace([_req('Create', '{{baseUrl}}/partners')]);
      final typo = await cli(['run', workspace.path, '--cleanups'], json);
      expect(typo.code, 2);
      expect(typo.err, contains('Unknown option --cleanups'));
    });

    test('without it nothing is deleted, even for a request with cleanup switched on', () async {
      final r = await cli(['run', workspace.path, '--env', 'Staging'], _workspace([_req('Create', '{{baseUrl}}/partners', cleanup: _on)]));

      expect(r.code, 0);
      expect(server.lines, ['POST https://staging.test/partners']);
      expect(r.out, isNot(contains('Cleanup')));
    });

    test('the MCP server has no cleanup: the flag is refused there and no tool deletes what a request created', () async {
      final json = _workspace([_req('Create', '{{baseUrl}}/partners', cleanup: _on)]);
      final r = await cli(['mcp', workspace.path, '--env', 'Staging', '--cleanup'], json);
      expect(r.code, 2);
      expect(r.err, contains('--cleanup is for "postpilot run"'));

      final runner = WorkspaceRunner.parse(json, server.call);
      final tools = jsonDecode((await McpServer(runner, const RunOptions(), const {}).handleLine(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'})))!)['result']['tools'] as List;
      expect(jsonEncode(tools).toLowerCase(), isNot(contains('cleanup')));
    });
  });

  group('deleting what a run created', () {
    test('goes newest first, prints each record, and exits 0 when everything went', () async {
      final json = _workspace([
        _req('Create A', '{{baseUrl}}/partners', cleanup: _on),
        _req('Create B', '{{baseUrl}}/partners', cleanup: _on),
        _req('List', '{{baseUrl}}/partners', method: HttpMethod.get),
        _req('Create C', '{{baseUrl}}/partners', cleanup: _on),
      ]);

      final r = await cli(['run', workspace.path, '--env', 'Staging', '--cleanup', '--no-color'], json);

      expect(r.code, 0, reason: r.out + r.err);
      expect(server.lines, [
        'POST https://staging.test/partners',
        'POST https://staging.test/partners',
        'GET https://staging.test/partners',
        'POST https://staging.test/partners',
        'DELETE https://staging.test/partners/103',
        'DELETE https://staging.test/partners/102',
        'DELETE https://staging.test/partners/101',
      ]);
      expect(r.out, contains('Cleanup: 3 records were created by this run, deleting the newest first.'));
      expect(r.out, contains('  deleted  Shop / Create C  DELETE {{baseUrl}}/partners/103'));
      expect(r.out.indexOf('Create C  DELETE'), lessThan(r.out.indexOf('Create A  DELETE')));
      expect(r.out, contains('Cleanup: 3 records deleted.'));
    });

    test('an Odoo create is unlinked on the same server with the ids it made', () async {
      final json = _workspace([
        _req('Create partners', '{{odooUrl}}/json/2/res.partner/create', body: const RequestBody(type: BodyType.raw, rawText: '{"vals_list": [{"name": "A"}, {"name": "B"}]}'), cleanup: _on),
      ]);

      final r = await cli(['run', workspace.path, '--env', 'Staging', '--cleanup', '--no-color'], json);

      expect(r.code, 0, reason: r.out + r.err);
      expect(server.lines, ['POST https://odoo-staging.test/json/2/res.partner/create', 'POST https://odoo-staging.test/json/2/res.partner/unlink']);
      expect(jsonDecode(utf8.decode(server.calls.last.body!)), {'ids': [101, 102]});
      expect(r.out, contains('Odoo unlink res.partner [101, 102]'));
      expect(r.out, contains('Cleanup: 2 records deleted.'));
    });

    test('a delete that fails is printed with the reason, the others still go, and the exit code is 1', () async {
      server.fixed['DELETE https://staging.test/partners/102'] = server.reply({'message': 'Record does not exist.'}, status: 404);
      final json = _workspace([
        _req('Create A', '{{baseUrl}}/partners', cleanup: _on),
        _req('Create B', '{{baseUrl}}/partners', cleanup: _on),
        _req('Create C', '{{baseUrl}}/partners', cleanup: _on),
      ]);

      final r = await cli(['run', workspace.path, '--env', 'Staging', '--cleanup', '--no-color'], json);

      expect(r.code, 1, reason: 'the requests passed; the cleanup did not');
      expect(server.lines.where((l) => l.startsWith('DELETE')), hasLength(3));
      expect(r.out, contains('  FAILED   Shop / Create B  DELETE {{baseUrl}}/partners/102'));
      expect(r.out, contains('HTTP 404: Record does not exist.'));
      expect(r.out, contains('Cleanup: 2 records deleted, 1 delete failed.'));
    });

    test('a create whose record cannot be found is reported, and counts against the exit code', () async {
      server.fixed['POST https://staging.test/partners'] = server.reply({'ok': true});
      final r = await cli(['run', workspace.path, '--env', 'Staging', '--cleanup', '--no-color'], _workspace([_req('Create A', '{{baseUrl}}/partners', cleanup: _on)]));

      expect(r.code, 1);
      expect(r.out, contains('not cleaned up  Shop / Create A: No id found in the response'));
      expect(r.out, contains('1 create could not be cleaned up'));
      expect(server.lines, ['POST https://staging.test/partners']);
    });

    test('says so when no request asks for cleanup, and changes nothing', () async {
      final r = await cli(['run', workspace.path, '--env', 'Staging', '--cleanup', '--no-color'], _workspace([_req('Create', '{{baseUrl}}/partners')]));

      expect(r.code, 0);
      expect(r.out, contains('no request has "Clean up what this request creates" switched on'));
      expect(server.lines, ['POST https://staging.test/partners']);
    });

    test('with a JSON report on stdout the summary goes to stderr, so the report stays parseable', () async {
      final r = await cli(['run', workspace.path, '--env', 'Staging', '--cleanup', '--report', 'json'], _workspace([_req('Create A', '{{baseUrl}}/partners', cleanup: _on)]));

      expect(r.code, 0);
      expect(() => jsonDecode(r.out), returnsNormally);
      expect(r.err, contains('Cleanup: 1 record deleted.'));
    });

    test('another request is the undo, sent with the created id, in a folder too', () async {
      final json = _workspace(
        [
          _req('Create A', '{{baseUrl}}/partners', cleanup: const CleanupSettings(enabled: true, undo: CleanupUndo.request, request: 'Cleanup/Remove partner')),
          _req('Remove partner', '{{baseUrl}}/remove/{{created.id}}/by/{{created.name}}', method: HttpMethod.delete, folderId: 1),
        ],
        folders: const [FolderEntity(id: 1, collectionId: 0, parentFolderId: null, name: 'Cleanup')],
      );

      final r = await cli(['run', workspace.path, '--env', 'Staging', '--cleanup', '--no-color', '--request', 'Create A'], json);

      expect(r.code, 0, reason: r.out + r.err);
      expect(server.lines, ['POST https://staging.test/partners', 'DELETE https://staging.test/remove/101/by/Ann']);
    });

    test('an undo request that does not exist fails that delete with a clear reason', () async {
      final json = _workspace([_req('Create A', '{{baseUrl}}/partners', cleanup: const CleanupSettings(enabled: true, undo: CleanupUndo.request, request: 'Nowhere'))]);

      final r = await cli(['run', workspace.path, '--env', 'Staging', '--cleanup', '--no-color'], json);

      expect(r.code, 1);
      expect(r.out, contains('No single request of the collection is called "Nowhere"'));
      expect(server.lines, ['POST https://staging.test/partners']);
    });

    test('each pass of a --data run is cleaned with the row it ran with', () async {
      final data = File(p.join(dir.path, 'rows.csv'))..writeAsStringSync('region\neu\nus\n');
      final json = _workspace([
        _req('Create A', '{{baseUrl}}/partners', cleanup: const CleanupSettings(enabled: true, undo: CleanupUndo.request, request: 'Remove partner')),
        _req('Remove partner', '{{baseUrl}}/remove/{{created.id}}?region={{region}}', method: HttpMethod.delete),
      ]);

      final r = await cli(['run', workspace.path, '--env', 'Staging', '--cleanup', '--no-color', '--data', data.path, '--request', 'Create A'], json);

      expect(r.code, 0, reason: r.out + r.err);
      expect(server.lines.where((l) => l.startsWith('DELETE')), [
        'DELETE https://staging.test/remove/102?region=us',
        'DELETE https://staging.test/remove/101?region=eu',
      ]);
    });

    test('a variable a request of the run saved is still there for the delete (a token from a login)', () async {
      final login = _req(
        'Login',
        '{{baseUrl}}/login',
        scripts: RequestScriptsEntity(
          requestId: 0,
          assertionsJson: '[]',
          extractorsJson: ScriptsJsonCodec.encodeExtractors([ExtractorEntity(path: r'$.token', variableKey: 'token')]),
        ),
      );
      final json = _workspace(
        [login, _req('Create A', '{{baseUrl}}/partners', cleanup: _on)],
        auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}'),
      );

      final r = await cli(['run', workspace.path, '--env', 'Staging', '--cleanup', '--no-color'], json);

      expect(r.code, 0, reason: r.out + r.err);
      final delete = server.calls.last;
      expect(delete.method, 'DELETE');
      expect(delete.headers['Authorization'], 'Bearer tok-abc', reason: 'the delete is authorised like the requests of the run');
      expect(r.out, isNot(contains('tok-abc')), reason: 'a token never reaches the output');
    });
  });

  group('the production lock', () {
    test('a run in Production is refused as a whole, and no cleanup follows', () async {
      final r = await cli(['run', workspace.path, '--env', 'Production', '--cleanup', '--no-color'], _workspace([_req('Create A', '{{baseUrl}}/partners', cleanup: _on)]));

      expect(r.code, 2);
      expect(server.calls, isEmpty);
      expect(r.err, contains('Production lock'));
      expect(r.out, isNot(contains('Cleanup')));
    });

    test('--allow-production lets the run create and the cleanup delete, as it lets any request through', () async {
      final r = await cli(['run', workspace.path, '--env', 'Production', '--allow-production', '--cleanup', '--no-color'], _workspace([_req('Create A', '{{baseUrl}}/partners', cleanup: _on)]));

      expect(r.code, 0, reason: r.out + r.err);
      expect(server.lines, ['POST https://api.test/partners', 'DELETE https://api.test/partners/101']);
    });

    test('a delete the lock refuses is not sent: a create that reads like a GET passes the lock, its DELETE does not', () async {
      final json = _workspace([_req('Create by GET', '{{baseUrl}}/partners/new', method: HttpMethod.get, cleanup: const CleanupSettings(enabled: true, undo: CleanupUndo.restDelete))]);
      server.fixed['GET https://api.test/partners/new'] = server.reply({'id': 7});
      final runner = WorkspaceRunner.parse(json, server.call);
      RunOptions options(Map<String, String> row) => const RunOptions(environment: 'Production');
      final run = await runIterated(runner, optionsFor: options, processVariables: const {});

      final report = await runCliCleanup(runner: runner, run: run, optionsFor: options, processVariables: const {});

      expect(server.lines, ['GET https://api.test/partners/new'], reason: 'the DELETE was never sent');
      expect(report.failed, 1);
      expect(report.hasFailures, isTrue);
      expect(report.text, contains('Refused by the production lock'));
      expect(report.text, contains('DELETE'));
    });

    test('the same delete goes when the person who started the process allowed production', () async {
      final json = _workspace([_req('Create by GET', '{{baseUrl}}/partners/new', method: HttpMethod.get, cleanup: const CleanupSettings(enabled: true, undo: CleanupUndo.restDelete))]);
      server.fixed['GET https://api.test/partners/new'] = server.reply({'id': 7});
      final runner = WorkspaceRunner.parse(json, server.call);
      RunOptions options(Map<String, String> row) => const RunOptions(environment: 'Production', production: ProductionLock(allow: true));
      final run = await runIterated(runner, optionsFor: options, processVariables: const {});

      final report = await runCliCleanup(runner: runner, run: run, optionsFor: options, processVariables: const {});

      expect(server.lines, ['GET https://api.test/partners/new', 'DELETE https://api.test/partners/new/7']);
      expect(report.deleted, 1);
      expect(report.hasFailures, isFalse);
    });

    test('a production host named on the command line locks the cleanup too', () async {
      final json = _workspace([_req('Create by GET', '{{baseUrl}}/partners/new', method: HttpMethod.get, cleanup: const CleanupSettings(enabled: true, undo: CleanupUndo.restDelete))]);
      server.fixed['GET https://staging.test/partners/new'] = server.reply({'id': 7});
      final runner = WorkspaceRunner.parse(json, server.call);
      RunOptions options(Map<String, String> row) => const RunOptions(environment: 'Staging', production: ProductionLock(hosts: ['staging.test']));
      final run = await runIterated(runner, optionsFor: options, processVariables: const {});

      final report = await runCliCleanup(runner: runner, run: run, optionsFor: options, processVariables: const {});

      expect(server.lines, ['GET https://staging.test/partners/new']);
      expect(report.text, contains('production'));
      expect(report.failed, 1);
    });
  });
}
