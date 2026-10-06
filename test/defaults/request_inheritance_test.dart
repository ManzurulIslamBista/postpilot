// What a request is sent with once the collection and its folders pass headers, auth and variables down.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/code_generator.dart';
import 'package:postpilot/features/request_builder/domain/services/request_spec_builder.dart';
import 'package:postpilot/features/request_builder/domain/services/resolved_request_spec.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/prepare_request_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/send_request_usecase.dart';

import '../support/drift_repos.dart';
import '../support/shop_seed.dart';

KeyValueItem _h(String key, String value, {bool enabled = true}) => KeyValueItem(key: key, value: value, enabled: enabled);

const _bearer = AuthType.bearer;

void main() {
  late AppDatabase db;
  late DriftRepos repos;
  late int shop;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    shop = await repos.collectionRepository.createCollection('Shop');
  });
  tearDown(() => db.close());

  BuildVariableResolverUseCase buildResolver() => BuildVariableResolverUseCase(
        repos.collectionVariableRepository,
        repos.environmentRepository,
        repos.globalVariableRepository,
        repos.defaultsRepository,
      );

  ResolveRequestDefaultsUseCase defaults() => ResolveRequestDefaultsUseCase(repos.defaultsRepository);

  PrepareRequestUseCase prepare() => PrepareRequestUseCase(buildResolver(), repos.collectionAuthRepository, defaults: defaults());

  Future<int> folder(String name, {int? parent}) =>
      repos.collectionRepository.createFolder(collectionId: shop, parentFolderId: parent, name: name);

  Future<ApiRequestEntity> request(
    String name, {
    int? folderId,
    String url = 'https://shop.test/items',
    List<KeyValueItem> headers = const [],
    RequestAuth auth = const RequestAuth(type: AuthType.inherit),
  }) async {
    final id = await addRequest(repos, shop, name, folderId: folderId, url: url, headers: headers, auth: auth);
    return (await repos.requestRepository.findById(id))!;
  }

  Future<PreparedRequest> prepared(ApiRequestEntity request) => prepare()(request);

  Future<void> setCollectionAuth(RequestAuth auth) =>
      repos.collectionAuthRepository.setAuthJson(shop, auth.toJsonString());

  group('headers', () {
    test('the collection\'s, then the folders\' outermost first, then the request\'s own, a same-named one from a more specific level replacing it', () async {
      final a = await folder('A');
      final b = await folder('B', parent: a);
      await repos.defaultsRepository.saveCollection(
        shop,
        LevelDefaults(headers: [_h('X-Api-Version', '1'), _h('Accept-Language', 'en')]),
      );
      await repos.defaultsRepository.saveFolder(a, LevelDefaults(headers: [_h('x-api-version', '2')]));
      await repos.defaultsRepository.saveFolder(b, LevelDefaults(headers: [_h('X-Folder-B', 'b')]));
      final r = await request('Get', folderId: b, headers: [_h('X-Own', 'own')]);

      final headers = (await prepared(r)).spec.headers;

      expect(headers.entries.map((e) => '${e.key}: ${e.value}').toList(), [
        'Accept-Language: en',
        'x-api-version: 2',
        'X-Folder-B: b',
        'X-Own: own',
      ]);
    });

    test('the request\'s own header with the same name wins whatever its letter case', () async {
      await repos.defaultsRepository.saveCollection(shop, LevelDefaults(headers: [_h('Accept-Language', 'en')]));
      final r = await request('Get', headers: [_h('ACCEPT-LANGUAGE', 'bn')]);

      expect((await prepared(r)).spec.headers, {'ACCEPT-LANGUAGE': 'bn'});
    });

    test('a header switched off at an inner level is not sent below it, and is still sent elsewhere', () async {
      final a = await folder('A');
      final off = await folder('Off', parent: a);
      final on = await folder('On', parent: a);
      await repos.defaultsRepository.saveCollection(shop, LevelDefaults(headers: [_h('X-Tenant', 'acme')]));
      await repos.defaultsRepository.saveFolder(off, LevelDefaults(headers: [_h('x-tenant', '', enabled: false)]));

      expect((await prepared(await request('In off', folderId: off))).spec.headers, isEmpty);
      expect((await prepared(await request('In on', folderId: on))).spec.headers, {'X-Tenant': 'acme'});
      expect((await prepared(await request('Top'))).spec.headers, {'X-Tenant': 'acme'});
    });

    test('a request switches an inherited header off with a disabled row of the same name', () async {
      await repos.defaultsRepository.saveCollection(shop, LevelDefaults(headers: [_h('X-Tenant', 'acme'), _h('X-Keep', 'k')]));
      final r = await request('Get', headers: [_h('X-TENANT', 'ignored', enabled: false)]);

      expect((await prepared(r)).spec.headers, {'X-Keep': 'k'});
    });

    test('a disabled default header is ignored', () async {
      await repos.defaultsRepository.saveCollection(shop, LevelDefaults(headers: [_h('X-Off', '1', enabled: false)]));
      expect((await prepared(await request('Get'))).spec.headers, isEmpty);
    });

    test('{{variables}} in an inherited header resolve like in the request\'s own, and are checked for being defined', () async {
      final a = await folder('A');
      await repos.defaultsRepository.saveCollection(shop, LevelDefaults(headers: [_h('X-Region', '{{region}}')]));
      await repos.defaultsRepository.saveFolder(a, LevelDefaults(variables: [DefaultVariable(key: 'region', value: 'eu')]));

      final inFolder = await prepared(await request('In', folderId: a));
      expect(inFolder.spec.headers, {'X-Region': 'eu'});
      expect(inFolder.undefinedVariables, isEmpty);

      final outside = await prepared(await request('Out'));
      expect(outside.spec.headers, {'X-Region': '{{region}}'});
      expect(outside.undefinedVariables.map((u) => u.name), ['region']);
    });

    test('a collection with no defaults at all prepares exactly what it did before they existed', () async {
      final r = await request('Get', headers: [_h('X-Own', '1')], url: 'shop.test/items?x=1');
      final before = const RequestSpecBuilder().build(r, await buildResolver()(shop));

      final spec = (await prepared(r)).spec;

      expect(spec.headers, before.headers);
      expect(spec.url, before.url);
      expect(spec.method, before.method);
    });
  });

  group('auth', () {
    test('a request that inherits takes the nearest folder\'s auth, else the collection\'s', () async {
      final parent = await folder('Parent');
      final child = await folder('Child', parent: parent);
      await setCollectionAuth(const RequestAuth(type: _bearer, bearerToken: 'collection-token'));
      await repos.defaultsRepository.saveFolder(parent, const LevelDefaults(auth: RequestAuth(type: _bearer, bearerToken: 'parent-token')));

      // The child folder is set to "Inherit from parent": it sets no auth of its own.
      expect((await prepared(await request('In child', folderId: child))).spec.headers['Authorization'], 'Bearer parent-token');
      expect((await prepared(await request('In parent', folderId: parent))).spec.headers['Authorization'], 'Bearer parent-token');
      expect((await prepared(await request('Top'))).spec.headers['Authorization'], 'Bearer collection-token');
    });

    test('a folder\'s No Auth switches the inherited auth off for everything in it', () async {
      final public = await folder('Public');
      final inner = await folder('Inner', parent: public);
      await setCollectionAuth(const RequestAuth(type: _bearer, bearerToken: 'collection-token'));
      await repos.defaultsRepository.saveFolder(public, const LevelDefaults(auth: RequestAuth(type: AuthType.none)));

      final sent = await prepared(await request('In inner', folderId: inner));

      expect(sent.spec.headers, isNot(contains('Authorization')));
      expect(sent.auth.type, AuthType.none);
    });

    test('a request with an auth of its own is not touched by the folders', () async {
      final a = await folder('A');
      await repos.defaultsRepository.saveFolder(a, const LevelDefaults(auth: RequestAuth(type: _bearer, bearerToken: 'folder-token')));

      final own = await request('Own', folderId: a, auth: const RequestAuth(type: _bearer, bearerToken: 'own-token'));
      final none = await request('None', folderId: a, auth: const RequestAuth(type: AuthType.none));

      expect((await prepared(own)).spec.headers['Authorization'], 'Bearer own-token');
      expect((await prepared(none)).spec.headers, isNot(contains('Authorization')));
    });

    test('the auth in force is reported with the folder\'s credentials, for Digest and the like', () async {
      final a = await folder('A');
      await repos.defaultsRepository.saveFolder(
        a,
        const LevelDefaults(auth: RequestAuth(type: AuthType.digest, basicUsername: 'ann', basicPassword: 'pw')),
      );

      final sent = await prepared(await request('Get', folderId: a));

      expect(sent.auth.type, AuthType.digest);
      expect(sent.auth.basicUsername, 'ann');
    });

    test('an auth header of the folder\'s auth beats a default Authorization header, as the request\'s own auth would', () async {
      final a = await folder('A');
      await repos.defaultsRepository.saveCollection(shop, LevelDefaults(headers: [_h('Authorization', 'Basic stale')]));
      await repos.defaultsRepository.saveFolder(a, const LevelDefaults(auth: RequestAuth(type: _bearer, bearerToken: 'fresh')));

      expect((await prepared(await request('Get', folderId: a))).spec.headers['Authorization'], 'Bearer fresh');
    });
  });

  group('variables', () {
    Future<String> value(String name, {int? folderId, Map<String, String> data = const {}}) async =>
        (await buildResolver()(shop, folderId: folderId, dataVariables: data)).resolve('{{$name}}');

    test('precedence: data row, active environment, folders (innermost first), collection, globals', () async {
      final outer = await folder('Outer');
      final inner = await folder('Inner', parent: outer);
      await repos.globalVariableRepository.upsert(GlobalVariableEntity(id: 0, key: 'v', value: 'global', isSecret: false, enabled: true));
      expect(await value('v', folderId: inner), 'global');

      await repos.collectionVariableRepository
          .upsert(CollectionVariableEntity(id: 0, collectionId: shop, key: 'v', value: 'collection', enabled: true));
      expect(await value('v', folderId: inner), 'collection');

      await repos.defaultsRepository.saveFolder(outer, LevelDefaults(variables: [DefaultVariable(key: 'v', value: 'outer')]));
      expect(await value('v', folderId: inner), 'outer');
      expect(await value('v'), 'collection', reason: 'a request outside the folders does not see their variables');

      await repos.defaultsRepository.saveFolder(inner, LevelDefaults(variables: [DefaultVariable(key: 'v', value: 'inner')]));
      expect(await value('v', folderId: inner), 'inner');
      expect(await value('v', folderId: outer), 'outer');

      final env = await repos.environmentRepository.create('Dev');
      await repos.environmentRepository
          .upsertVariable(EnvironmentVariableEntity(id: 0, environmentId: env, key: 'v', value: 'environment', isSecret: false, enabled: true));
      await repos.environmentRepository.setActive(env);
      expect(await value('v', folderId: inner), 'environment', reason: 'the environment beats the folders');

      expect(await value('v', folderId: inner, data: {'v': 'data'}), 'data');
    });

    test('a disabled folder variable is not visible and does not hide the one above it', () async {
      final outer = await folder('Outer');
      final inner = await folder('Inner', parent: outer);
      await repos.defaultsRepository.saveFolder(outer, LevelDefaults(variables: [DefaultVariable(key: 'v', value: 'outer')]));
      await repos.defaultsRepository.saveFolder(inner, LevelDefaults(variables: [DefaultVariable(key: 'v', value: 'inner', enabled: false)]));

      expect(await value('v', folderId: inner), 'outer');
    });

    test('a folder variable may reference another scope\'s variable', () async {
      final a = await folder('A');
      await repos.collectionVariableRepository
          .upsert(CollectionVariableEntity(id: 0, collectionId: shop, key: 'host', value: 'shop.test', enabled: true));
      await repos.defaultsRepository.saveFolder(a, LevelDefaults(variables: [DefaultVariable(key: 'base', value: 'https://{{host}}/v2')]));

      expect(await value('base', folderId: a), 'https://shop.test/v2');
    });

    test('a secret folder variable is used in the request like any other, and never appears in an undefined list', () async {
      final a = await folder('A');
      await repos.defaultsRepository.saveFolder(
        a,
        LevelDefaults(variables: [DefaultVariable(key: 'tenantKey', value: 'k-123', isSecret: true)]),
      );
      final r = await request('Get', folderId: a, headers: [_h('X-Tenant-Key', '{{tenantKey}}')]);

      final sent = await prepared(r);

      expect(sent.spec.headers, {'X-Tenant-Key': 'k-123'});
      expect(sent.undefinedVariables, isEmpty);
    });
  });

  group('a request moved between folders', () {
    test('what it is sent with follows its folder, also when the open tab still holds the old one', () async {
      final a = await folder('A');
      final b = await folder('B');
      await repos.defaultsRepository.saveFolder(a, LevelDefaults(headers: [_h('X-From', 'A')], auth: const RequestAuth(type: _bearer, bearerToken: 'a-token')));
      await repos.defaultsRepository.saveFolder(b, LevelDefaults(headers: [_h('X-From', 'B')]));
      final tab = await request('Get', folderId: a);
      expect((await prepared(tab)).spec.headers, {'X-From': 'A', 'Authorization': 'Bearer a-token'});

      await db.requestsDao.updateRequest(tab.id, RequestsCompanion(folderId: Value(b)));

      expect((await prepared(tab)).spec.headers, {'X-From': 'B'});
    });
  });

  group('the snippet is what is sent', () {
    test('headers, auth and variables inherited from folders and the collection are in both, byte for byte', () async {
      final a = await folder('A');
      final b = await folder('B', parent: a);
      await repos.defaultsRepository.saveCollection(shop, LevelDefaults(headers: [_h('Accept-Language', 'en'), _h('X-Gone', '1')]));
      await repos.defaultsRepository.saveFolder(
        a,
        LevelDefaults(
          headers: [_h('X-Region', '{{region}}')],
          variables: [DefaultVariable(key: 'region', value: 'eu')],
          auth: const RequestAuth(type: _bearer, bearerToken: 'folder-token'),
        ),
      );
      await repos.defaultsRepository.saveFolder(b, LevelDefaults(headers: [_h('x-gone', '', enabled: false)]));
      final r = await request('Get', folderId: b, headers: [_h('X-Own', '1')]);

      final client = _RecordingApiClient();
      await SendRequestUseCase(client, buildResolver(), _NoHistory(), repos.collectionAuthRepository, null, null, const RequestSpecBuilder(), defaults())(r);
      final generator = _CapturingGenerator();
      await GenerateCodeSnippetUseCase(buildResolver(), repos.collectionAuthRepository, defaults: defaults())(
        GenerateCodeSnippetParams(r, generator),
      );

      expect(client.sent.single.headers, {
        'Accept-Language': 'en',
        'X-Region': 'eu',
        'X-Own': '1',
        'Authorization': 'Bearer folder-token',
      });
      expect(generator.spec!.headers, client.sent.single.headers);
      expect(generator.spec!.url, client.sent.single.url);
      expect(generator.spec!.bodyBytes, client.sent.single.body);
    });

    test('sending still refuses a {{variable}} no scope defines, naming the inherited header it is in', () async {
      await repos.defaultsRepository.saveCollection(shop, LevelDefaults(headers: [_h('X-Region', '{{region}}')]));
      final r = await request('Get');
      final send = SendRequestUseCase(_RecordingApiClient(), buildResolver(), _NoHistory(), repos.collectionAuthRepository, null, null,
          const RequestSpecBuilder(), defaults());

      await expectLater(
        send(r),
        throwsA(predicate((e) => e.toString().contains('region') && e.toString().contains('X-Region'))),
      );
    });
  });
}

final class _CapturingGenerator implements CodeGenerator {
  ResolvedRequestSpec? spec;

  @override
  String get id => 'capture';

  @override
  String get label => 'Capture';

  @override
  String generate(ResolvedRequestSpec spec) {
    this.spec = spec;
    return '';
  }
}

final class _RecordingApiClient implements ApiClient {
  final List<ApiRequestSpec> sent = [];

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    sent.add(spec);
    return const ApiHttpResponse(statusCode: 200, statusMessage: 'OK', headers: {}, bodyBytes: [], duration: Duration.zero);
  }
}

final class _NoHistory implements HistoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
