// Postman has `auth`, `variable` and `event` on collections and folders: they become defaults here, and go back there.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/defaults/domain/services/defaults_resolver.dart';
import 'package:postpilot/features/import_export/domain/usecases/export_postman_collection_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_postman_collection_usecase.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_exporter.dart';
import 'package:postpilot/features/request_builder/domain/services/importers/postman_collection_parser.dart';

import '../support/drift_repos.dart';
import '../support/shop_seed.dart';

Map<String, Object?> _tests(List<String> lines) => {
      'event': [
        {
          'listen': 'test',
          'script': {'type': 'text/javascript', 'exec': lines},
        },
      ],
    };

Map<String, Object?> _bearer(String token) => {
      'type': 'bearer',
      'bearer': [
        {'key': 'token', 'value': token},
      ],
    };

final _collection = jsonEncode({
  'info': {'name': 'Shop', 'schema': 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json'},
  'auth': _bearer('collection-token'),
  'variable': [
    {'key': 'baseUrl', 'value': 'https://shop.test'},
  ],
  ..._tests(['pm.test("ok", function () { pm.response.to.have.status(200); });']),
  'item': [
    {
      'name': 'Orders',
      'auth': _bearer('orders-token'),
      'variable': [
        {'key': 'region', 'value': 'eu'},
        {'key': 'apiKey', 'value': 'k-1', 'type': 'secret'},
        {'key': 'old', 'value': 'x', 'disabled': true},
      ],
      ..._tests(['pm.test("created", function () { pm.response.to.have.status(201); });']),
      'item': [
        {
          'name': 'Public',
          'auth': {'type': 'noauth'},
          'item': [
            {
              'name': 'Health',
              'request': {'method': 'GET', 'url': {'raw': '{{baseUrl}}/health'}},
            },
          ],
        },
        {
          'name': 'Create order',
          'request': {'method': 'POST', 'url': {'raw': '{{baseUrl}}/orders'}},
        },
        {
          'name': 'Own auth',
          'request': {'method': 'GET', 'url': {'raw': '{{baseUrl}}/mine'}, 'auth': _bearer('own-token')},
          ..._tests(['pm.test("own", function () { pm.response.to.have.status(200); });']),
        },
      ],
    },
  ],
});

void main() {
  group('import', () {
    test('the parser keeps a folder\'s auth, variables and tests on the folder and the collection\'s on the collection', () {
      final parsed = PostmanCollectionParser.parse(_collection);

      expect(parsed.auth?.bearerToken, 'collection-token');
      expect(parsed.variables.map((v) => v.key), ['baseUrl'], reason: 'a folder\'s variables no longer join the collection\'s');
      expect(parsed.assertions.single.expected, '200');
      final orders = parsed.items.single as PostmanFolderItem;
      expect(orders.auth?.bearerToken, 'orders-token');
      expect(orders.variables, [
        DefaultVariable(key: 'region', value: 'eu'),
        DefaultVariable(key: 'apiKey', value: 'k-1', isSecret: true),
        DefaultVariable(key: 'old', value: 'x', enabled: false),
      ]);
      expect(orders.assertions.single.expected, '201');
      final public = orders.children.whereType<PostmanFolderItem>().single;
      expect(public.auth?.type, AuthType.none, reason: 'noauth is a setting, not "inherit"');
      expect(public.variables, isEmpty);
    });

    test('a request keeps only what it has itself: its tests and its auth, "inherit" when it has none', () {
      final parsed = PostmanCollectionParser.parse(_collection);
      final requests = [
        for (final item in (parsed.items.single as PostmanFolderItem).children)
          if (item is PostmanRequestItem) item,
      ];

      final create = requests.firstWhere((r) => r.name == 'Create order');
      final own = requests.firstWhere((r) => r.name == 'Own auth');
      expect(create.auth.type, AuthType.inherit);
      expect(create.assertions, isEmpty, reason: 'the folder\'s and the collection\'s tests are theirs, not copied down');
      expect(own.auth.bearerToken, 'own-token');
      expect(own.assertions.single.expected, '200');
    });

    test('the counts include the folders\' and the collection\'s tests', () {
      final parsed = PostmanCollectionParser.parse(_collection);

      expect(parsed.assertionCount, 3, reason: 'one on the collection, one on Orders, one on the request "Own auth"');
    });

    test('the use case stores them as the collection\'s and the folders\' defaults, and requests inherit as in Postman', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repos = DriftRepos(db);
      final useCase = ImportPostmanCollectionUseCase(
        repos.collectionRepository,
        repos.requestRepository,
        repos.collectionVariableRepository,
        repos.collectionAuthRepository,
        repos.scriptsRepository,
        repos.defaultsRepository,
      );

      final summary = await useCase.importWithSummary(_collection);

      final id = summary.collectionIds.single;
      final tree = await repos.defaultsRepository.loadTree(id);
      final folders = {for (final f in tree.folders) f.name: f};
      expect(tree.collection.assertions.single.expected, '200');
      expect(tree.collection.auth?.bearerToken, 'collection-token');
      final orders = tree.folderDefaults[folders['Orders']!.id]!;
      expect(orders.auth?.bearerToken, 'orders-token');
      expect(orders.variables.map((v) => (v.key, v.isSecret, v.enabled)), [('region', false, true), ('apiKey', true, true), ('old', false, false)]);
      expect(orders.assertions.single.expected, '201');
      expect(tree.folderDefaults[folders['Public']!.id]!.auth?.type, AuthType.none);
      expect(await repos.collectionVariableRepository.getEnabledMap(id), {'baseUrl': 'https://shop.test'});

      // A request in Public inherits "No Auth" from its folder; one in Orders the folder's bearer.
      final health = (await repos.requestRepository.watchByCollection(id).first).firstWhere((r) => r.name == 'Health');
      final create = (await repos.requestRepository.watchByCollection(id).first).firstWhere((r) => r.name == 'Create order');
      expect(DefaultsResolver.resolve(tree.chainFor(health.folderId)).auth?.type, AuthType.none);
      expect(DefaultsResolver.resolve(tree.chainFor(create.folderId)).auth?.bearerToken, 'orders-token');
      expect(summary.notes.join('\n'), contains('3 checks'));
    });

    test('without a defaults store they are left out, and the summary says so', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repos = DriftRepos(db);
      final useCase = ImportPostmanCollectionUseCase(
        repos.collectionRepository,
        repos.requestRepository,
        repos.collectionVariableRepository,
        repos.collectionAuthRepository,
        repos.scriptsRepository,
      );

      final summary = await useCase.importWithSummary(_collection);

      expect(summary.notes.join('\n'), contains('were not imported'));
      expect((await db.customSelect('SELECT COUNT(*) AS n FROM folder_defaults').getSingle()).read<int>('n'), 0);
    });
  });

  group('export', () {
    late AppDatabase db;
    late DriftRepos repos;
    late int shop;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repos = DriftRepos(db);
      shop = await repos.collectionRepository.createCollection('Shop');
    });
    tearDown(() => db.close());

    Future<String> export({bool redact = false}) async {
      final json = await ExportPostmanCollectionUseCase(
        repos.collectionRepository,
        repos.requestRepository,
        repos.collectionVariableRepository,
        repos.collectionAuthRepository,
        repos.defaultsRepository,
      )(shop);
      return redact ? PostmanCollectionExporter.redact(json) : json;
    }

    Future<void> seed() async {
      final orders = await repos.collectionRepository.createFolder(collectionId: shop, name: 'Orders');
      final inner = await repos.collectionRepository.createFolder(collectionId: shop, parentFolderId: orders, name: 'Inner');
      await repos.defaultsRepository.saveCollection(
        shop,
        LevelDefaults(headers: [KeyValueItem(key: 'X-Tenant', value: 'acme'), KeyValueItem(key: 'Accept-Language', value: 'en')]),
      );
      await repos.defaultsRepository.saveFolder(
        orders,
        LevelDefaults(
          headers: [KeyValueItem(key: 'x-api-version', value: '2'), KeyValueItem(key: 'Accept-Language', value: '', enabled: false)],
          variables: [DefaultVariable(key: 'region', value: 'eu'), DefaultVariable(key: 'tenantKey', value: 'folder-secret', isSecret: true)],
          auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'orders-bearer-token'),
        ),
      );
      await addRequest(repos, shop, 'List', folderId: inner, headers: [KeyValueItem(key: 'X-Own', value: '1')]);
      await addRequest(repos, shop, 'Top', headers: [KeyValueItem(key: 'x-tenant', value: 'override')]);
    }

    Map<String, dynamic> find(Map<String, dynamic> root, String name) {
      Map<String, dynamic>? walk(List items) {
        for (final item in items.cast<Map<String, dynamic>>()) {
          if (item['name'] == name) return item;
          final inside = item['item'];
          if (inside is List) {
            final found = walk(inside);
            if (found != null) return found;
          }
        }
        return null;
      }

      return walk(root['item'] as List)!;
    }

    test('a folder\'s auth and variables are written on the folder, where Postman has them', () async {
      await seed();

      final orders = find(jsonDecode(await export()) as Map<String, dynamic>, 'Orders');

      expect(orders['auth']['type'], 'bearer');
      expect((orders['auth']['bearer'] as List).single['value'], 'orders-bearer-token');
      expect((orders['variable'] as List).map((v) => '${v['key']}:${v['type']}'), ['region:null', 'tenantKey:secret']);
    });

    test('the headers a request inherits are written into it, minus the ones it overrides or a folder switched off', () async {
      await seed();
      final root = jsonDecode(await export()) as Map<String, dynamic>;

      List<String> headersOf(String request) =>
          [for (final h in find(root, request)['request']['header'] as List) '${h['key']}=${h['value']}${h['disabled'] == true ? ' (off)' : ''}'];

      // List: collection X-Tenant; Orders replaces nothing of it but switches Accept-Language off and adds x-api-version.
      expect(headersOf('List'), ['X-Tenant=acme', 'x-api-version=2', 'X-Own=1']);
      // Top: the request's own x-tenant replaces the collection's X-Tenant, Accept-Language is still inherited.
      expect(headersOf('Top'), ['Accept-Language=en', 'x-tenant=override']);
    });

    test('a request that inherits writes no auth of its own, so Postman inherits the folder\'s', () async {
      await seed();

      final list = find(jsonDecode(await export()) as Map<String, dynamic>, 'List');

      expect((list['request'] as Map).containsKey('auth'), isFalse);
    });

    test('redacting replaces a folder\'s credentials and its secret variables', () async {
      await seed();

      final text = await export(redact: true);

      expect(text, isNot(contains('orders-bearer-token')));
      expect(text, isNot(contains('folder-secret')));
      final orders = find(jsonDecode(text) as Map<String, dynamic>, 'Orders');
      expect((orders['auth']['bearer'] as List).single['value'], '{{bearerToken}}');
      expect((orders['variable'] as List).firstWhere((v) => v['key'] == 'tenantKey')['value'], '');
      expect((orders['variable'] as List).firstWhere((v) => v['key'] == 'region')['value'], 'eu');
    });

    test('an export of a collection with no defaults is what it was before', () async {
      await addRequest(repos, shop, 'Plain', headers: [KeyValueItem(key: 'X-Own', value: '1')]);

      final root = jsonDecode(await export()) as Map<String, dynamic>;

      final plain = find(root, 'Plain');
      expect((plain['request']['header'] as List).map((h) => h['key']), ['X-Own']);
      expect(root.containsKey('variable'), isFalse);
    });

    test('exported and imported again, the folder auth and variables are back and the headers are explicit', () async {
      await seed();
      final json = await export();

      final parsed = PostmanCollectionParser.parse(json);

      final orders = parsed.items.whereType<PostmanFolderItem>().single;
      expect(orders.auth?.bearerToken, 'orders-bearer-token');
      expect(orders.variables, [DefaultVariable(key: 'region', value: 'eu'), DefaultVariable(key: 'tenantKey', value: 'folder-secret', isSecret: true)]);
      final list = ((orders.children.single as PostmanFolderItem).children.single as PostmanRequestItem);
      expect(list.headers.map((h) => h.key), ['X-Tenant', 'x-api-version', 'X-Own']);
      expect(list.auth.type, AuthType.inherit);
    });
  });
}
