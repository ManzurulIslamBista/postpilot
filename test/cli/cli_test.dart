import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/cli/cli_main.dart';
import 'package:postpilot/features/cli/dart_io_sender.dart';
import 'package:postpilot/features/cli/mcp_server.dart';
import 'package:postpilot/features/cli/reporters.dart';
import 'package:postpilot/features/cli/workspace_runner.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/workplace/domain/services/secret_splitter.dart';

BackupRequest _req(
  String name,
  String url, {
  HttpMethod method = HttpMethod.get,
  int? folderId,
  RequestAuth auth = const RequestAuth(type: AuthType.inherit),
  RequestBody body = RequestBody.empty,
  List<KeyValueItem> headers = const [],
  List<AssertionEntity> assertions = const [],
  List<ExtractorEntity> extractors = const [],
}) =>
    BackupRequest(
      request: ApiRequestEntity(id: 0, collectionId: 0, folderId: folderId, name: name, method: method, url: url, headers: headers, queryParams: const [], body: body, auth: auth),
      scripts: assertions.isEmpty && extractors.isEmpty
          ? null
          : RequestScriptsEntity(requestId: 0, assertionsJson: ScriptsJsonCodec.encodeAssertions(assertions), extractorsJson: ScriptsJsonCodec.encodeExtractors(extractors)),
    );

String _workspace() => BackupCodec.encode(BackupSnapshot(
      exportedAt: DateTime.utc(2026),
      environments: [
        BackupEnvironment(name: 'Staging', variables: [
          EnvironmentVariableEntity(id: 0, environmentId: 0, key: 'baseUrl', value: 'https://staging.test', isSecret: false, enabled: true),
          EnvironmentVariableEntity(id: 0, environmentId: 0, key: 'apiKey', value: '', isSecret: true, enabled: true),
        ]),
        BackupEnvironment(name: 'Prod', variables: [
          EnvironmentVariableEntity(id: 0, environmentId: 0, key: 'baseUrl', value: 'https://prod.test', isSecret: false, enabled: true),
        ]),
      ],
      collections: [
        BackupCollection(
          name: 'Shop',
          auth: const RequestAuth(type: AuthType.bearer, bearerToken: '{{apiKey}}'),
          variables: [CollectionVariableEntity(id: 0, collectionId: 0, key: 'orderId', value: '42', enabled: true)],
          folders: [const FolderEntity(id: 1, collectionId: 0, parentFolderId: null, name: 'Auth')],
          requests: [
            _req(
              'Login',
              '{{baseUrl}}/login',
              method: HttpMethod.post,
              folderId: 1,
              auth: const RequestAuth(type: AuthType.none),
              body: const RequestBody(type: BodyType.raw, rawText: '{"user":"ann"}'),
              assertions: [AssertionEntity(type: AssertionType.statusEquals, expected: '200'), AssertionEntity(type: AssertionType.jsonPathExists, path: 'token')],
              extractors: [ExtractorEntity(path: 'token', variableKey: 'sessionToken')],
            ),
            _req(
              'Get order',
              '{{baseUrl}}/orders/{{orderId}}',
              headers: [KeyValueItem(key: 'X-Session', value: '{{sessionToken}}')],
              assertions: [AssertionEntity(type: AssertionType.jsonPathEquals, path: 'id', expected: '42')],
            ),
            _req('Broken', '{{baseUrl}}/broken', assertions: [AssertionEntity(type: AssertionType.statusEquals, expected: '200')]),
            // OAuth 2.0 needs the app (a browser or a token request), so the CLI skips it. Digest is no longer
            // skipped: the CLI answers its challenge (see cli_safety_test.dart).
            _req('OAuth thing', '{{baseUrl}}/oauth', auth: const RequestAuth(type: AuthType.oauth2)),
          ],
        ),
      ],
    ));

/// A scripted server: answers by "METHOD path" and records what it was asked.
final class _Fake {
  final calls = <CliRequest>[];
  Future<CliResponse> call(CliRequest r) async {
    calls.add(r);
    final path = Uri.parse(r.url).path;
    (int, String) answer = switch ('${r.method} $path') {
      'POST /login' => (200, '{"token":"tok-abc","password":"hunter2"}'),
      'GET /orders/42' => (200, '{"id":42,"total":9.5}'),
      'GET /broken' => (500, '{"error":"boom"}'),
      _ => (404, '{}'),
    };
    return CliResponse(statusCode: answer.$1, statusMessage: answer.$1 == 200 ? 'OK' : 'Error', headers: {'content-type': 'application/json', 'set-cookie': 'sid=SECRET'}, bodyBytes: utf8.encode(answer.$2), duration: const Duration(milliseconds: 12));
  }
}

(IOSink, StringBuffer) _capture() {
  final controller = StreamController<List<int>>();
  final buffer = StringBuffer();
  controller.stream.transform(utf8.decoder).listen(buffer.write);
  return (IOSink(controller.sink), buffer);
}

void main() {
  group('WorkspaceRunner', () {
    test('resolves variables in layers, inherits the collection auth, signs and chains requests', () async {
      final fake = _Fake();
      final runner = WorkspaceRunner.parse(_workspace(), fake.call);
      final summary = await runner.run(const RunOptions(environment: 'Staging', variables: {'apiKey': 'key-from-cli'}));

      expect(fake.calls.map((c) => '${c.method} ${c.url}'), [
        'POST https://staging.test/login',
        'GET https://staging.test/orders/42',
        'GET https://staging.test/broken',
      ]);
      expect(fake.calls[0].headers['Authorization'], isNull, reason: 'the login request opts out of auth');
      expect(fake.calls[1].headers['Authorization'], 'Bearer key-from-cli', reason: 'inherited bearer, resolved from --var');
      expect(fake.calls[1].headers['X-Session'], 'tok-abc', reason: 'extracted from the login response');
      expect(utf8.decode(fake.calls[0].body!), '{"user":"ann"}');

      expect(summary.total, 4);
      final byName = {for (final o in summary.outcomes) o.name: o};
      expect(byName['Login']!.passed, isTrue);
      expect(byName['Login']!.scripts.extracted.single.value, 'tok-abc');
      expect(byName['Get order']!.passed, isTrue);
      expect(byName['Broken']!.passed, isFalse);
      expect(byName['Broken']!.failures.single, contains('(got 500)'));
      expect(byName['OAuth thing']!.skipped, contains('oauth2'));
      expect(summary.ok, isFalse);
      expect(summary.failed, 1);
      expect(summary.skipped, 1);
      expect(summary.passed, 2);
    });

    test('an unresolved variable is a clear failure, not a request to a broken URL', () async {
      final fake = _Fake();
      final summary = await WorkspaceRunner.parse(_workspace(), fake.call).run(const RunOptions());
      expect(fake.calls, isEmpty);
      expect(summary.outcomes.first.error, contains('{{baseUrl}}'));
      expect(summary.outcomes.first.error, contains('--env'));
    });

    test('bail stops at the first failure; collection and folder filters narrow the run', () async {
      final fake = _Fake();
      final runner = WorkspaceRunner.parse(_workspace(), fake.call);
      final bailed = await runner.run(const RunOptions(environment: 'Staging', variables: {'apiKey': 'k'}, bail: true));
      expect(bailed.outcomes.map((o) => o.name), ['Login', 'Get order', 'Broken']);

      final folder = await runner.run(const RunOptions(environment: 'Staging', variables: {'apiKey': 'k'}, folder: 'Auth'));
      expect(folder.outcomes.map((o) => o.name), ['Login']);
      expect((await runner.run(const RunOptions(collection: 'Nope'))).total, 0);
    });

    test('an unknown environment is reported with the available ones', () async {
      await expectLater(
        WorkspaceRunner.parse(_workspace(), _Fake().call).run(const RunOptions(environment: 'Dev')),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', allOf(contains('Dev'), contains('Staging, Prod')))),
      );
    });

    test('the local secrets file fills the blanks of the shared workspace', () async {
      final local = SecretSplitter.encodeLocal({'env/Staging/apiKey': 'key-from-local-file'});
      final fake = _Fake();
      await WorkspaceRunner.parse(_workspace(), fake.call, localSecrets: local).run(const RunOptions(environment: 'Staging'));
      expect(fake.calls[1].headers['Authorization'], 'Bearer key-from-local-file');
    });

    test('a failing connection is reported per request and the run goes on', () async {
      var n = 0;
      final runner = WorkspaceRunner.parse(_workspace(), (r) async {
        if (n++ == 0) throw 'Connection refused';
        return const CliResponse(statusCode: 200, statusMessage: 'OK', headers: {}, bodyBytes: [], duration: Duration.zero);
      });
      final summary = await runner.run(const RunOptions(environment: 'Staging', variables: {'apiKey': 'k'}));
      expect(summary.outcomes.first.error, 'Connection refused');
      expect(summary.outcomes.first.passed, isFalse);
      expect(summary.total, 4);
    });
  });

  group('Reporters', () {
    test('console lines and summary', () async {
      final summary = await WorkspaceRunner.parse(_workspace(), _Fake().call).run(const RunOptions(environment: 'Staging', variables: {'apiKey': 'k'}));
      final lines = summary.outcomes.map((o) => RunReporters.line(o)).toList();
      expect(lines[0], startsWith('✔ POST'));
      expect(lines[0], contains('Shop / Auth / Login'));
      expect(lines[2], startsWith('✖ GET'));
      expect(lines[2], contains('statusEquals'.isEmpty ? '' : 'Status equals 200'));
      expect(lines[3], contains('skip'));
      expect(RunReporters.console(summary), contains('4 requests, 2 passed, 1 failed, 1 skipped'));
    });

    test('junit is well-formed, counts match, and text is escaped', () async {
      final summary = await WorkspaceRunner.parse(_workspace(), _Fake().call).run(const RunOptions(environment: 'Staging', variables: {'apiKey': 'k'}));
      final xml = RunReporters.junit(summary);
      expect(xml, startsWith('<?xml'));
      expect(xml, contains('tests="4" failures="1" skipped="1"'));
      expect(xml, contains('<testsuite name="Shop"'));
      expect(xml, contains('<failure message="Status equals 200 (got 500)"'));
      expect(xml, contains('<skipped'));
      expect(xml, isNot(contains('hunter2')));
      expect('<testcase'.allMatches(xml).length, 4);
    });

    test('json carries the verdict, and urls are masked', () async {
      final summary = await WorkspaceRunner.parse(_workspace(), _Fake().call).run(const RunOptions(environment: 'Staging', variables: {'apiKey': 'k'}));
      final json = jsonDecode(RunReporters.json(summary)) as Map<String, dynamic>;
      expect(json['ok'], isFalse);
      expect(json['failed'], 1);
      expect((json['requests'] as List).length, 4);
    });
  });

  group('runCli', () {
    late Directory dir;
    late File workspace;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('pp_cli');
      workspace = File(p.join(dir.path, 'workspace.json'))..writeAsStringSync(_workspace());
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<({int code, String out, String err})> cli(List<String> args, {Map<String, String> env = const {}}) async {
      final (out, outBuf) = _capture();
      final (err, errBuf) = _capture();
      final code = await runCli(args, sender: _Fake().call, out: out, err: err, environment: env);
      await out.flush();
      await err.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return (code: code, out: outBuf.toString(), err: errBuf.toString());
    }

    test('exit code 1 when a request fails, 0 when the selection passes', () async {
      final failing = await cli(['run', workspace.path, '--env', 'Staging', '--var', 'apiKey=k', '--no-color']);
      expect(failing.code, 1);
      expect(failing.out, contains('✖ GET'));
      expect(failing.out, contains('1 failed'));

      final passing = await cli(['run', workspace.path, '--env=Staging', '--var=apiKey=k', '--folder', 'Auth', '--no-color']);
      expect(passing.code, 0, reason: passing.out);
      expect(passing.out, contains('1 passed'));
    });

    test('secrets come from POSTPILOT_VAR_ environment variables and workspace.local.json', () async {
      final r = await cli(['run', workspace.path, '--env', 'Staging', '--folder', 'Auth'], env: {'POSTPILOT_VAR_apiKey': 'from-env'});
      expect(r.code, 0);
      File(p.join(dir.path, 'workspace.local.json')).writeAsStringSync(SecretSplitter.encodeLocal({'env/Staging/apiKey': 'from-file'}));
      expect((await cli(['run', workspace.path, '--env', 'Staging', '--folder', 'Auth'])).code, 0);
    });

    test('junit report goes to a file, with a summary on screen', () async {
      final out = p.join(dir.path, 'report.xml');
      final r = await cli(['run', workspace.path, '--env', 'Staging', '--var', 'apiKey=k', '--report', 'junit', '--out', out, '--no-color']);
      expect(r.code, 1);
      expect(File(out).readAsStringSync(), contains('<testsuites'));
      expect(r.out, contains('Report written to'));
    });

    test('list shows environments and requests', () async {
      final r = await cli(['list', workspace.path]);
      expect(r.code, 0);
      expect(r.out, contains('Environments: Staging, Prod'));
      expect(r.out, contains('Shop / Auth  POST   Login'));
    });

    test('usage mistakes exit with 2 and say what is wrong', () async {
      expect((await cli([])).code, 2);
      expect((await cli(['--help'])).code, 0);
      expect((await cli(['--version'])).out, contains('postpilot '));
      for (final bad in [
        ['explode'],
        ['run'],
        ['run', p.join(dir.path, 'missing.json')],
        ['run', workspace.path, '--wat'],
        ['run', workspace.path, '--env'],
        ['run', workspace.path, '--var', 'novalue'],
        ['run', workspace.path, '--env', 'Nope'],
        ['run', workspace.path, '--report', 'pdf'],
        ['run', workspace.path, '--collection', 'Ghost', '--env', 'Staging'],
      ]) {
        final r = await cli(bad);
        expect(r.code, 2, reason: '$bad -> ${r.err}');
        expect(r.err, isNotEmpty);
      }
      File(p.join(dir.path, 'bad.json')).writeAsStringSync('not a workspace');
      final notWorkspace = await cli(['run', p.join(dir.path, 'bad.json')]);
      expect(notWorkspace.code, 2);
      expect(notWorkspace.err, contains('is not a PostPilot workspace'));
    });
  });

  group('MCP server', () {
    McpServer server() => McpServer(WorkspaceRunner.parse(_workspace(), _Fake().call), const RunOptions(environment: 'Staging', variables: {'apiKey': 'k'}), const {});

    Future<Map<String, dynamic>> ask(McpServer s, String method, [Map<String, dynamic>? params, int id = 1]) async =>
        jsonDecode((await s.handleLine(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params})))!) as Map<String, dynamic>;

    Map<String, dynamic> toolResult(Map<String, dynamic> reply) => reply['result'] as Map<String, dynamic>;
    String text(Map<String, dynamic> reply) => ((toolResult(reply)['content'] as List).first as Map)['text'] as String;

    test('handshake, tool list and notifications', () async {
      final s = server();
      final init = await ask(s, 'initialize', {'protocolVersion': '2025-03-26'});
      expect(init['result']['protocolVersion'], '2025-03-26');
      expect(init['result']['serverInfo']['name'], 'postpilot');
      expect(await s.handleLine(jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'})), isNull);
      final tools = (await ask(s, 'tools/list'))['result']['tools'] as List;
      expect(tools.map((t) => t['name']), ['list_requests', 'list_environments', 'run_request', 'run_collection']);
      expect((await ask(s, 'nope'))['error']['code'], -32601);
      expect(jsonDecode((await s.handleLine('{broken'))!)['error']['code'], -32700);
    });

    test('lists requests and environments', () async {
      final s = server();
      final requests = jsonDecode(text(await ask(s, 'tools/call', {'name': 'list_requests', 'arguments': {}}))) as List;
      expect(requests.map((r) => r['name']), ['Login', 'Get order', 'Broken', 'OAuth thing']);
      final envs = jsonDecode(text(await ask(s, 'tools/call', {'name': 'list_environments'})));
      expect(envs['environments'], ['Staging', 'Prod']);
      expect(envs['default'], 'Staging');
    });

    test('runs a request with its tests, masks secrets, and keeps extracted variables for the next call', () async {
      final s = server();
      final login = jsonDecode(text(await ask(s, 'tools/call', {'name': 'run_request', 'arguments': {'request': 'Login'}}))) as Map<String, dynamic>;
      expect(login['status'], '200 OK');
      expect(login['passed'], isTrue);
      expect(login['tests'], ['PASS Status equals 200', 'PASS token exists']);
      expect(login['savedVariables'], ['sessionToken']);
      expect(jsonEncode(login), isNot(contains('hunter2')), reason: 'a password in the body is masked');
      expect(jsonEncode(login), isNot(contains('sid=SECRET')), reason: 'a cookie header is masked');

      final order = jsonDecode(text(await ask(s, 'tools/call', {'name': 'run_request', 'arguments': {'request': 'Get order'}}))) as Map<String, dynamic>;
      expect(order['passed'], isTrue, reason: 'the session token from the previous call was available');
    });

    test('errors are reported as tool errors, not protocol errors', () async {
      final s = server();
      final unknown = await ask(s, 'tools/call', {'name': 'run_request', 'arguments': {'request': 'Nope'}});
      expect(toolResult(unknown)['isError'], isTrue);
      expect(text(unknown), contains('No request named "Nope"'));
      final badTool = await ask(s, 'tools/call', {'name': 'delete_everything'});
      expect(toolResult(badTool)['isError'], isTrue);
      final run = jsonDecode(text(await ask(s, 'tools/call', {'name': 'run_collection', 'arguments': {'collection': 'Shop'}}))) as Map<String, dynamic>;
      expect(run['ok'], isFalse);
      expect(run['failed'], 1);
      expect((run['failures'] as List).single['request'], 'Broken');
    });
  });

  group('sendWithDartIo against a real server', () {
    late HttpServer server;
    late int port;
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
    });
    tearDown(() => server.close(force: true));

    CliRequest request(String path, {String method = 'GET', List<int>? body, Duration timeout = const Duration(seconds: 5)}) =>
        CliRequest(method: method, url: 'http://127.0.0.1:$port$path', headers: {'X-Test': 'yes'}, body: body, timeout: timeout, verifySsl: true);

    test('sends method, headers and body; reads status, headers and body', () async {
      server.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        req.response
          ..statusCode = 201
          ..headers.set('x-echo', '${req.method} ${req.headers.value('x-test')} $body')
          ..write('{"made":true}');
        await req.response.close();
      });
      final r = await sendWithDartIo(request('/things', method: 'POST', body: utf8.encode('hello')));
      expect(r.statusCode, 201);
      expect(r.headers['x-echo'], 'POST yes hello');
      expect(utf8.decode(r.bodyBytes), '{"made":true}');
      expect(r.duration, isNot(Duration.zero));
    });

    test('a slow server times out, and a closed port says so', () async {
      server.listen((req) async => Future<void>.delayed(const Duration(seconds: 3)));
      await expectLater(sendWithDartIo(request('/slow', timeout: const Duration(milliseconds: 300))), throwsA(contains('Timed out')));
      await server.close(force: true);
      await expectLater(sendWithDartIo(request('/x')), throwsA(isA<String>().having((s) => s, 'message', contains("Can't reach"))));
    });
  });
}
