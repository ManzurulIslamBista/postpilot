// `postpilot run` and the MCP server with Odoo: smart references are looked up on the server, an Odoo 18 session
// carries its cookie from one request to the next, an expired session logs in again, and the production lock reads
// the model and the method from a call_kw body. The only server is an in-process Odoo.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/features/auth_renewal/domain/entities/relogin_config.dart';
import 'package:postpilot/features/cli/cli_cookies.dart';
import 'package:postpilot/features/cli/production_lock.dart';
import 'package:postpilot/features/cli/workspace_runner.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import '../odoo/support/fake_odoo.dart';

CliSend _over(ApiClient api, {void Function(CliRequest)? onSend}) => (request) async {
      onSend?.call(request);
      final r = await api.send(ApiRequestSpec(method: request.method, url: request.url, headers: request.headers, body: request.body));
      return CliResponse(statusCode: r.statusCode, statusMessage: r.statusMessage, headers: r.headers, bodyBytes: r.bodyBytes, duration: r.duration);
    };

BackupRequest _post(String name, String path, String body, {List<KeyValueItem> headers = const []}) => BackupRequest(
      request: ApiRequestEntity(
        id: 0,
        collectionId: 0,
        folderId: null,
        name: name,
        method: HttpMethod.post,
        url: '{{odooUrl}}$path',
        headers: headers,
        queryParams: const [],
        body: RequestBody(type: BodyType.raw, rawText: body),
        auth: const RequestAuth(type: AuthType.none),
      ),
    );

EnvironmentVariableEntity _var(String key, String value, {bool secret = false}) =>
    EnvironmentVariableEntity(id: 0, environmentId: 0, key: key, value: value, isSecret: secret, enabled: true);

final _json2Headers = [
  KeyValueItem(key: 'Authorization', value: 'bearer {{odooApiKey}}'),
  KeyValueItem(key: 'X-Odoo-Database', value: '{{odooDb}}'),
];

String _workspace(FakeOdoo odoo, List<BackupRequest> requests, {String environment = 'Staging', RequestAuth? auth, bool jsonRpc = false}) => BackupCodec.encode(BackupSnapshot(
      exportedAt: DateTime.utc(2026),
      environments: [
        BackupEnvironment(name: environment, variables: [
          _var('odooUrl', odoo.host),
          _var('odooDb', odoo.db),
          if (jsonRpc) ...[_var('odooLogin', odoo.login), _var('odooPassword', odoo.password, secret: true)] else _var('odooApiKey', odoo.apiKey, secret: true),
        ]),
      ],
      collections: [BackupCollection(name: 'Odoo', auth: auth, requests: requests)],
    ));

const _login = '{"jsonrpc": "2.0", "method": "call", "params": {"db": "{{odooDb}}", "login": "{{odooLogin}}", "password": "{{odooPassword}}"}}';
const _count = '{"jsonrpc": "2.0", "method": "call", "params": {"model": "res.partner", "method": "search_count", "args": [[]], "kwargs": {}}}';

void main() {
  late FakeOdoo odoo;
  setUp(() => odoo = FakeOdoo());

  group('smart references in the command line', () {
    test('the ids are looked up on the server of the request and the body carries numbers', () async {
      final runner = WorkspaceRunner.parse(
        _workspace(odoo, [
          _post('Create partner', '/json/2/res.partner/create', '{"vals_list": [{"name": "X", "parent_id": {{xmlid:base.main_partner}}, "country_id": {{ref:res.country:BD}}}]}', headers: _json2Headers),
        ]),
        _over(odoo),
      );

      final summary = await runner.run(const RunOptions(environment: 'Staging'));

      final outcome = summary.outcomes.single;
      expect(outcome.error, isNull);
      expect(outcome.passed, isTrue);
      expect(odoo.records['res.partner']!.last, allOf(containsPair('parent_id', 1), containsPair('country_id', 20)));
      expect(odoo.calls, ['ir.model.data.search_read', 'res.country.name_search', 'res.partner.create']);
    });

    test('a token that cannot be resolved fails that request with the reason, and nothing with the literal is sent', () async {
      final runner = WorkspaceRunner.parse(
        _workspace(odoo, [
          _post('Create partner', '/json/2/res.partner/create', '{"vals_list": [{"name": "X", "parent_id": {{xmlid:base.nope}}}]}', headers: _json2Headers),
          _post('Count', '/json/2/res.partner/search_count', '{"domain": []}', headers: _json2Headers),
        ]),
        _over(odoo),
      );

      final summary = await runner.run(const RunOptions(environment: 'Staging'));

      expect(summary.outcomes[0].passed, isFalse);
      expect(summary.outcomes[0].error, allOf(startsWith('XML-ID base.nope not found on https://odoo.test'), endsWith('The request was not sent.')));
      expect(odoo.writes, isEmpty);
      expect(odoo.requests.where((r) => r.body is List<int> && utf8.decode(r.body as List<int>).contains('{{')), isEmpty);
      expect(summary.outcomes[1].passed, isTrue, reason: 'the next request still runs');
    });

    test('the answers are kept for the run: a second request with the same token asks nothing', () async {
      final runner = WorkspaceRunner.parse(
        _workspace(odoo, [
          _post('One', '/json/2/res.partner/write', '{"ids": [3], "vals": {"parent_id": {{xmlid:base.main_partner}}}}', headers: _json2Headers),
          _post('Two', '/json/2/res.partner/write', '{"ids": [4], "vals": {"parent_id": {{xmlid:base.main_partner}}}}', headers: _json2Headers),
        ]),
        _over(odoo),
      );

      await runner.run(const RunOptions(environment: 'Staging'));

      expect(odoo.calls.where((c) => c == 'ir.model.data.search_read'), hasLength(1));
      expect(odoo.records['res.partner']!.firstWhere((r) => r['id'] == 4)['parent_id'], 1);
    });

    test('a variable an agent passes cannot make the lookup go to another server', () async {
      final runner = WorkspaceRunner.parse(
        _workspace(odoo, [
          _post('Create partner', '/json/2/res.partner/create', '{"vals_list": [{"name": "X", "parent_id": {{xmlid:base.main_partner}}}]}', headers: _json2Headers),
        ]),
        _over(odoo),
      );

      final summary = await runner.run(const RunOptions(environment: 'Staging', agentVariables: {'odooUrl': 'https://evil.test'}));

      expect(summary.outcomes.single.blocked, isNotNull);
      expect(odoo.requests, isEmpty, reason: 'neither the lookup nor the request left');
    });
  });

  group('an Odoo 18 session in the command line', () {
    test('the cookie of the Log in request is carried to the next ones, in memory', () async {
      final sent = <CliRequest>[];
      final runner = WorkspaceRunner.parse(
        _workspace(odoo, [_post('Log in', '/web/session/authenticate', _login), _post('Count', '/web/dataset/call_kw/res.partner/search_count', _count)], jsonRpc: true),
        _over(odoo, onSend: sent.add),
      );

      final summary = await runner.run(const RunOptions(environment: 'Staging'));

      expect(summary.outcomes.map((o) => o.passed), [true, true]);
      expect(jsonDecode(summary.outcomes[1].responseBody!)['result'], 4);
      expect(sent[1].headers['Cookie'], 'session_id=sess1; frontend_lang=en_US', reason: 'every cookie the login set, and no other');
      expect(odoo.authenticateCount, 1);
    });

    test('an expired session logs in again through the collection\'s re-login, once', () async {
      final runner = WorkspaceRunner.parse(
        _workspace(
          odoo,
          [_post('Log in', '/web/session/authenticate', _login), _post('Count', '/web/dataset/call_kw/res.partner/search_count', _count)],
          jsonRpc: true,
          auth: const RequestAuth(type: AuthType.none).withRelogin(const ReloginConfig(request: 'Log in')),
        ),
        _over(odoo),
      );

      // Only Count runs: with no session at all Odoo says it expired, which starts the re-login.
      final summary = await runner.run(const RunOptions(environment: 'Staging', requests: ['Count']));

      final count = summary.outcomes.single;
      expect(count.passed, isTrue, reason: count.error ?? count.responseBody);
      expect(jsonDecode(count.responseBody!)['result'], 4);
      expect(count.notes.single, startsWith('Re-authenticated via "Log in" and retried'));
      expect(odoo.authenticateCount, 1);
    });

    test('without a re-login the expiry is the answer, as Odoo gave it', () async {
      final runner = WorkspaceRunner.parse(
        _workspace(odoo, [_post('Count', '/web/dataset/call_kw/res.partner/search_count', _count)], jsonRpc: true),
        _over(odoo),
      );

      final summary = await runner.run(const RunOptions(environment: 'Staging'));

      expect(summary.outcomes.single.responseBody, contains('SessionExpiredException'));
      expect(summary.outcomes.single.status, 200);
    });

    test('smart references of a JSON-RPC request log in with the environment\'s login', () async {
      final runner = WorkspaceRunner.parse(
        _workspace(
          odoo,
          [
            _post('Log in', '/web/session/authenticate', _login),
            _post('Update', '/web/dataset/call_kw/res.partner/write', '{"jsonrpc": "2.0", "method": "call", "params": {"model": "res.partner", "method": "write", "args": [[3], {"parent_id": {{xmlid:base.main_partner}}}], "kwargs": {}}}'),
          ],
          jsonRpc: true,
        ),
        _over(odoo),
      );

      final summary = await runner.run(const RunOptions(environment: 'Staging'));

      expect(summary.outcomes.map((o) => o.passed), [true, true]);
      expect(odoo.records['res.partner']!.firstWhere((r) => r['id'] == 3)['parent_id'], 1);
    });
  });

  group('the production lock reads a call_kw body', () {
    Future<RunSummary> runIn(String environment, String url, String body, {bool allow = false}) {
      final runner = WorkspaceRunner.parse(_workspace(odoo, [_post('Call', url, body)], environment: environment, jsonRpc: true), _over(odoo));
      return runner.run(RunOptions(environment: environment, production: ProductionLock(allow: allow)));
    }

    String call(String method, [String args = '[[3]]']) =>
        '{"jsonrpc": "2.0", "method": "call", "params": {"model": "res.partner", "method": "$method", "args": $args, "kwargs": {}}}';

    test('an unlink behind a URL that says search_read is refused in production, and nothing is sent', () async {
      final summary = await runIn('Production', '/web/dataset/call_kw/res.partner/search_read', call('unlink'));
      expect(summary.outcomes.single.blocked, isNotNull);
      expect(summary.outcomes.single.blocked, contains('production lock'));
      expect(odoo.requests, isEmpty);
    });

    test('a call_kw to a bare path is judged by the method in its body', () async {
      expect((await runIn('Production', '/web/dataset/call_kw', call('unlink'))).outcomes.single.blocked, isNotNull);
      expect((await runIn('Production', '/web/dataset/call_kw', call('write', '[[3], {"name": "x"}]'))).outcomes.single.blocked, isNotNull);
      expect(odoo.requests, isEmpty);
    });

    test('a read still runs in production, with the lock on', () async {
      final summary = await runIn('Production', '/web/dataset/call_kw', call('search_count', '[[]]'));
      expect(summary.outcomes.single.blocked, isNull);
      expect(summary.outcomes.single.status, 200);
    });

    test('with --allow-production the write goes through', () async {
      final summary = await runIn('Production', '/web/dataset/call_kw/res.partner/write', call('write', '[[3], {"name": "Renamed"}]'), allow: true);
      expect(summary.outcomes.single.blocked, isNull);
    });
  });

  group('the in-memory cookie jar', () {
    CliRequest request(String url, {Map<String, String> headers = const {}}) => CliRequest(method: 'GET', url: url, headers: headers, body: null, timeout: const Duration(seconds: 5), verifySsl: true);
    CliResponse response(Map<String, String> headers) => CliResponse(statusCode: 200, statusMessage: 'OK', headers: headers, bodyBytes: const [], duration: Duration.zero);

    test('keeps what a response sets and sends it to the same origin only', () async {
      final sent = <CliRequest>[];
      final jar = CliCookieJar();
      final send = jar.wrap((r) async {
        sent.add(r);
        return response({'set-cookie': 'session_id=abc123; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Max-Age=604800; HttpOnly; Path=/, frontend_lang=en_US; Path=/'});
      });

      await send(request('https://odoo.test/web/session/authenticate'));
      await send(request('https://odoo.test/web/dataset/call_kw'));
      await send(request('https://other.test/x'));
      await send(request('http://odoo.test/x'));

      expect(sent[0].headers.containsKey('Cookie'), isFalse);
      expect(sent[1].headers['Cookie'], 'session_id=abc123; frontend_lang=en_US');
      expect(sent[2].headers.containsKey('Cookie'), isFalse, reason: 'another host');
      expect(sent[3].headers.containsKey('Cookie'), isFalse, reason: 'another scheme and port');
    });

    test('a request with a Cookie header of its own is sent as written', () async {
      final sent = <CliRequest>[];
      final send = (CliCookieJar()..store('https://odoo.test/', {'set-cookie': 'session_id=jar'})).wrap((r) async {
        sent.add(r);
        return response(const {});
      });
      await send(request('https://odoo.test/x', headers: {'cookie': 'session_id=mine'}));
      expect(sent.single.headers, {'cookie': 'session_id=mine'});
    });

    test('an empty value or a Max-Age of zero deletes the cookie, which is how Odoo ends a session', () {
      final jar = CliCookieJar()..store('https://odoo.test/', {'set-cookie': 'session_id=abc; Path=/, tz=Europe/Brussels; Path=/'});
      expect(jar.cookieHeader('https://odoo.test/x'), 'session_id=abc; tz=Europe/Brussels');
      jar.store('https://odoo.test/', {'Set-Cookie': 'session_id=; Max-Age=0; Path=/'});
      expect(jar.cookieHeader('https://odoo.test/x'), 'tz=Europe/Brussels');
      jar.store('https://odoo.test/', {'set-cookie': 'tz=x; Max-Age=-1'});
      expect(jar.cookieHeader('https://odoo.test/x'), isNull);
    });

    test('an Expires date with its comma does not split a cookie in two', () {
      final jar = CliCookieJar()..store('https://odoo.test/', {'set-cookie': 'a=1; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/'});
      expect(jar.cookieHeader('https://odoo.test/'), 'a=1');
    });

    test('adding a header keeps every other part of the request', () async {
      CliRequest? seen;
      final jar = CliCookieJar()..store('https://odoo.test/', {'set-cookie': 'session_id=s'});
      final original = CliRequest(method: 'POST', url: 'https://odoo.test/x', headers: const {'A': 'b'}, body: const [1, 2], timeout: const Duration(seconds: 9), verifySsl: false, baseDir: '/work');
      await jar.wrap((r) async {
        seen = r;
        return response(const {});
      })(original);
      expect(seen!.headers, {'A': 'b', 'Cookie': 'session_id=s'});
      expect((seen!.method, seen!.url, seen!.body, seen!.timeout, seen!.verifySsl, seen!.baseDir, seen!.upload), ('POST', 'https://odoo.test/x', const [1, 2], const Duration(seconds: 9), false, '/work', null));
    });
  });
}
