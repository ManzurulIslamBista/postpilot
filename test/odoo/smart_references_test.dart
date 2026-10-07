import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/odoo/data/odoo_client.dart';
import 'package:postpilot/features/odoo/data/odoo_smart_resolver.dart';
import 'package:postpilot/features/odoo/domain/services/smart_references.dart';
import 'package:postpilot/features/request_builder/domain/services/undefined_variables.dart';
import 'support/fake_odoo.dart';

SmartReferenceContext _json2(FakeOdoo odoo, {String path = '/json/2/res.partner/create', String? apiKey, Map<String, String> extra = const {}}) => SmartReferenceContext(
      url: '${odoo.host}$path',
      headers: {'Authorization': 'bearer ${apiKey ?? odoo.apiKey}', 'X-Odoo-Database': odoo.db, 'Content-Type': 'application/json'},
      variable: (name) => extra[name],
    );

SmartReferenceContext _rpc(FakeOdoo odoo, {Map<String, String>? variables, Map<String, String> headers = const {}}) => SmartReferenceContext(
      url: '${odoo.host}/web/dataset/call_kw/res.partner/write',
      headers: headers,
      variable: (name) => (variables ??
          {'odooLogin': odoo.login, 'odooPassword': odoo.password, 'odooDb': odoo.db})[name],
    );

Future<SmartReferenceException> _failure(Future<Object?> call) async {
  try {
    await call;
  } on SmartReferenceException catch (e) {
    return e;
  }
  fail('a SmartReferenceException was expected');
}

void main() {
  group('the token', () {
    test('an XML-ID is module.name, a name reference is model:name and the name may hold colons and spaces', () {
      final xml = SmartReference.tryParse('xmlid:base.main_company')!;
      expect((xml.kind, xml.module, xml.xmlName), (SmartReferenceKind.xmlId, 'base', 'main_company'));
      expect(xml.describe, 'XML-ID base.main_company');
      final named = SmartReference.tryParse('ref:res.partner:Azure Interior')!;
      expect((named.kind, named.model, named.recordName), (SmartReferenceKind.name, 'res.partner', 'Azure Interior'));
      expect(SmartReference.tryParse('ref:res.partner:Odoo S.A.: Belgium (HQ)')!.recordName, 'Odoo S.A.: Belgium (HQ)');
      expect(SmartReference.tryParse('ref:res.country:BD')!.recordName, 'BD');
      expect(named.token, '{{ref:res.partner:Azure Interior}}');
    });

    test('a badly written token is refused with the way to write it', () {
      for (final bad in ['xmlid:main_company', 'xmlid:base.', 'xmlid:.x', 'xmlid:base. x', 'ref:res.partner', 'ref:res.partner:', 'ref:partner:Ann', 'ref::Ann']) {
        expect(SmartReference.tryParse(bad), isNull, reason: bad);
        expect(SmartReferences.problemWith(bad), isNotNull, reason: bad);
      }
      expect(SmartReferences.problemWith('xmlid:main_company'), contains('module.name'));
      expect(SmartReferences.problemWith('ref:res.partner'), contains('{{ref:model:name}}'));
      expect(SmartReferences.problemWith('xmlid:base.main_company'), isNull);
    });

    test('only xmlid and ref are smart', () {
      expect(SmartReferences.isSmartKey('xmlid:base.x'), isTrue);
      expect(SmartReferences.isSmartKey('ref:res.partner:A'), isTrue);
      expect(SmartReferences.isSmartKey('xmlid'), isFalse);
      expect(SmartReferences.isSmartKey('refresh_token'), isFalse);
      expect(SmartReferences.hasAny('a {{xmlid:base.x}} b'), isTrue);
      expect(SmartReferences.hasAny('{{ref}} {{xmlidx:y}}'), isFalse);
    });

    test('pendingKeys and ordinary split what a request leaves undefined', () {
      const undefined = [
        UndefinedVariable('baseUrl', ['the URL']),
        UndefinedVariable('xmlid:base.x', ['the request body'], inBody: true),
        UndefinedVariable('ref:res.country:BD', ['the request body'], inBody: true),
      ];
      expect(SmartReferences.pendingKeys(undefined), ['xmlid:base.x', 'ref:res.country:BD']);
      expect(SmartReferences.ordinary(undefined).map((v) => v.name), ['baseUrl']);
    });
  });

  group('the variable resolver', () {
    test('leaves a smart reference alone and reports it undefined, until a scope holds its id', () {
      final resolver = VariableResolver({'a': '1'});
      const body = '{"p": {{xmlid:base.main_company}}, "c": {{ref:res.country:BD}}, "a": {{a}}}';
      expect(resolver.resolve(body), '{"p": {{xmlid:base.main_company}}, "c": {{ref:res.country:BD}}, "a": 1}');
      expect(resolver.undefinedIn(body), ['xmlid:base.main_company', 'ref:res.country:BD']);

      final filled = VariableResolver.layered([
        {'xmlid:base.main_company': '1', 'ref:res.country:BD': '20'},
        {'a': '1'},
      ]);
      expect(filled.resolve(body), '{"p": 1, "c": 20, "a": 1}');
      expect(filled.undefinedIn(body), isEmpty);
    });

    test('a variable whose value holds a smart reference is expanded first, then resolved', () {
      final resolver = VariableResolver.layered([
        {'xmlid:base.main_company': '7'},
        {'companyId': '{{xmlid:base.main_company}}'},
      ]);
      expect(resolver.resolve('{"company_id": {{companyId}}}'), '{"company_id": 7}');
      expect(VariableResolver({'companyId': '{{xmlid:base.main_company}}'}).undefinedIn('{{companyId}}'), ['xmlid:base.main_company']);
    });

    test('a name with spaces and punctuation is one token, and ordinary variables are untouched', () {
      final resolver = VariableResolver({'ref': 'plain', 'ref:res.partner:Azure Interior': '2'});
      expect(resolver.resolve('{{ref}} {{ref:res.partner:Azure Interior}} {{ref:res.partner:Other}}'), 'plain 2 {{ref:res.partner:Other}}');
    });
  });

  group('looking the ids up', () {
    late FakeOdoo odoo;
    late OdooSmartReferenceResolver resolver;
    var now = DateTime.utc(2026, 10, 6, 12);
    setUp(() {
      odoo = FakeOdoo();
      now = DateTime.utc(2026, 10, 6, 12);
      resolver = OdooSmartReferenceResolver(odoo, now: () => now);
    });

    test('an XML-ID, a name and a country code are resolved in one go', () async {
      final ids = await resolver.resolve(_json2(odoo), ['xmlid:base.main_partner', 'ref:res.partner:Azure Interior', 'ref:res.country:BD', 'xmlid:base.us']);
      expect(ids, {
        'xmlid:base.main_partner': '1',
        'ref:res.partner:Azure Interior': '2',
        'ref:res.country:BD': '20',
        'xmlid:base.us': '233',
      });
      expect(odoo.calls, ['ir.model.data.search_read', 'res.partner.name_search', 'res.country.name_search', 'ir.model.data.search_read']);
      expect(odoo.writes, isEmpty, reason: 'a lookup only reads');
    });

    test('an answer is kept per server and database: the second send asks nothing', () async {
      await resolver.resolve(_json2(odoo), ['xmlid:base.main_partner']);
      odoo.calls.clear();
      expect(await resolver.resolve(_json2(odoo), ['xmlid:base.main_partner']), {'xmlid:base.main_partner': '1'});
      expect(odoo.calls, isEmpty);
      expect(resolver.cachedCount, 1);

      now = now.add(const Duration(minutes: 11));
      await resolver.resolve(_json2(odoo), ['xmlid:base.main_partner']);
      expect(odoo.calls, ['ir.model.data.search_read'], reason: 'ten minutes is the most a stale id is trusted');

      resolver.clearCache();
      odoo.calls.clear();
      await resolver.resolve(_json2(odoo), ['xmlid:base.main_partner']);
      expect(odoo.calls, hasLength(1));
    });

    test('another database is another answer', () async {
      final other = FakeOdoo(host: 'https://odoo2.test', db: 'staging');
      other.records['ir.model.data']!.firstWhere((r) => r['name'] == 'main_partner')['res_id'] = 99;
      final shared = _Router({odoo.host: odoo, other.host: other});
      final r = OdooSmartReferenceResolver(shared, now: () => now);
      final a = await r.resolve(_json2(odoo), ['xmlid:base.main_partner']);
      final b = await r.resolve(
        SmartReferenceContext(url: 'https://odoo2.test/json/2/res.partner/create', headers: {'Authorization': 'bearer ${other.apiKey}', 'X-Odoo-Database': 'staging'}, variable: (_) => null),
        ['xmlid:base.main_partner'],
      );
      expect(a['xmlid:base.main_partner'], '1');
      expect(b['xmlid:base.main_partner'], '99', reason: 'the same XML-ID is another id in another database');
    });

    test('an XML-ID that does not exist says which server it was looked up on', () async {
      final e = await _failure(resolver.resolve(_json2(odoo), ['xmlid:base.foo']));
      expect(e.message, startsWith('XML-ID base.foo not found on https://odoo.test (database prod).'));
      expect(e.message, contains('module.name'));
    });

    test('a user who may not read ir.model.data is served by check_object_reference', () async {
      odoo.deniedMethods.add('ir.model.data.search_read');
      expect(await resolver.resolve(_json2(odoo), ['xmlid:base.bd']), {'xmlid:base.bd': '20'});
      expect(odoo.calls, ['ir.model.data.search_read', 'ir.model.data.check_object_reference']);
      final e = await _failure(resolver.resolve(_json2(odoo), ['xmlid:base.foo']));
      expect(e.message, startsWith('XML-ID base.foo not found on https://odoo.test'));
      odoo.deniedMethods.add('ir.model.data.check_object_reference');
      final denied = await _failure(resolver.resolve(_json2(odoo), ['xmlid:base.us2']));
      expect(denied.message, contains('may not read it'));
    });

    test('a name that is not unique lists the records, a name that is not found lists the similar ones', () async {
      odoo.records['res.partner']!.add({'id': 5, 'name': 'Deco Addict', 'is_company': true});
      final ambiguous = await _failure(resolver.resolve(_json2(odoo), ['ref:res.partner:Deco Addict']));
      expect(ambiguous.message, contains('matches 2 records'));
      expect(ambiguous.message, contains('3: Deco Addict; 5: Deco Addict'));
      expect(ambiguous.message, contains('{{xmlid:module.name}}'));

      final missing = await _failure(resolver.resolve(_json2(odoo), ['ref:res.partner:Azure']));
      expect(missing.message, 'No record of res.partner is named "Azure" on https://odoo.test. Similar: 2: Azure Interior.');
      final nothing = await _failure(resolver.resolve(_json2(odoo), ['ref:res.partner:Zzz']));
      expect(nothing.message, 'No record of res.partner is named "Zzz" on https://odoo.test.');
    });

    test('a token that is not well formed is refused before anything is asked', () async {
      final e = await _failure(resolver.resolve(_json2(odoo), ['xmlid:nodot']));
      expect(e.message, contains('is not an XML-ID'));
      expect(odoo.requests, isEmpty);
    });

    test('a wrong API key, an unknown model and an unreachable server are each explained, never with the key in them', () async {
      final wrong = await _failure(resolver.resolve(_json2(odoo, apiKey: 'sk-live-very-secret'), ['xmlid:base.bd']));
      expect(wrong.message, 'Could not look up {{xmlid:base.bd}} on https://odoo.test: Invalid apikey');
      expect(wrong.message, isNot(contains('sk-live-very-secret')));

      final unknownModel = await _failure(resolver.resolve(_json2(odoo), ['ref:sale.partnr:X']));
      expect(unknownModel.message, contains('does not exist'));

      final offline = OdooSmartReferenceResolver(_Offline());
      final down = await _failure(offline.resolve(_json2(odoo, apiKey: 'sk-live-very-secret'), ['xmlid:base.bd']));
      expect(down.message, startsWith('Could not reach https://odoo.test to look up {{xmlid:base.bd}}: '));
      expect(down.message, isNot(contains('sk-live-very-secret')));
    });

    test('a server with credentials in its URL does not show them in a message', () async {
      final e = await _failure(OdooSmartReferenceResolver(_Offline()).resolve(
        SmartReferenceContext(url: 'https://admin:hunter2pw@odoo.test/json/2/res.partner/create', headers: {'Authorization': 'bearer k'}, variable: (_) => null),
        ['xmlid:base.bd'],
      ));
      expect(e.message, isNot(contains('hunter2pw')));
    });

    test('the request says nothing about Odoo: that is explained, and odooUrl is the fallback', () async {
      final notOdoo = SmartReferenceContext(url: 'https://api.example.com/users', headers: const {}, variable: (_) => null);
      expect((await _failure(resolver.resolve(notOdoo, ['xmlid:base.bd']))).message, contains('not an Odoo call'));
      final viaVariables = SmartReferenceContext(
        url: 'https://api.example.com/users',
        headers: const {},
        variable: (name) => {'odooUrl': odoo.host, 'odooApiKey': odoo.apiKey, 'odooDb': odoo.db}[name],
      );
      expect(await resolver.resolve(viaVariables, ['xmlid:base.bd']), {'xmlid:base.bd': '20'});
    });

    test('a JSON-2 request without an API key cannot be looked up for', () async {
      final noKey = SmartReferenceContext(url: '${odoo.host}/json/2/res.partner/create', headers: const {}, variable: (_) => null);
      expect((await _failure(resolver.resolve(noKey, ['xmlid:base.bd']))).message, contains('sends no API key'));
    });

    test('with Odoo 18 the lookup logs in with odooLogin and odooPassword and uses call_kw', () async {
      final ids = await resolver.resolve(_rpc(odoo), ['xmlid:base.main_partner', 'ref:res.country:BD']);
      expect(ids, {'xmlid:base.main_partner': '1', 'ref:res.country:BD': '20'});
      expect(odoo.authenticateCount, 1);
      expect(odoo.requests.where((r) => r.url.contains('/call_kw/')).map((r) => r.url), [
        'https://odoo.test/web/dataset/call_kw/ir.model.data/search_read',
        'https://odoo.test/web/dataset/call_kw/res.country/name_search',
      ]);
      expect(odoo.writes, isEmpty);
    });

    test('without credentials the session of another request (the Log in request) is used, and its absence is explained', () async {
      // A session some other request opened.
      final login = await OdooClient(odoo).connect(OdooConnection(baseUrl: odoo.host, database: odoo.db, apiKey: odoo.password, protocol: OdooProtocol.jsonRpc, login: odoo.login));
      expect(login.ok, isTrue);
      final withCookie = _rpc(odoo, variables: const {}, headers: {'Cookie': 'session_id=sess1'});
      expect(await resolver.resolve(withCookie, ['xmlid:base.bd']), {'xmlid:base.bd': '20'});
      final without = await _failure(OdooSmartReferenceResolver(odoo).resolve(_rpc(odoo, variables: const {}), ['xmlid:base.bd']));
      expect(without.message, allOf(contains('not open or has expired'), contains('odooLogin')));
    });

    test('a JSON-RPC password that is wrong is a lookup failure that says so', () async {
      final e = await _failure(resolver.resolve(_rpc(odoo, variables: {'odooLogin': 'admin', 'odooPassword': 'nope', 'odooDb': 'prod'}), ['xmlid:base.bd']));
      expect(e.message, contains('Access Denied'));
    });
  });
}

/// Sends each request to the fake that owns its host.
final class _Router implements ApiClient {
  final Map<String, ApiClient> hosts;
  _Router(this.hosts);

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) {
    final uri = Uri.parse(spec.url);
    return hosts['${uri.scheme}://${uri.authority}']!.send(spec);
  }
}

final class _Offline implements ApiClient {
  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async => throw NetworkException(
        'Failed host lookup for ${spec.url} (${spec.headers['Authorization']})',
        kind: NetworkErrorKind.connectionError,
        summary: "Couldn't find the server odoo.test",
      );
}
