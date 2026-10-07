// Smart references and the Odoo 18 session through the real send path: the real use cases over a real in-memory
// database, and an in-process Odoo as the only server. Nothing real is called.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/auth_renewal/domain/entities/relogin_config.dart';
import 'package:postpilot/features/auth_renewal/domain/usecases/relogin_usecase.dart';
import 'package:postpilot/features/defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/odoo/data/odoo_smart_resolver.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/services/request_spec_builder.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';
import 'package:postpilot/features/scripting/domain/evaluator/assertion_evaluator.dart';
import 'package:postpilot/features/scripting/domain/usecases/run_request_scripts_usecase.dart';
import '../auth_renewal/auth_harness.dart' show RecordingHistory;
import '../support/drift_repos.dart';
import '../support/shop_seed.dart';
import 'support/fake_odoo.dart';

/// What the app's cookie jar does for the sender: keeps the session cookie of a login and sends it along.
final class _Jar implements ApiClient {
  final ApiClient inner;
  String? cookie;
  _Jar(this.inner);

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    final headers = {...spec.headers, if (cookie != null && !spec.headers.containsKey('Cookie')) 'Cookie': cookie!};
    final r = await inner.send(ApiRequestSpec(method: spec.method, url: spec.url, headers: headers, body: spec.body, options: spec.options));
    for (final c in r.setCookies) {
      final m = RegExp(r'^session_id=([^;]+)').firstMatch(c);
      if (m != null) cookie = 'session_id=${m[1]}';
    }
    return r;
  }
}

final class _World {
  final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
  late final DriftRepos repos = DriftRepos(db);
  final FakeOdoo odoo = FakeOdoo();
  late final _Jar jar = _Jar(odoo);
  final RecordingHistory history = RecordingHistory();

  late final resolver = BuildVariableResolverUseCase(repos.collectionVariableRepository, repos.environmentRepository, repos.globalVariableRepository, repos.defaultsRepository);
  late final defaults = ResolveRequestDefaultsUseCase(repos.defaultsRepository);
  late final scripts = RunRequestScriptsUseCase(repos.scriptsRepository, resolver, repos.environmentRepository, repos.globalVariableRepository, const AssertionEvaluator(), defaults);
  late final relogin = ReloginUseCase(repos.requestRepository, repos.collectionAuthRepository, scripts, collections: repos.collectionRepository, defaults: defaults);

  SendRequestUseCase sender({bool lookups = true}) => SendRequestUseCase(
        jar,
        resolver,
        history,
        repos.collectionAuthRepository,
        null,
        null,
        const RequestSpecBuilder(),
        defaults,
        null,
        relogin,
        lookups ? OdooSmartReferenceResolver(odoo) : null,
      );

  Future<void> environment(Map<String, String> variables) async {
    final id = await repos.environmentRepository.create('Odoo');
    for (final e in variables.entries) {
      await repos.environmentRepository.upsertVariable(EnvironmentVariableEntity(id: 0, environmentId: id, key: e.key, value: e.value, isSecret: e.key.toLowerCase().contains('key'), enabled: true));
    }
    await repos.environmentRepository.setActive(id);
  }

  Future<ApiRequestEntity> post(int collection, String name, String url, String body, {List<KeyValueItem> headers = const []}) async {
    final id = await addRequest(
      repos,
      collection,
      name,
      method: HttpMethod.post,
      url: url,
      headers: headers,
      body: RequestBody(type: BodyType.raw, rawText: body),
      auth: const RequestAuth(type: AuthType.none),
    );
    return (await repos.requestRepository.findById(id))!;
  }

  List<KeyValueItem> get json2Headers => [
        KeyValueItem(key: 'Authorization', value: 'bearer {{odooApiKey}}'),
        KeyValueItem(key: 'X-Odoo-Database', value: '{{odooDb}}'),
        KeyValueItem(key: 'Content-Type', value: 'application/json'),
      ];

  Map<String, String> get json2Environment => {'odooUrl': odoo.host, 'odooDb': odoo.db, 'odooApiKey': odoo.apiKey};

  Future<void> close() => db.close();
}

String _bodyOf(ApiRequestSpec spec) => utf8.decode(spec.body as List<int>);

void main() {
  late _World world;
  late int collection;

  setUp(() async {
    world = _World();
    collection = await world.repos.collectionRepository.createCollection('Odoo');
  });
  tearDown(() => world.close());

  group('{{xmlid:...}} and {{ref:...}} in a request that is sent', () {
    test('the ids are looked up on the server the request goes to and the body carries numbers', () async {
      await world.environment(world.json2Environment);
      final request = await world.post(
        collection,
        'Create partner',
        '{{odooUrl}}/json/2/res.partner/create',
        '{"vals_list": [{"name": "X", "parent_id": {{xmlid:base.main_partner}}, "country_id": {{ref:res.country:BD}}}]}',
        headers: world.json2Headers,
      );

      final response = await world.sender()(request);

      expect(response.statusCode, 200);
      final create = world.odoo.requests.last;
      expect(create.url, 'https://odoo.test/json/2/res.partner/create');
      expect(jsonDecode(_bodyOf(create)), {
        'vals_list': [
          {'name': 'X', 'parent_id': 1, 'country_id': 20},
        ],
      });
      expect(world.odoo.records['res.partner']!.last, containsPair('parent_id', 1));
      expect(world.odoo.records['res.partner']!.last, containsPair('country_id', 20));
      expect(jsonDecode(utf8.decode(response.bodyBytes)), [5]);
      expect(world.odoo.calls, ['ir.model.data.search_read', 'res.country.name_search', 'res.partner.create']);
    });

    test('History keeps the request as written, with its tokens, never the ids', () async {
      await world.environment(world.json2Environment);
      final request = await world.post(collection, 'Create', '{{odooUrl}}/json/2/res.partner/create', '{"vals_list": [{"name": "X", "parent_id": {{xmlid:base.main_partner}}}]}', headers: world.json2Headers);

      await world.sender()(request);

      expect(world.history.calls.single.url, '{{odooUrl}}/json/2/res.partner/create');
    });

    test('a token that cannot be resolved stops the request: the literal is never sent', () async {
      await world.environment(world.json2Environment);
      final request = await world.post(collection, 'Create', '{{odooUrl}}/json/2/res.partner/create', '{"vals_list": [{"name": "X", "parent_id": {{xmlid:base.nope}}}]}', headers: world.json2Headers);

      await expectLater(
        world.sender()(request),
        throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', allOf(startsWith('XML-ID base.nope not found on https://odoo.test'), endsWith('The request was not sent.')))),
      );
      expect(world.odoo.writes, isEmpty);
      expect(world.odoo.requests.where((r) => r.body is List<int> && _bodyOf(r).contains('{{')), isEmpty);
      expect(world.odoo.requests.where((r) => r.url.endsWith('/create')), isEmpty);
    });

    test('without a lookup wired the request is refused instead of sending the token', () async {
      await world.environment(world.json2Environment);
      final request = await world.post(collection, 'Create', '{{odooUrl}}/json/2/res.partner/create', '{"vals_list": [{"name": "X", "parent_id": {{xmlid:base.main_partner}}}]}', headers: world.json2Headers);

      await expectLater(
        world.sender(lookups: false)(request),
        throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', allOf(contains('{{xmlid:base.main_partner}}'), contains('no lookup is available'), contains('was not sent')))),
      );
      expect(world.odoo.requests, isEmpty);
    });

    test('a missing ordinary variable is reported first, and nothing is looked up for a request that cannot go out', () async {
      await world.environment(world.json2Environment);
      final request = await world.post(collection, 'Create', '{{odooUrl}}/json/2/res.partner/create', '{"vals_list": [{"name": "{{customerName}}", "parent_id": {{xmlid:base.main_partner}}}]}', headers: world.json2Headers);

      await expectLater(world.sender()(request), throwsA(isA<InvalidRequestException>().having((e) => e.message, 'message', contains('{{customerName}}'))));
      expect(world.odoo.requests, isEmpty);
    });

    test('a variable that holds a token makes the same request portable between environments', () async {
      await world.environment({...world.json2Environment, 'companyId': '{{xmlid:base.main_partner}}'});
      final request = await world.post(collection, 'Create', '{{odooUrl}}/json/2/res.partner/create', '{"vals_list": [{"name": "E", "parent_id": {{companyId}}}]}', headers: world.json2Headers);

      await world.sender()(request);

      expect(jsonDecode(_bodyOf(world.odoo.requests.last)), {
        'vals_list': [
          {'name': 'E', 'parent_id': 1},
        ],
      });
    });

    test('a request without tokens costs no lookup at all', () async {
      await world.environment(world.json2Environment);
      final request = await world.post(collection, 'Count', '{{odooUrl}}/json/2/res.partner/search_count', '{"domain": []}', headers: world.json2Headers);

      final response = await world.sender()(request);

      expect(jsonDecode(utf8.decode(response.bodyBytes)), 4);
      expect(world.odoo.calls, ['res.partner.search_count']);
    });

    test('with Odoo 18 the lookups log in with the environment\'s login and password', () async {
      await world.environment({'odooUrl': world.odoo.host, 'odooDb': world.odoo.db, 'odooLogin': world.odoo.login, 'odooPassword': world.odoo.password});
      final request = await world.post(
        collection,
        'Update',
        '{{odooUrl}}/web/dataset/call_kw/res.partner/write',
        '{"jsonrpc": "2.0", "method": "call", "params": {"model": "res.partner", "method": "write", "args": [[3], {"parent_id": {{xmlid:base.main_partner}}}], "kwargs": {}}}',
      );
      // The login request of the collection opens the session the write itself uses.
      final login = await world.post(collection, 'Log in', '{{odooUrl}}/web/session/authenticate', '{"jsonrpc": "2.0", "method": "call", "params": {"db": "{{odooDb}}", "login": "{{odooLogin}}", "password": "{{odooPassword}}"}}');
      final send = world.sender();
      expect((await send(login)).statusCode, 200);

      final response = await send(request);

      expect(jsonDecode(utf8.decode(response.bodyBytes))['result'], true);
      expect(world.odoo.records['res.partner']!.firstWhere((r) => r['id'] == 3)['parent_id'], 1);
      expect(world.odoo.authenticateCount, 2, reason: 'the login request, and the lookup that has the credentials of the environment');
    });
  });

  group('an Odoo 18 session that expires', () {
    late ApiRequestEntity login;
    late ApiRequestEntity list;
    const countBody = '{"jsonrpc": "2.0", "method": "call", "params": {"model": "res.partner", "method": "search_count", "args": [[]], "kwargs": {}}}';
    const countPath = '/web/dataset/call_kw/res.partner/search_count';

    Future<void> setUpCollection({required bool relogin}) async {
      await world.environment({'odooUrl': world.odoo.host, 'odooDb': world.odoo.db, 'odooLogin': world.odoo.login, 'odooPassword': world.odoo.password});
      login = await world.post(collection, 'Log in', '{{odooUrl}}/web/session/authenticate', '{"jsonrpc": "2.0", "method": "call", "params": {"db": "{{odooDb}}", "login": "{{odooLogin}}", "password": "{{odooPassword}}"}}');
      list = await world.post(collection, 'Count partners', '{{odooUrl}}$countPath', countBody);
      if (relogin) {
        await world.repos.collectionAuthRepository.setAuthJson(
          collection,
          const RequestAuth(type: AuthType.none).withRelogin(const ReloginConfig(request: 'Log in')).toJsonString(),
        );
      }
    }

    List<String> pathsSince(int before) => [for (final r in world.odoo.requests.skip(before)) Uri.parse(r.url).path];

    test("with the collection's re-login set, the Log in request runs and the call is sent again, once", () async {
      await setUpCollection(relogin: true);
      final send = world.sender();
      expect((await send(login)).statusCode, 200);
      expect(jsonDecode(utf8.decode((await send(list)).bodyBytes))['result'], 4);
      world.odoo.expireSessions();
      final before = world.odoo.requests.length;

      final response = await send(list);

      expect(response.statusCode, 200);
      expect(jsonDecode(utf8.decode(response.bodyBytes))['result'], 4);
      expect(pathsSince(before), [countPath, '/web/session/authenticate', countPath], reason: 'the call Odoo found expired, the login, the one retry');
      expect(world.odoo.authenticateCount, 2);
      expect(response.authNotes.single, startsWith('Re-authenticated via "Log in" and retried'));
    });

    test('without it the answer Odoo gave is returned untouched: still a 200 with the expiry in the body', () async {
      await setUpCollection(relogin: false);
      final send = world.sender();
      await send(login);
      world.odoo.expireSessions();

      final response = await send(list);

      expect(response.statusCode, 200, reason: 'the 401 that starts a re-login is never what the person is shown');
      expect(utf8.decode(response.bodyBytes), contains('SessionExpiredException'));
      expect(response.authNotes, isEmpty);
      expect(world.odoo.authenticateCount, 1);
    });

    test('a re-login that does not open a lasting session does not loop: one login, one retry, then the answer stands', () async {
      await setUpCollection(relogin: true);
      final forgetful = _Forgetful(world.odoo);
      final send = SendRequestUseCase(forgetful, world.resolver, world.history, world.repos.collectionAuthRepository, null, null, const RequestSpecBuilder(), world.defaults, null, world.relogin);

      final response = await send(list);

      expect(response.statusCode, 200);
      expect(utf8.decode(response.bodyBytes), contains('SessionExpiredException'));
      expect(pathsSince(0), [countPath, '/web/session/authenticate', countPath]);
    });
  });
}

/// Forgets every session before it answers a call_kw.
final class _Forgetful implements ApiClient {
  final FakeOdoo inner;
  String? cookie;
  _Forgetful(this.inner);

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    if (spec.url.contains('/call_kw/')) inner.expireSessions();
    final headers = {...spec.headers, 'Cookie': ?cookie};
    final r = await inner.send(ApiRequestSpec(method: spec.method, url: spec.url, headers: headers, body: spec.body, options: spec.options));
    for (final c in r.setCookies) {
      final m = RegExp(r'^session_id=([^;]+)').firstMatch(c);
      if (m != null) cookie = 'session_id=${m[1]}';
    }
    return r;
  }
}
