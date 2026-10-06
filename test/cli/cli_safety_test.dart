import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/cli/cli_main.dart';
import 'package:postpilot/features/cli/dart_io_sender.dart';
import 'package:postpilot/features/cli/mcp_server.dart';
import 'package:postpilot/features/cli/production_lock.dart';
import 'package:postpilot/features/cli/reporters.dart';
import 'package:postpilot/features/cli/workspace_runner.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/safety/domain/services/production_detector.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';

// ---------------------------------------------------------------- fixtures

BackupRequest _req(
  String name,
  String url, {
  HttpMethod method = HttpMethod.get,
  RequestAuth auth = const RequestAuth(type: AuthType.inherit),
  RequestBody body = RequestBody.empty,
  List<AssertionEntity> assertions = const [],
}) =>
    BackupRequest(
      request: ApiRequestEntity(id: 0, collectionId: 0, folderId: null, name: name, method: method, url: url, headers: const [], queryParams: const [], body: body, auth: auth),
      scripts: assertions.isEmpty
          ? null
          : RequestScriptsEntity(requestId: 0, assertionsJson: ScriptsJsonCodec.encodeAssertions(assertions), extractorsJson: ScriptsJsonCodec.encodeExtractors(const [])),
    );

EnvironmentVariableEntity _var(String key, String value) => EnvironmentVariableEntity(id: 0, environmentId: 0, key: key, value: value, isSecret: false, enabled: true);

CollectionVariableEntity _cvar(String key, String value) => CollectionVariableEntity(id: 0, collectionId: 0, key: key, value: value, enabled: true);

const _bearer = RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}');
const _json = RequestBody(type: BodyType.raw, rawText: '{"sku": "a"}');

RequestBody _graphql(String query) => RequestBody(type: BodyType.graphql, graphqlQuery: query);

/// Three environments that point at the live server (`Production`, a `Dev`
/// that was copied from it, and `customer-a`), one that does not, and `Chain`,
/// whose baseUrl is built from two other variables.
String _shop() => BackupCodec.encode(BackupSnapshot(
      exportedAt: DateTime.utc(2026),
      environments: [
        BackupEnvironment(name: 'Production', variables: [_var('baseUrl', 'https://api.shop.test'), _var('token', 'tok-secret-123')]),
        BackupEnvironment(name: 'Staging', variables: [_var('baseUrl', 'https://staging.shop.test'), _var('token', 'tok-secret-123')]),
        BackupEnvironment(name: 'Dev', variables: [_var('baseUrl', 'https://api.shop.test'), _var('token', 'tok-secret-123')]),
        BackupEnvironment(name: 'customer-a', variables: [_var('baseUrl', 'https://a.shop.test'), _var('token', 'tok-secret-123')]),
        BackupEnvironment(name: 'Chain', variables: [_var('scheme', 'https'), _var('host', 'chain.shop.test'), _var('baseUrl', '{{scheme}}://{{host}}'), _var('token', 'tok-secret-123')]),
      ],
      collections: [
        BackupCollection(
          name: 'Reads',
          auth: _bearer,
          variables: [_cvar('orderId', '1'), _cvar('path', '/orders')],
          requests: [
            _req('List orders', '{{baseUrl}}/orders'),
            _req('Get order', '{{baseUrl}}/orders/{{orderId}}'),
            _req('Raw path', '{{baseUrl}}{{path}}'),
            _req('Odoo read', '{{baseUrl}}/json/2/sale.order/search_read', method: HttpMethod.post, body: const RequestBody(type: BodyType.raw, rawText: '{"domain": []}')),
            _req('GraphQL query', '{{baseUrl}}/graphql', method: HttpMethod.post, body: _graphql('query { orders { id } }')),
          ],
        ),
        BackupCollection(
          name: 'Writes',
          auth: _bearer,
          requests: [
            _req('Create order', '{{baseUrl}}/orders', method: HttpMethod.post, body: _json),
            _req('Delete order', '{{baseUrl}}/orders/1', method: HttpMethod.delete),
            _req('Odoo unlink', '{{baseUrl}}/json/2/sale.order/unlink', method: HttpMethod.post, body: const RequestBody(type: BodyType.raw, rawText: '{"ids": [1]}')),
            _req('GraphQL delete', '{{baseUrl}}/graphql', method: HttpMethod.post, body: _graphql('mutation { deleteOrder(id: 1) { id } }')),
          ],
        ),
      ],
    ));

/// Answers 200 to everything and remembers what it was asked.
final class _Fake {
  final calls = <CliRequest>[];
  Future<CliResponse> call(CliRequest r) async {
    calls.add(r);
    return CliResponse(
      statusCode: 200,
      statusMessage: 'OK',
      headers: const {'content-type': 'application/json'},
      bodyBytes: utf8.encode('{"ok":true}'),
      duration: const Duration(milliseconds: 5),
    );
  }

  List<String> get urls => [for (final c in calls) '${c.method} ${c.url}'];
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

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pp_cli_safety');
    workspace = File(p.join(dir.path, 'workspace.json'))..writeAsStringSync(_shop());
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<({int code, String out, String err, _Fake fake})> cli(List<String> args, {String? json}) async {
    if (json != null) workspace.writeAsStringSync(json);
    final fake = _Fake();
    final (out, outBuf) = _capture();
    final (err, errBuf) = _capture();
    final code = await runCli(args, sender: fake.call, out: out, err: err, environment: const {});
    await out.flush();
    await err.flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return (code: code, out: outBuf.toString(), err: errBuf.toString(), fake: fake);
  }

  // ----------------------------------------------------- 1. production lock

  group('production lock: command line', () {
    test('refuses a run that would change data in Production, lists the requests, sends nothing and exits 2', () async {
      final r = await cli(['run', workspace.path, '--env', 'Production', '--no-color']);
      expect(r.code, 2);
      expect(r.fake.calls, isEmpty);
      expect(r.out, isEmpty);
      expect(r.err, contains('Production lock: 4 selected requests would change data in production'));
      expect(r.err, contains('POST   Writes / Create order'));
      expect(r.err, contains('DELETE Writes / Delete order (deletes data)'));
      expect(r.err, contains('POST   Writes / Odoo unlink (deletes data)'));
      expect(r.err, contains('POST   Writes / GraphQL delete (deletes data)'));
      expect(r.err, contains('environment "Production" looks like production'));
      expect(r.err, contains('--allow-production'));
      expect(r.err, isNot(contains('Reads /')), reason: 'reads over POST (Odoo search_read, a GraphQL query) are not blocked');
    });

    test('a read-only selection runs in Production, reads over POST included', () async {
      final r = await cli(['run', workspace.path, '--env', 'Production', '--collection', 'Reads', '--no-color']);
      expect(r.code, 0, reason: r.err + r.out);
      expect(r.fake.urls, [
        'GET https://api.shop.test/orders',
        'GET https://api.shop.test/orders/1',
        'GET https://api.shop.test/orders',
        'POST https://api.shop.test/json/2/sale.order/search_read',
        'POST https://api.shop.test/graphql',
      ]);
      expect(r.fake.calls.first.headers['Authorization'], 'Bearer tok-secret-123');
    });

    test('--allow-production lets everything through', () async {
      final r = await cli(['run', workspace.path, '--env', 'Production', '--allow-production', '--no-color']);
      expect(r.code, 0, reason: r.err + r.out);
      expect(r.fake.calls, hasLength(9));
    });

    test('a Staging environment is not locked', () async {
      final r = await cli(['run', workspace.path, '--env', 'Staging', '--no-color']);
      expect(r.code, 0, reason: r.err + r.out);
      expect(r.fake.calls, hasLength(9));
    });

    test('--production-host protects a Dev environment that points at the live host, subdomains and case included', () async {
      expect((await cli(['run', workspace.path, '--env', 'Dev'])).code, 0, reason: 'without the host, Dev is just Dev');
      for (final host in ['api.shop.test', 'API.SHOP.TEST', 'shop.test', '*.shop.test', 'https://api.shop.test/v1']) {
        final r = await cli(['run', workspace.path, '--env', 'Dev', '--production-host', host]);
        expect(r.code, 2, reason: host);
        expect(r.fake.calls, isEmpty, reason: host);
        expect(r.err, contains('api.shop.test is a production host'), reason: host);
      }
      final equalsForm = await cli(['run', workspace.path, '--env', 'Dev', '--production-host=api.shop.test']);
      expect(equalsForm.code, 2);
      final other = await cli(['run', workspace.path, '--env', 'Staging', '--production-host', 'api.shop.test']);
      expect(other.code, 0, reason: 'Staging goes to staging.shop.test');
      final port = await cli(['run', workspace.path, '--env', 'Dev', '--production-host', 'api.shop.test:8443']);
      expect(port.code, 0, reason: 'https on 443 is not port 8443');
    });

    test('--production-word marks a custom environment name, and is repeatable', () async {
      expect((await cli(['run', workspace.path, '--env', 'customer-a'])).code, 0);
      final r = await cli(['run', workspace.path, '--env', 'customer-a', '--production-word', 'eu', '--production-word', 'customer']);
      expect(r.code, 2);
      expect(r.err, contains('environment "customer-a" looks like production'));
    });

    test('the lock also covers the json report mode, and list is unaffected', () async {
      final r = await cli(['run', workspace.path, '--env', 'Production', '--report', 'json']);
      expect(r.code, 2);
      expect(r.out, isEmpty);
      expect((await cli(['list', workspace.path])).code, 0);
    });

    test('--help documents the lock flags', () async {
      final r = await cli(['--help']);
      expect(r.out, allOf(contains('--allow-production'), contains('--production-host'), contains('--production-word'), contains('--fail-on-skip')));
    });
  });

  group('production lock: runner', () {
    test('refuses at send time too, and says why per request', () async {
      final fake = _Fake();
      final runner = WorkspaceRunner.parse(_shop(), fake.call);
      final summary = await runner.run(const RunOptions(environment: 'Production', collection: 'Writes'));
      expect(fake.calls, isEmpty);
      expect(summary.failed, 4);
      expect(summary.ok, isFalse);
      for (final o in summary.outcomes) {
        expect(o.blocked, isNotNull, reason: o.name);
        expect(o.error, contains('Refused by the production lock'));
        expect(o.error, contains('--allow-production'));
        expect(o.passed, isFalse);
      }

      final allowed = await runner.run(const RunOptions(environment: 'Production', collection: 'Writes', production: ProductionLock(allow: true)));
      expect(fake.calls, hasLength(4));
      expect(allowed.ok, isTrue);
    });

    test('productionBlocks classifies by intent and skips what is never sent', () async {
      final runner = WorkspaceRunner.parse(_shop(), _Fake().call);
      final blocks = runner.productionBlocks(const RunOptions(environment: 'Production'));
      expect(blocks.map((b) => b.name), ['Create order', 'Delete order', 'Odoo unlink', 'GraphQL delete']);
      expect(blocks.map((b) => b.effect), [RequestEffect.write, RequestEffect.destructive, RequestEffect.destructive, RequestEffect.destructive]);
      expect(runner.productionBlocks(const RunOptions(environment: 'Production', production: ProductionLock(allow: true))), isEmpty);
      expect(runner.productionBlocks(const RunOptions(environment: 'Staging')), isEmpty);
      expect(runner.productionBlocks(const RunOptions(environment: 'Production', collection: 'Reads')), isEmpty);
      expect(() => runner.productionBlocks(const RunOptions(environment: 'Nope')), throwsA(isA<ArgumentError>()));
    });
  });

  group('production lock: MCP server', () {
    McpServer server(_Fake fake, {RunOptions options = const RunOptions(environment: 'Staging')}) =>
        McpServer(WorkspaceRunner.parse(_shop(), fake.call), options, const {});

    Future<Map<String, dynamic>> call(McpServer s, String tool, Map<String, dynamic> args) async =>
        jsonDecode((await s.handleLine(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call', 'params': {'name': tool, 'arguments': args}})))!) as Map<String, dynamic>;

    bool isError(Map<String, dynamic> reply) => (reply['result'] as Map)['isError'] == true;
    String text(Map<String, dynamic> reply) => (((reply['result'] as Map)['content'] as List).first as Map)['text'] as String;

    test('refuses a data-changing request in Production and tells the agent why, and that it cannot lift the lock', () async {
      final fake = _Fake();
      final s = server(fake);
      for (final name in ['Create order', 'Delete order', 'Odoo unlink', 'GraphQL delete']) {
        final reply = await call(s, 'run_request', {'request': name, 'environment': 'Production'});
        expect(isError(reply), isTrue, reason: name);
        expect(text(reply), allOf(contains('Refused by the production lock'), contains(name), contains('--allow-production'), contains('Only the person who starts PostPilot')), reason: name);
      }
      expect(fake.calls, isEmpty);
    });

    test('reads still run in Production, GET and reads over POST alike', () async {
      final fake = _Fake();
      final s = server(fake);
      for (final name in ['List orders', 'Odoo read', 'GraphQL query']) {
        final reply = await call(s, 'run_request', {'request': name, 'environment': 'Production'});
        expect(isError(reply), isFalse, reason: '$name: ${text(reply)}');
      }
      expect(fake.calls, hasLength(3));
    });

    test('no tool argument lifts the lock', () async {
      final fake = _Fake();
      final s = server(fake);
      final reply = await call(s, 'run_request', {
        'request': 'Create order',
        'environment': 'Production',
        'allowProduction': true,
        'allow_production': true,
        'allow-production': true,
        'variables': {'allowProduction': 'true'},
      });
      expect(isError(reply), isTrue);
      expect(fake.calls, isEmpty);
    });

    test('the operator can allow it with --allow-production, which then runs the request', () async {
      final fake = _Fake();
      final s = server(fake, options: const RunOptions(environment: 'Production', production: ProductionLock(allow: true)));
      final reply = await call(s, 'run_request', {'request': 'Delete order'});
      expect(isError(reply), isFalse, reason: text(reply));
      expect(fake.urls, ['DELETE https://api.shop.test/orders/1']);
    });

    test('a production host from the operator protects any environment', () async {
      final fake = _Fake();
      final s = server(fake, options: const RunOptions(environment: 'Dev', production: ProductionLock(hosts: ['api.shop.test'])));
      final reply = await call(s, 'run_request', {'request': 'Create order'});
      expect(isError(reply), isTrue);
      expect(text(reply), contains('api.shop.test is a production host'));
      expect(fake.calls, isEmpty);
      expect(isError(await call(s, 'run_request', {'request': 'List orders'})), isFalse);
    });

    test('run_collection refuses the whole run when any selected request changes data, and sends nothing', () async {
      final fake = _Fake();
      final s = server(fake);
      final reply = await call(s, 'run_collection', {'collection': 'Writes', 'environment': 'Production'});
      expect(isError(reply), isTrue);
      expect(text(reply), allOf(contains('Production lock: 4 selected requests'), contains('Writes / Create order'), contains('--allow-production')));
      expect(fake.calls, isEmpty);

      final reads = await call(s, 'run_collection', {'collection': 'Reads', 'environment': 'Production'});
      expect(isError(reads), isFalse, reason: text(reads));
      expect(jsonDecode(text(reads))['ok'], isTrue);
      expect(fake.calls, hasLength(5));
    });

    test('list_environments tells the agent which environments are locked and whether the lock is on', () async {
      final s = server(_Fake());
      final envs = jsonDecode(text(await call(s, 'list_environments', {}))) as Map<String, dynamic>;
      expect(envs['productionEnvironments'], ['Production']);
      expect(envs['productionLock'], startsWith('on'));
      final open = server(_Fake(), options: const RunOptions(production: ProductionLock(allow: true)));
      expect(jsonDecode(text(await call(open, 'list_environments', {})))['productionLock'], startsWith('off'));
    });

    test('the tool descriptions state the rules', () async {
      final tools = jsonDecode((await server(_Fake()).handleLine(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'})))!)['result']['tools'] as List;
      final run = tools.firstWhere((t) => t['name'] == 'run_request')['description'] as String;
      expect(run, allOf(contains('Production lock'), contains('--allow-production'), contains('scheme, host or port')));
      expect(tools.firstWhere((t) => t['name'] == 'run_collection')['description'], contains('refused'));
    });
  });

  // -------------------------------------------- 2. agent variables vs host

  group('agent variables cannot redirect a request', () {
    McpServer server(_Fake fake, {RunOptions options = const RunOptions(environment: 'Staging')}) =>
        McpServer(WorkspaceRunner.parse(_shop(), fake.call), options, const {});

    Future<Map<String, dynamic>> call(McpServer s, Map<String, dynamic> args) async => jsonDecode(
          (await s.handleLine(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call', 'params': {'name': 'run_request', 'arguments': args}})))!,
        ) as Map<String, dynamic>;

    bool isError(Map<String, dynamic> reply) => (reply['result'] as Map)['isError'] == true;
    String text(Map<String, dynamic> reply) => (((reply['result'] as Map)['content'] as List).first as Map)['text'] as String;

    test('overriding baseUrl is refused, nothing is sent, and the reply states the rule', () async {
      final fake = _Fake();
      final reply = await call(server(fake), {'request': 'List orders', 'variables': {'baseUrl': 'https://evil.example'}});
      expect(isError(reply), isTrue);
      expect(text(reply), allOf(contains('Refused'), contains('baseUrl'), contains('https://staging.shop.test'), contains('https://evil.example'), contains('credentials cannot be redirected')));
      expect(fake.calls, isEmpty, reason: 'the Bearer token never left');
    });

    test('a variable that only builds part of the host is refused too, through a chain of variables', () async {
      final fake = _Fake();
      final s = server(fake, options: const RunOptions(environment: 'Chain'));
      expect(isError(await call(s, {'request': 'List orders', 'variables': {'host': 'evil.example'}})), isTrue);
      expect(isError(await call(s, {'request': 'List orders', 'variables': {'scheme': 'http'}})), isTrue, reason: 'the scheme is part of the origin');
      expect(fake.calls, isEmpty);
      expect(isError(await call(s, {'request': 'List orders'})), isFalse);
      expect(fake.urls, ['GET https://chain.shop.test/orders']);
    });

    test('text that bends the host out of a path variable is refused', () async {
      final fake = _Fake();
      final s = server(fake);
      for (final path in ['.evil.example/x', '@evil.example/x', ':9999@evil.example', r'\@evil.example/x']) {
        final reply = await call(s, {'request': 'Raw path', 'variables': {'path': path}});
        expect(isError(reply), isTrue, reason: path);
      }
      expect(fake.calls, isEmpty);
    });

    test('variables that stay in the path or the query are fine, and apply to that call only', () async {
      final fake = _Fake();
      final s = server(fake);
      expect(isError(await call(s, {'request': 'Get order', 'variables': {'orderId': '42'}})), isFalse);
      expect(isError(await call(s, {'request': 'Get order', 'variables': {'orderId': '43'}})), isFalse);
      expect(isError(await call(s, {'request': 'Get order'})), isFalse);
      expect(isError(await call(s, {'request': 'Raw path', 'variables': {'path': '/orders?page=2'}})), isFalse);
      expect(fake.urls, [
        'GET https://staging.shop.test/orders/42',
        'GET https://staging.shop.test/orders/43',
        'GET https://staging.shop.test/orders/1',
        'GET https://staging.shop.test/orders?page=2',
      ]);
    });

    test('passing the same host the workspace already uses is harmless', () async {
      final fake = _Fake();
      final reply = await call(server(fake), {'request': 'List orders', 'variables': {'baseUrl': 'https://Staging.Shop.test'}});
      expect(isError(reply), isFalse, reason: text(reply));
      expect(fake.calls, hasLength(1));
    });

    test('a host that only an agent could supply is refused, with the way out', () async {
      final fake = _Fake();
      final reply = await call(server(fake, options: const RunOptions()), {'request': 'List orders', 'variables': {'baseUrl': 'https://evil.example'}});
      expect(isError(reply), isTrue);
      expect(text(reply), allOf(contains('{{baseUrl}}'), contains('does not define'), contains('--var baseUrl=')));
      expect(fake.calls, isEmpty);
    });

    test('--var of the operator may set the host, the agent may not', () async {
      final fake = _Fake();
      final s = server(fake, options: const RunOptions(variables: {'baseUrl': 'https://ops.shop.test', 'token': 't'}));
      expect(isError(await call(s, {'request': 'Get order', 'variables': {'orderId': '5'}})), isFalse);
      expect(fake.urls, ['GET https://ops.shop.test/orders/5']);
      expect(isError(await call(s, {'request': 'Get order', 'variables': {'baseUrl': 'https://evil.example'}})), isTrue);
      expect(fake.calls, hasLength(1));
    });

    test('a value may not point at other variables, so a secret cannot be pulled into a request', () async {
      final fake = _Fake();
      final reply = await call(server(fake), {'request': 'Get order', 'variables': {'orderId': '{{token}}'}});
      expect(isError(reply), isTrue);
      expect(text(reply), contains('cannot contain {{'));
      expect(fake.calls, isEmpty);
      expect(isError(await call(server(fake), {'request': 'Get order', 'variables': ['x']})), isTrue);
    });

    test('the runner enforces the same rule without the MCP layer', () async {
      final fake = _Fake();
      final runner = WorkspaceRunner.parse(_shop(), fake.call);
      final summary = await runner.run(const RunOptions(environment: 'Staging', collection: 'Reads', agentVariables: {'baseUrl': 'https://evil.example', 'orderId': '9'}));
      expect(fake.calls, isEmpty);
      expect(summary.outcomes.every((o) => o.blocked != null), isTrue);
    });
  });

  // ----------------------------------------------------------- 3. masking

  group('everything an agent or a log reads is masked', () {
    const secretKey = 'sk_live_abcdefghijklmnop1234';

    WorkspaceRunner leaky(CliSend send) => WorkspaceRunner.parse(
          BackupCodec.encode(BackupSnapshot(
            exportedAt: DateTime.utc(2026),
            environments: [BackupEnvironment(name: 'Staging', variables: [_var('baseUrl', 'https://staging.shop.test')])],
            collections: [
              BackupCollection(name: 'Leaky', requests: [
                _req('Token check', '{{baseUrl}}/me', assertions: [
                  AssertionEntity(type: AssertionType.jsonPathEquals, path: 'data.access_token', expected: 'abc'),
                  AssertionEntity(type: AssertionType.jsonPathEquals, path: 'data.note', expected: 'x'),
                  AssertionEntity(type: AssertionType.jsonPathEquals, path: 'data.profile', expected: '{}'),
                  AssertionEntity(type: AssertionType.headerEquals, path: 'Set-Cookie', expected: 'x'),
                  AssertionEntity(type: AssertionType.jsonPathExists, path: 'data.missing'),
                ]),
              ]),
            ],
          )),
          send,
        );

    Future<CliResponse> leakyServer(CliRequest r) async => CliResponse(
          statusCode: 200,
          statusMessage: 'OK',
          headers: const {'set-cookie': 'sid=TOPSECRETCOOKIE', 'content-type': 'application/json'},
          bodyBytes: utf8.encode('{"data":{"access_token":"$secretKey","note":"hello world","profile":{"password":"hunter2","name":"Ann"}}}'),
          duration: Duration.zero,
        );

    void expectNoSecrets(String where, String output) {
      for (final secret in [secretKey, 'hunter2', 'TOPSECRETCOOKIE']) {
        expect(output, isNot(contains(secret)), reason: '$where leaked $secret');
      }
    }

    test('the value a failed check saw is masked in failures, the console, JUnit and the JSON report, and plain values still show', () async {
      final summary = await leaky(leakyServer).run(const RunOptions(environment: 'Staging'));
      final failures = summary.outcomes.single.failures;
      expect(failures, hasLength(5));
      expect(failures[0], 'data.access_token equals abc (got ••••••)');
      expect(failures[1], 'data.note equals x (got hello world)');
      expect(failures[2], 'data.profile equals {} (got {"password":"••••••","name":"Ann"})');
      expect(failures[3], 'Header Set-Cookie equals x (got ••••••)');
      expect(failures[4], 'data.missing exists (got Missing)');
      expectNoSecrets('failures', failures.join('\n'));
      expectNoSecrets('console line', RunReporters.line(summary.outcomes.single));
      expectNoSecrets('console', RunReporters.console(summary));
      expectNoSecrets('junit', RunReporters.junit(summary));
      final json = RunReporters.json(summary);
      expectNoSecrets('json report', json);
      final assertions = (jsonDecode(json)['requests'][0]['assertions'] as List).cast<Map<String, dynamic>>();
      expect(assertions.map((a) => a['actual']), ['••••••', 'hello world', '{"password":"••••••","name":"Ann"}', '••••••', 'Missing']);
      expect(assertions.map((a) => a['name']), ['data.access_token equals abc', 'data.note equals x', 'data.profile equals {}', 'Header Set-Cookie equals x', 'data.missing exists']);
    });

    test('the MCP reply masks the checks, the failures and the body', () async {
      final s = McpServer(leaky(leakyServer), const RunOptions(environment: 'Staging'), const {});
      final reply = (await s.handleLine(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call', 'params': {'name': 'run_request', 'arguments': {'request': 'Token check'}}})))!;
      expectNoSecrets('mcp', reply);
      expect(reply, contains('data.note equals x (got hello world)'));
    });

    test('an error that quotes the URL does not carry the token in it', () async {
      for (final thrown in <Object>[
        'Could not reach https://staging.shop.test/me?token=abc123secret&page=2',
        HttpException('Connection closed', uri: Uri.parse('https://staging.shop.test/me?token=abc123secret')),
        const FormatException('Bad host in https://u:pw0rdsecret@staging.shop.test/me'),
      ]) {
        final summary = await leaky((r) async => throw thrown).run(const RunOptions(environment: 'Staging'));
        final o = summary.outcomes.single;
        for (final text in [o.error!, o.failures.join('\n'), RunReporters.line(o), RunReporters.junit(summary), RunReporters.json(summary)]) {
          expect(text, isNot(contains('abc123secret')), reason: '$thrown');
          expect(text, isNot(contains('pw0rdsecret')), reason: '$thrown');
        }
        expect(o.error, contains('••••••'), reason: '$thrown');
      }
    });

    test('an MCP tool error is masked as well', () async {
      final s = McpServer(leaky((r) async => throw 'failed: https://staging.shop.test/me?api_key=zzz999secret'), const RunOptions(environment: 'Staging'), const {});
      final reply = (await s.handleLine(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call', 'params': {'name': 'run_request', 'arguments': {'request': 'Token check'}}})))!;
      expect(reply, isNot(contains('zzz999secret')));
      expect(reply, contains('••••••'));
    });

    group('the dart:io sender', () {
      test('a response cut off mid-body (HttpException) is reported without the URL', () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close());
        // Promises 100 bytes, sends 7 and hangs up: the client's exception quotes the request URL.
        server.listen((socket) {
          socket.write('HTTP/1.1 200 OK\r\ncontent-length: 100\r\n\r\npartial');
          socket.close();
        });
        final request = CliRequest(
          method: 'GET',
          url: 'http://127.0.0.1:${server.port}/me?token=abc123secret',
          headers: const {},
          body: null,
          timeout: const Duration(seconds: 5),
          verifySsl: true,
        );
        Object? thrown;
        try {
          await sendWithDartIo(request);
        } catch (e) {
          thrown = e;
        }
        expect(thrown, isA<String>(), reason: 'every failure is reported as text, never as a raw exception object');
        expect(thrown as String, startsWith('The HTTP exchange failed'));
        expect(thrown, isNot(contains('abc123secret')));
        expect(thrown, isNot(contains('token=')));
      });

      test('a URL that cannot be parsed (FormatException) is reported without the URL', () async {
        final request = CliRequest(
          method: 'GET',
          url: 'http://127.0.0.1:notaport/me?token=abc123secret',
          headers: const {},
          body: null,
          timeout: const Duration(seconds: 5),
          verifySsl: true,
        );
        Object? thrown;
        try {
          await sendWithDartIo(request);
        } catch (e) {
          thrown = e;
        }
        expect(thrown, isA<String>());
        expect(thrown as String, allOf(contains('not valid'), isNot(contains('abc123secret'))));
      });
    });
  });

  // ------------------------------------------------- 4. skipped requests

  group('skipped requests do not count as success', () {
    String oauthOnly() => BackupCodec.encode(BackupSnapshot(
          exportedAt: DateTime.utc(2026),
          environments: [BackupEnvironment(name: 'Staging', variables: [_var('baseUrl', 'https://staging.shop.test')])],
          collections: [
            BackupCollection(name: 'Auth', requests: [
              _req('Token A', '{{baseUrl}}/a', auth: const RequestAuth(type: AuthType.oauth2)),
              _req('Token B', '{{baseUrl}}/b', auth: const RequestAuth(type: AuthType.oauth2)),
            ]),
          ],
        ));

    String mixed() => BackupCodec.encode(BackupSnapshot(
          exportedAt: DateTime.utc(2026),
          environments: [BackupEnvironment(name: 'Staging', variables: [_var('baseUrl', 'https://staging.shop.test')])],
          collections: [
            BackupCollection(name: 'Auth', requests: [
              _req('Ping', '{{baseUrl}}/ping'),
              _req('Token', '{{baseUrl}}/token', auth: const RequestAuth(type: AuthType.oauth2)),
            ]),
          ],
        ));

    test('a run in which everything was skipped exits 1, says nothing was verified, and lists each skip with its reason', () async {
      final r = await cli(['run', workspace.path, '--env', 'Staging', '--no-color'], json: oauthOnly());
      expect(r.code, 1);
      expect(r.fake.calls, isEmpty);
      expect(r.err, contains('Nothing was verified: all 2 selected requests were skipped'));
      expect(r.out, contains('2 requests, 0 passed, 0 failed, 2 skipped'));
      expect(r.out, contains('Skipped, not sent:'));
      expect(r.out, contains('GET    Auth / Token A: oauth2 auth needs the app'));
      expect(r.out, contains('GET    Auth / Token B: oauth2 auth needs the app'));
    });

    test('a passing request next to a skipped one is a pass, unless --fail-on-skip', () async {
      final ok = await cli(['run', workspace.path, '--env', 'Staging', '--no-color'], json: mixed());
      expect(ok.code, 0, reason: ok.err + ok.out);
      expect(ok.out, contains('1 passed'));
      expect(ok.out, contains('Skipped, not sent:'));

      final strict = await cli(['run', workspace.path, '--env', 'Staging', '--no-color', '--fail-on-skip']);
      expect(strict.code, 1);
      expect(strict.err, contains('--fail-on-skip: 1 request was skipped'));
      expect(strict.out, contains('--fail-on-skip: this fails the run'));
      expect(strict.fake.calls, hasLength(1), reason: 'the other request still ran');
    });

    test('the JSON report agrees: ok is false for an all-skipped run and with --fail-on-skip', () async {
      final all = await cli(['run', workspace.path, '--env', 'Staging', '--report', 'json'], json: oauthOnly());
      final allJson = jsonDecode(all.out) as Map<String, dynamic>;
      expect(all.code, 1);
      expect(allJson['ok'], isFalse);
      expect(allJson['skipped'], 2);
      expect((allJson['requests'] as List).first['skipped'], contains('oauth2'));

      final strict = await cli(['run', workspace.path, '--env', 'Staging', '--report', 'json', '--fail-on-skip'], json: mixed());
      expect(jsonDecode(strict.out)['ok'], isFalse);
      final lenient = await cli(['run', workspace.path, '--env', 'Staging', '--report', 'json']);
      expect(jsonDecode(lenient.out)['ok'], isTrue);
    });

    test('RunSummary.ok needs something that passed', () {
      RequestOutcome passed() => const RequestOutcome(collection: 'c', folder: '', name: 'p', method: 'GET', url: 'u', status: 200);
      RequestOutcome skipped() => const RequestOutcome(collection: 'c', folder: '', name: 's', method: 'GET', url: 'u', skipped: 'why');
      RequestOutcome failed() => const RequestOutcome(collection: 'c', folder: '', name: 'f', method: 'GET', url: 'u', status: 500);
      expect(RunSummary([skipped(), skipped()], Duration.zero).ok, isFalse);
      expect(RunSummary([skipped(), skipped()], Duration.zero).allSkipped, isTrue);
      expect(const RunSummary([], Duration.zero).ok, isFalse);
      expect(RunSummary([passed(), skipped()], Duration.zero).ok, isTrue);
      expect(RunSummary([passed(), skipped()], Duration.zero, failOnSkip: true).ok, isFalse);
      expect(RunSummary([passed()], Duration.zero, failOnSkip: true).ok, isTrue);
      expect(RunSummary([passed(), failed()], Duration.zero).ok, isFalse);
      expect(RunSummary([passed(), skipped()], Duration.zero).passed, 1);
    });

    test('the MCP run_collection result is not ok when everything was skipped, and names the skipped requests', () async {
      final s = McpServer(WorkspaceRunner.parse(oauthOnly(), _Fake().call), const RunOptions(environment: 'Staging'), const {});
      final reply = jsonDecode((await s.handleLine(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call', 'params': {'name': 'run_collection', 'arguments': {'collection': 'Auth'}}})))!);
      final result = jsonDecode(reply['result']['content'][0]['text']) as Map<String, dynamic>;
      expect(result['ok'], isFalse);
      expect(result['skipped'], 2);
      expect(result['warning'], contains('skipped'));
      expect((result['skippedRequests'] as List).map((e) => e['request']), ['Token A', 'Token B']);
      expect((result['skippedRequests'] as List).first['reason'], contains('oauth2'));
    });
  });

  // ------------------------------------------------------ 7. digest auth

  group('digest auth', () {
    // Expected values come from Python's hashlib, with RFC 2617 section 3.2.2.1:
    //   HA1 = md5("ann:shop-realm:s3cret pass"), HA2 = md5("GET:/digest/orders?id=7"),
    //   no qop:  response = md5(HA1:nonce:HA2)           -> c24be1d7fca062ecf922b8be1432dc36 for nonce abc123nonce
    // The same formula with qop reproduces the RFC's published example 6629fae49393a05397450978507c4ef1.
    String digestWorkspace() => BackupCodec.encode(BackupSnapshot(
          exportedAt: DateTime.utc(2026),
          environments: [BackupEnvironment(name: 'Staging', variables: [_var('baseUrl', 'https://staging.shop.test'), _var('pw', 's3cret pass')])],
          collections: [
            BackupCollection(
              name: 'Camera',
              auth: const RequestAuth(type: AuthType.digest, basicUsername: 'ann', basicPassword: '{{pw}}'),
              requests: [_req('Digest orders', '{{baseUrl}}/digest/orders?id=7')],
            ),
          ],
        ));

    CliResponse answer(int status, {Map<String, String> headers = const {}}) =>
        CliResponse(statusCode: status, statusMessage: status == 200 ? 'OK' : 'Unauthorized', headers: headers, bodyBytes: utf8.encode('{}'), duration: Duration.zero);

    String? header(CliRequest r, String name) => r.headers.entries.where((e) => e.key.toLowerCase() == name.toLowerCase()).firstOrNull?.value;

    test('is no longer skipped: the 401 challenge is answered and the request sent again', () async {
      final calls = <CliRequest>[];
      final runner = WorkspaceRunner.parse(digestWorkspace(), (r) async {
        calls.add(r);
        return header(r, 'Authorization') == null
            ? answer(401, headers: {'www-authenticate': 'Digest realm="shop-realm", nonce="abc123nonce"'})
            : answer(200);
      });
      final summary = await runner.run(const RunOptions(environment: 'Staging'));
      final o = summary.outcomes.single;
      expect(o.skipped, isNull);
      expect(o.passed, isTrue, reason: '${o.failures}');
      expect(o.status, 200);
      expect(summary.ok, isTrue);

      expect(calls, hasLength(2));
      expect(header(calls[0], 'Authorization'), isNull);
      final auth = header(calls[1], 'Authorization')!;
      expect(auth, startsWith('Digest '));
      expect(auth, contains('username="ann"'));
      expect(auth, contains('realm="shop-realm"'));
      expect(auth, contains('nonce="abc123nonce"'));
      expect(auth, contains('uri="/digest/orders?id=7"'));
      expect(auth, contains('response="c24be1d7fca062ecf922b8be1432dc36"'));
      expect(calls[1].url, calls[0].url);
    });

    test('with qop=auth the response covers the client nonce the header carries', () async {
      final calls = <CliRequest>[];
      final runner = WorkspaceRunner.parse(digestWorkspace(), (r) async {
        calls.add(r);
        return header(r, 'Authorization') == null
            ? answer(401, headers: {'WWW-Authenticate': 'Digest realm="shop-realm", nonce="n1", qop="auth", opaque="op9"'})
            : answer(200);
      });
      await runner.run(const RunOptions(environment: 'Staging'));
      final auth = header(calls[1], 'Authorization')!;
      String field(String name) => RegExp('$name="?([^",]+)"?').firstMatch(auth)![1]!;
      final cnonce = field('cnonce');
      expect(field('nc'), '00000001');
      expect(field('qop'), 'auth');
      expect(field('opaque'), 'op9');
      String md5Hex(String s) => md5.convert(utf8.encode(s)).toString();
      final ha1 = md5Hex('ann:shop-realm:s3cret pass');
      final ha2 = md5Hex('GET:/digest/orders?id=7');
      expect(field('response'), md5Hex('$ha1:n1:00000001:$cnonce:auth:$ha2'));
    });

    test('a 401 without a usable challenge stands, and a rejected answer is not retried again', () async {
      var plain = 0;
      final noChallenge = await WorkspaceRunner.parse(digestWorkspace(), (r) async {
        plain++;
        return answer(401, headers: {'www-authenticate': 'Basic realm="x"'});
      }).run(const RunOptions(environment: 'Staging'));
      expect(plain, 1);
      expect(noChallenge.outcomes.single.status, 401);
      expect(noChallenge.outcomes.single.passed, isFalse);

      var rejected = 0;
      final wrongPassword = await WorkspaceRunner.parse(digestWorkspace(), (r) async {
        rejected++;
        return answer(401, headers: {'www-authenticate': 'Digest realm="shop-realm", nonce="abc123nonce"'});
      }).run(const RunOptions(environment: 'Staging'));
      expect(rejected, 2);
      expect(wrongPassword.outcomes.single.failures, contains('HTTP 401 Unauthorized'));
    });

    test('a server that does not ask for digest gets a single request', () async {
      var n = 0;
      final summary = await WorkspaceRunner.parse(digestWorkspace(), (r) async {
        n++;
        return answer(200);
      }).run(const RunOptions(environment: 'Staging'));
      expect(n, 1);
      expect(summary.ok, isTrue);
    });
  });
}
