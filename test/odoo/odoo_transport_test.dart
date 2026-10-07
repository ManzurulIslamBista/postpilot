import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/odoo/data/odoo_client.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_json2.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_jsonrpc.dart';
import 'support/fake_odoo.dart';

OdooConnection _json2(FakeOdoo odoo) => OdooConnection(baseUrl: odoo.host, database: odoo.db, apiKey: odoo.apiKey);
OdooConnection _rpc(FakeOdoo odoo, {String? password, String? database}) => OdooConnection(
      baseUrl: odoo.host,
      database: database ?? odoo.db,
      apiKey: password ?? odoo.password,
      protocol: OdooProtocol.jsonRpc,
      login: odoo.login,
    );

void main() {
  group('the same call through both APIs', () {
    late FakeOdoo odoo;
    late OdooClient client;
    setUp(() {
      odoo = FakeOdoo();
      client = OdooClient(odoo);
    });

    final calls = <String, OdooCall>{
      'search_read': const OdooCall(model: 'res.partner', method: 'search_read', params: {'domain': [['is_company', '=', true]], 'fields': ['name'], 'limit': 2, 'order': 'id desc'}),
      'search_count': const OdooCall(model: 'res.partner', method: 'search_count', params: {'domain': [['is_company', '=', true]]}),
      'read': const OdooCall(model: 'res.partner', method: 'read', ids: [2], params: {'fields': ['name', 'country_id']}),
      'name_search': const OdooCall(model: 'res.partner', method: 'name_search', params: {'name': 'azure', 'operator': 'ilike', 'limit': 5}),
      'default_get': const OdooCall(model: 'res.partner', method: 'default_get', params: {'fields_list': ['type', 'active']}),
      'exists': const OdooCall(model: 'res.partner', method: 'exists', ids: [3, 999]),
    };
    // What Odoo answers, worked out by hand from the fake's records.
    final expected = <String, Object?>{
      // Three companies, the first two by limit (the fake keeps the order of its rows).
      'search_read': [
        {'id': 1, 'name': 'My Company'},
        {'id': 2, 'name': 'Azure Interior'},
      ],
      'search_count': 3,
      'read': [
        {'id': 2, 'name': 'Azure Interior', 'country_id': [233, 'United States']},
      ],
      'name_search': [
        [2, 'Azure Interior'],
      ],
      'default_get': {'active': true, 'type': 'contact'},
      'exists': [3],
    };

    for (final name in calls.keys) {
      test('$name answers the same with JSON-2 and with a JSON-RPC session', () async {
        final viaJson2 = await client.call(_json2(odoo), calls[name]!);
        final viaRpc = await client.call(_rpc(odoo), calls[name]!);
        expect(viaJson2.ok, isTrue, reason: viaJson2.error?.message);
        expect(viaRpc.ok, isTrue, reason: viaRpc.error?.message);
        expect(viaJson2.json, expected[name]);
        expect(viaRpc.json, expected[name]);
      });
    }

    test('the body of a JSON-RPC result is the bare result, as JSON-2 would send it', () async {
      final r = await client.call(_rpc(odoo), calls['search_count']!);
      expect(r.body, '3');
      expect(r.json, 3);
    });
  });

  group('JSON-RPC call_kw body', () {
    test('passes the leading parameters by position and the rest by name', () {
      Map<String, Object?> params(OdooCall c) => OdooJsonRpc.callBody(c)['params'] as Map<String, Object?>;

      expect(params(const OdooCall(model: 'res.partner', method: 'search_read', params: {'domain': [], 'fields': ['name'], 'limit': 20, 'order': 'id desc'})), {
        'model': 'res.partner',
        'method': 'search_read',
        'args': [<Object?>[], ['name']],
        'kwargs': {'limit': 20, 'order': 'id desc'},
      });
      expect(params(const OdooCall(model: 'res.partner', method: 'write', ids: [7], params: {'vals': {'name': 'X'}})), {
        'model': 'res.partner',
        'method': 'write',
        'args': [
          [7],
          {'name': 'X'},
        ],
        'kwargs': <String, Object?>{},
      });
      expect(params(const OdooCall(model: 'res.partner', method: 'create', params: {'vals_list': [{'name': 'A'}]}))['args'], [
        [
          {'name': 'A'},
        ],
      ]);
      // Before Odoo 19 a name search's domain is `args`, and a missing name leaves nothing to put it after.
      expect(params(const OdooCall(model: 'res.partner', method: 'name_search', params: {'domain': [['a', '=', 1]], 'limit': 3}))['kwargs'], {
        'args': [
          ['a', '=', 1],
        ],
        'limit': 3,
      });
      expect(params(const OdooCall(model: 'res.partner', method: 'unlink', ids: [1, 2]))['args'], [
        [1, 2],
      ]);
      expect(params(const OdooCall(model: 'res.partner', method: 'action_archive', ids: [5]))['args'], [
        [5],
      ]);
      expect(params(const OdooCall(model: 'res.partner', method: 'fields_get', params: {'attributes': ['type']}))['kwargs'], {
        'attributes': ['type'],
      });
      expect(params(const OdooCall(model: 'res.partner', method: 'search', context: {'lang': 'fr_FR'}, params: {'domain': []}))['kwargs'], {
        'context': {'lang': 'fr_FR'},
      });
    });

    test('the saved templates keep the {{recordId}} variable and are valid JSON once it has a value', () {
      final drafts = OdooJsonRpc.templatesFor('res.partner', sampleFields: const ['name']);
      expect(drafts, hasLength(10));
      for (final d in drafts) {
        expect(d.url, startsWith('{{odooUrl}}/web/dataset/call_kw/res.partner/'));
        expect(d.headers.containsKey('Authorization'), isFalse, reason: 'the session is the login');
        expect(() => jsonDecode(d.bodyText.replaceAll('{{recordId}}', '7')), returnsNormally, reason: d.name);
      }
      final delete = drafts.firstWhere((d) => d.name == 'Delete res.partner');
      expect(jsonDecode(delete.bodyText.replaceAll('{{recordId}}', '7')), {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': 'res.partner',
          'method': 'unlink',
          'args': [
            [7],
          ],
          'kwargs': <String, Object?>{},
        },
        'id': 1,
      });
      expect(delete.bodyText, contains('[{{recordId}}]'));
      final login = OdooJsonRpc.loginDraft();
      expect(login.url, '{{odooUrl}}/web/session/authenticate');
      expect(jsonDecode(login.bodyText)['params'], {'db': '{{odooDb}}', 'login': '{{odooLogin}}', 'password': '{{odooPassword}}'});
    });
  });

  group('the JSON-RPC session', () {
    test('logs in once, keeps only the session cookie and sends it on every call', () async {
      final odoo = FakeOdoo();
      final client = OdooClient(odoo);
      await client.call(_rpc(odoo), const OdooCall(model: 'res.partner', method: 'search_count', params: {'domain': <Object?>[]}));
      await client.call(_rpc(odoo), const OdooCall(model: 'res.partner', method: 'search_count', params: {'domain': <Object?>[]}));

      expect(odoo.authenticateCount, 1);
      final callKw = odoo.requests.where((r) => r.url.contains('/call_kw/')).toList();
      expect(callKw, hasLength(2));
      for (final r in callKw) {
        // Odoo also sets frontend_lang: only the session is kept.
        expect(r.headers['Cookie'], 'session_id=sess1');
      }
      final login = jsonDecode(utf8.decode(odoo.requests.first.body as List<int>));
      expect(login['params'], {'db': 'prod', 'login': 'admin', 'password': 'pw-456'});
    });

    test('an expired session logs in again once and the call goes through', () async {
      final odoo = FakeOdoo();
      final client = OdooClient(odoo);
      const count = OdooCall(model: 'res.partner', method: 'search_count', params: {'domain': <Object?>[]});
      expect((await client.call(_rpc(odoo), count)).json, 4);
      odoo.expireSessions();

      final again = await client.call(_rpc(odoo), count);

      expect(again.ok, isTrue);
      expect(again.json, 4);
      expect(odoo.authenticateCount, 2, reason: 'one login at first, one after the expiry');
      expect(odoo.requests.where((r) => r.url.contains('/call_kw/')), hasLength(3), reason: 'the first call, the one the server found expired, and its retry');
    });

    test('a session that expires again straight away is reported, never retried in a loop', () async {
      // A server that forgets every session before it answers a call.
      final odoo = _Forgetful();
      const count = OdooCall(model: 'res.partner', method: 'search_count', params: {'domain': <Object?>[]});

      final result = await OdooClient(odoo).call(_rpc(odoo), count);

      expect(result.ok, isFalse);
      expect(result.error!.exception, endsWith('SessionExpiredException'));
      // One login and a call that is refused, one more login and a retry that is refused: nothing beyond that.
      expect(odoo.authenticateCount, 2);
      expect(odoo.requests.where((r) => r.url.contains('/call_kw/')), hasLength(2));
    });

    test('a wrong password is explained, not shown as a server error', () async {
      final odoo = FakeOdoo();
      final r = await OdooClient(odoo).connect(_rpc(odoo, password: 'nope'));
      expect(r.ok, isFalse);
      expect(r.error!.title, 'Wrong login or password');
      expect(r.error!.hint, contains('database "prod"'));
    });

    test('connect reports who logged in and the server version', () async {
      final odoo = FakeOdoo();
      final r = await OdooClient(odoo).connect(_rpc(odoo));
      expect(r.ok, isTrue);
      expect((r.json as Map)['username'], 'admin');
      expect((r.json as Map)['server_version'], '17.0');
    });

    test('without a database the only one the server lists is used', () async {
      final odoo = FakeOdoo();
      final r = await OdooClient(odoo).connect(_rpc(odoo, database: ''));
      expect(r.ok, isTrue);
      final login = jsonDecode(utf8.decode(odoo.requests.where((q) => q.url.endsWith('/authenticate')).single.body as List<int>));
      expect(login['params']['db'], 'prod');
    });

    test('with the database list switched off the person is asked to type the name', () async {
      final odoo = FakeOdoo()..listsDatabases = false;
      final r = await OdooClient(odoo).connect(_rpc(odoo, database: ''));
      expect(r.ok, isFalse);
      expect(r.error!.title, 'Database needed');
      expect(r.error!.message, contains('type the name'));
      final listed = await OdooClient(odoo).databases(_rpc(odoo, database: ''));
      expect(listed.names, isEmpty);
      expect(listed.problem, contains('list_db'));
    });

    test('several databases are named, not guessed', () async {
      final odoo = FakeOdoo()..databases = ['prod', 'staging'];
      final r = await OdooClient(odoo).connect(_rpc(odoo, database: ''));
      expect(r.error!.message, contains('prod, staging'));
    });
  });

  group('JSON-2', () {
    test('a wrong key is an Invalid API key', () async {
      final odoo = FakeOdoo();
      final r = await OdooClient(odoo).connect(OdooConnection(baseUrl: odoo.host, database: odoo.db, apiKey: 'bad'));
      expect(r.ok, isFalse);
      expect(r.error!.title, 'Invalid API key');
    });

    test('connect is a harmless context_get', () async {
      final odoo = FakeOdoo();
      final r = await OdooClient(odoo).connect(_json2(odoo));
      expect(r.ok, isTrue);
      expect((r.json as Map)['lang'], 'en_US');
      expect(odoo.calls, ['res.users.context_get']);
    });
  });

  group('OdooConnection', () {
    test('reads the variables of an environment for either API', () {
      final json2 = OdooConnection.fromVariables({'odooUrl': 'x.odoo.com', 'odooDb': 'd', 'odooApiKey': 'k'});
      expect(json2.protocol, OdooProtocol.json2);
      expect(json2.apiKey, 'k');
      expect(json2.isComplete, isTrue);
      final rpc = OdooConnection.fromVariables({'odooUrl': 'x.odoo.com', 'odooDb': 'd', 'odooProtocol': 'jsonrpc', 'odooLogin': 'admin', 'odooPassword': 'pw'});
      expect(rpc.protocol, OdooProtocol.jsonRpc);
      expect(rpc.apiKey, 'pw');
      expect(rpc.login, 'admin');
      expect(rpc.isComplete, isTrue);
      expect(OdooConnection.fromVariables({'odooUrl': 'x', 'odooProtocol': 'jsonrpc', 'odooPassword': 'pw'}).isComplete, isFalse, reason: 'no login');
      expect(OdooConnection.fromVariables({'odooUrl': 'x', 'odooProtocol': 'weird'}).protocol, OdooProtocol.json2);
    });
  });
}

/// Forgets every session before it answers a call, to prove a call is retried once and no more.
final class _Forgetful extends FakeOdoo {
  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) {
    if (spec.url.contains('/call_kw/')) expireSessions();
    return super.send(spec);
  }
}
