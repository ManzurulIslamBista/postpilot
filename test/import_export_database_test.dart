import 'dart:convert';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/data/repositories/collection_auth_repository_impl.dart';
import 'package:postpilot/features/collections/data/repositories/collection_repository_impl.dart';
import 'package:postpilot/features/collections/data/repositories/collection_variable_repository_impl.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_auth_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_variable_repository.dart';
import 'package:postpilot/features/documentation/data/repositories/documentation_repository_impl.dart';
import 'package:postpilot/features/documentation/data/repositories/tag_repository_impl.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/documentation/domain/repositories/documentation_repository.dart';
import 'package:postpilot/features/documentation/domain/repositories/tag_repository.dart';
import 'package:postpilot/features/environments/data/repositories/environment_repository_impl.dart';
import 'package:postpilot/features/environments/data/repositories/global_variable_repository_impl.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/global_variable_repository.dart';
import 'package:postpilot/features/import_export/domain/entities/import_format.dart';
import 'package:postpilot/features/import_export/domain/usecases/export_curl_script_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/export_openapi_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_curl_script_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_har_usecase.dart';
import 'package:postpilot/features/import_export/domain/usecases/import_insomnia_usecase.dart';
import 'package:postpilot/features/request_builder/data/repositories/request_repository_impl.dart';
import 'package:postpilot/features/request_builder/data/repositories/request_scripts_repository_impl.dart';
import 'package:postpilot/features/request_builder/data/repositories/response_example_repository_impl.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_scripts_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/response_example_repository.dart';
import 'package:postpilot/features/request_builder/domain/usecases/build_variable_resolver_usecase.dart';
import 'package:postpilot/features/request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import 'package:postpilot/features/settings/data/repositories/request_settings_repository_impl.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'package:postpilot/features/settings/domain/repositories/request_settings_repository.dart';
import 'support/in_memory_import_export_fakes.dart';
import 'support/shop_seed.dart';

/// The real repositories over a real (in-memory SQLite) database, wired the
/// way the injector wires them.
final class _DriftRepositories implements RepositoryBundle {
  final AppDatabase database;
  _DriftRepositories(this.database)
      : collectionRepository = CollectionRepositoryImpl(database.collectionsDao),
        requestRepository = RequestRepositoryImpl(database.requestsDao),
        collectionVariableRepository = CollectionVariableRepositoryImpl(database.collectionVariablesDao),
        collectionAuthRepository = CollectionAuthRepositoryImpl(database.collectionAuthDao),
        scriptsRepository = RequestScriptsRepositoryImpl(database.requestScriptsDao),
        exampleRepository = ResponseExampleRepositoryImpl(database.responseExamplesDao),
        environmentRepository = EnvironmentRepositoryImpl(database.environmentsDao),
        globalVariableRepository = GlobalVariableRepositoryImpl(database.globalVariablesDao),
        requestSettingsRepository = RequestSettingsRepositoryImpl(database.requestSettingsDao),
        documentationRepository = DocumentationRepositoryImpl(database.entityDocsDao),
        tagRepository = TagRepositoryImpl(database.entityTagsDao);

  @override
  final RequestSettingsRepository requestSettingsRepository;
  @override
  final DocumentationRepository documentationRepository;
  @override
  final TagRepository tagRepository;
  @override
  final CollectionRepository collectionRepository;
  @override
  final RequestRepository requestRepository;
  @override
  final CollectionVariableRepository collectionVariableRepository;
  @override
  final CollectionAuthRepository collectionAuthRepository;
  @override
  final RequestScriptsRepository scriptsRepository;
  @override
  final ResponseExampleRepository exampleRepository;
  @override
  final EnvironmentRepository environmentRepository;
  @override
  final GlobalVariableRepository globalVariableRepository;
}

const _insomniaExport = r'''
{
  "_type": "export",
  "__export_format": 4,
  "resources": [
    {"_id": "wrk_1", "_type": "workspace", "parentId": null, "name": "Pet Store"},
    {"_id": "env_base", "_type": "environment", "parentId": "wrk_1", "name": "Base Environment", "data": {"base_url": "https://pets.test", "token": "abc"}},
    {"_id": "env_dev", "_type": "environment", "parentId": "env_base", "name": "Development", "data": {"base_url": "https://dev.pets.test"}},
    {"_id": "fld_1", "_type": "request_group", "parentId": "wrk_1", "name": "Pets", "metaSortKey": -2},
    {"_id": "fld_2", "_type": "request_group", "parentId": "fld_1", "name": "Admin", "metaSortKey": -1},
    {"_id": "req_1", "_type": "request", "parentId": "fld_1", "name": "List pets", "method": "GET", "url": "{{ _.base_url }}/pets", "metaSortKey": -2,
     "headers": [{"name": "Accept", "value": "application/json"}, {"name": "X-Debug", "value": "1", "disabled": true}],
     "parameters": [{"name": "limit", "value": "10"}],
     "authentication": {"type": "bearer", "token": "{{ _.token }}"}},
    {"_id": "req_2", "_type": "request", "parentId": "fld_2", "name": "Create pet", "method": "POST", "url": "{{ _.base_url }}/pets",
     "body": {"mimeType": "application/json", "text": "{\"name\": \"Rex\"}"},
     "authentication": {"type": "basic", "username": "u", "password": "p"}},
    {"_id": "req_3", "_type": "request", "parentId": "wrk_1", "name": "Login", "method": "POST", "url": "{{ _.base_url }}/login",
     "body": {"mimeType": "application/x-www-form-urlencoded", "params": [{"name": "user", "value": "ann"}, {"name": "remember", "value": "1", "disabled": true}]}}
  ]
}
''';

String _har() => jsonEncode({
      'log': {
        'version': '1.2',
        'entries': [
          {
            'request': {
              'method': 'POST',
              'url': 'https://shop.example.com/api/cart?x=1',
              'headers': [
                {'name': ':authority', 'value': 'shop.example.com'},
                {'name': 'content-type', 'value': 'application/json'},
                {'name': 'cookie', 'value': 'a=1'},
                {'name': 'cookie', 'value': 'b=2'},
              ],
              'postData': {'mimeType': 'application/json', 'text': '{"sku":"A1"}'},
            },
          },
          {
            'request': {'method': 'GET', 'url': 'https://shop.example.com/api/products', 'headers': const []},
          },
        ],
      },
    });

void main() {
  // Two databases are opened in a few tests; each has its own in-memory connection.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase database;
  late _DriftRepositories repos;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repos = _DriftRepositories(database);
  });

  tearDown(() => database.close());

  group('backup through the real repositories', () {
    test('export then restore into another database reproduces everything', () async {
      await seedShop(repos);
      final backup = (await repos.backupService.export()).text;
      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final target = _DriftRepositories(other);

      final summary = await target.backupService.restore(backup);

      expect(normalizedBackup((await target.backupService.export()).text), normalizedBackup(backup));
      expect((summary.folders, summary.requests, summary.environments, summary.globalVariables), (3, 6, 2, 2));
    });

    test('the restored requests are real, runnable rows: tests, examples and secret auth included', () async {
      await seedShop(repos);
      final backup = (await repos.backupService.export()).text;
      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final target = _DriftRepositories(other);

      await target.backupService.restore(backup);

      final shop = (await target.collectionRepository.watchCollections().first).singleWhere((c) => c.name == 'Shop');
      final summaries = await target.requestRepository.watchByCollection(shop.id).first;
      final oldOrder = summaries.singleWhere((r) => r.name == 'Old order');
      final full = (await target.requestRepository.findById(oldOrder.id))!;
      expect(full.method, HttpMethod.put);
      expect(full.body.type, BodyType.urlEncoded);
      expect(full.folderId, isNotNull);
      expect((await target.scriptsRepository.get(oldOrder.id))!.assertionsJson, shopAssertions);
      expect(await target.exampleRepository.watchByRequest(oldOrder.id).first, hasLength(2));
      final create = (await target.requestRepository.findById(summaries.singleWhere((r) => r.name == 'Create order').id))!;
      expect(create.auth.type, AuthType.oauth2);
      expect(create.auth.oauth2RefreshToken, 'refresh-token');
      expect(RequestAuth.fromJsonString(await target.collectionAuthRepository.getAuthJson(shop.id))!.bearerToken, '{{token}}');
    });

    test('settings, descriptions and tags land on the restored rows (their tables have no foreign key)', () async {
      await seedShop(repos);
      final backup = (await repos.backupService.export()).text;
      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final target = _DriftRepositories(other);
      // Different ids than in the source database, so an un-remapped id would show.
      for (var i = 0; i < 5; i++) {
        await target.collectionRepository.createCollection('Noise $i');
      }

      await target.backupService.restore(backup);

      final shop = (await target.collectionRepository.watchCollections().first).singleWhere((c) => c.name == 'Shop');
      final list = (await target.requestRepository.watchByCollection(shop.id).first).singleWhere((r) => r.name == 'List orders');
      final folders = {for (final f in await target.collectionRepository.watchFolders(shop.id).first) f.name: f.id};
      expect(
        await target.requestSettingsRepository.get(list.id),
        const RequestSettings(verifySsl: false, timeoutSeconds: 5, followRedirects: false),
      );
      expect(await target.documentationRepository.markdownOf(EntityKind.request, list.id), 'Lists **every** order.');
      expect(await target.tagRepository.tagsByLocalId(EntityKind.request), {list.id: ['orders', 'read']});
      expect(await target.documentationRepository.markdownOf(EntityKind.collection, shop.id), '# Shop API');
      expect(await target.tagRepository.tagsByLocalId(EntityKind.collection), {shop.id: ['internal']});
      expect(await target.documentationRepository.markdownByLocalId(EntityKind.folder), {folders['Archive']!: 'Old orders, read-only.'});
      expect(await target.tagRepository.tagsByLocalId(EntityKind.folder), {folders['Orders']!: ['orders', 'v2']});
    });

    test('a second restore into the same database adds a copy and leaves the originals alone', () async {
      await seedShop(repos);
      final backup = (await repos.backupService.export()).text;

      await repos.backupService.restore(backup);

      final names = (await repos.collectionRepository.watchCollections().first).map((c) => c.name).toList();
      expect(names, ['Shop', 'Empty', 'Shop (restored)', 'Empty (restored)']);
      expect((await repos.environmentRepository.watchAll().first).map((e) => e.name), ['Dev', 'Prod', 'Dev (restored)', 'Prod (restored)']);
      expect(await repos.globalVariableRepository.watchAll().first, hasLength(2));
    });

    test('deleting a restored collection cascades like any other, which is what the rollback relies on', () async {
      await seedShop(repos);
      final summary = await repos.backupService.restore((await repos.backupService.export()).text);

      await repos.collectionRepository.deleteCollection(summary.collectionIds.first);

      expect(await database.select(database.requests).get(), hasLength(6));
      expect(await database.select(database.folders).get(), hasLength(3));
      expect(await database.select(database.responseExamples).get(), hasLength(2));
    });
  });

  group('Insomnia import into the real database', () {
    test('creates nested folders, requests, collection variables and environments', () async {
      final useCase = ImportInsomniaUseCase(repos.writer, repos.collectionRepository, repos.environmentRepository);

      final summary = await useCase(_insomniaExport);

      expect(summary.format, ImportFormat.insomnia);
      final collectionId = summary.collectionIds.single;
      final folders = await repos.collectionRepository.watchFolders(collectionId).first;
      expect(folders.map((f) => f.name), ['Pets', 'Admin']);
      expect(folders.last.parentFolderId, folders.first.id);
      final summaries = await repos.requestRepository.watchByCollection(collectionId).first;
      expect(summaries.map((r) => r.name), unorderedEquals(['List pets', 'Create pet', 'Login']));
      final list = (await repos.requestRepository.findById(summaries.singleWhere((r) => r.name == 'List pets').id))!;
      expect(list.url, '{{base_url}}/pets');
      expect(list.headers.map((h) => (h.key, h.enabled)), [('Accept', true), ('X-Debug', false)]);
      expect(list.queryParams.single.key, 'limit');
      expect(list.auth.type, AuthType.bearer);
      expect(list.auth.bearerToken, '{{token}}');
      final login = (await repos.requestRepository.findById(summaries.singleWhere((r) => r.name == 'Login').id))!;
      expect(login.body.urlEncodedFields.map((f) => (f.key, f.enabled)), [('user', true), ('remember', false)]);
      final variables = await repos.collectionVariableRepository.getEnabledMap(collectionId);
      expect(variables, {'base_url': 'https://pets.test', 'token': 'abc'});
      final environment = (await repos.environmentRepository.watchAll().first).single;
      expect(environment.name, 'Pet Store - Development');
      expect((await repos.environmentRepository.watchVariables(environment.id).first).single.value, 'https://dev.pets.test');
    });
  });

  group('HAR and cURL imports into the real database', () {
    test('a HAR file becomes one flat collection with merged cookies', () async {
      final summary = await ImportHarUseCase(repos.writer)(_har());

      final summaries = await repos.requestRepository.watchByCollection(summary.collectionIds.single).first;
      expect(summaries.map((r) => r.name), ['POST /api/cart', 'GET /api/products']);
      final cart = (await repos.requestRepository.findById(summaries.first.id))!;
      expect(cart.url, 'https://shop.example.com/api/cart?x=1');
      expect(cart.headers.map((h) => (h.key, h.value)), [('content-type', 'application/json'), ('Cookie', 'a=1; b=2')]);
      expect(cart.body.rawText, '{"sku":"A1"}');
    });

    test('a cURL script goes into an existing collection and folder', () async {
      final collectionId = await repos.collectionRepository.createCollection('Mine');
      final folderId = await repos.collectionRepository.createFolder(collectionId: collectionId, name: 'Inbox');

      await ImportCurlScriptUseCase(repos.writer)(
        ImportCurlScriptParams(script: '# Ping\ncurl -X POST https://a.test/ping -H "Content-Type: application/json" -d \'{"a":"it\'\\\'\'s"}\'', collectionId: collectionId, folderId: folderId),
      );

      final summary = (await repos.requestRepository.watchByCollection(collectionId).first).single;
      expect((summary.name, summary.folderId, summary.method), ('Ping', folderId, HttpMethod.post));
      expect((await repos.requestRepository.findById(summary.id))!.body.rawText, '{"a":"it\'s"}');
    });
  });

  group('exports from the real database', () {
    test('OpenAPI export of the seeded shop is a valid document with its folders as tags', () async {
      await seedShop(repos);
      final shop = (await repos.collectionRepository.watchCollections().first).singleWhere((c) => c.name == 'Shop');

      final result = await ExportOpenApiUseCase(repos.loader)(shop.id);

      final doc = jsonDecode(result.text) as Map<String, dynamic>;
      expect(doc['openapi'], '3.0.3');
      expect((doc['servers'] as List).single, {'url': 'https://shop.test'});
      expect((doc['paths'] as Map).keys, containsAll(['/orders', '/x']));
      expect([for (final t in doc['tags'] as List) (t as Map)['name']], unorderedEquals(['Orders', 'Orders / Archive']));
      expect(result.itemCount, greaterThan(0));
    });

    test('the cURL script of the seeded shop has one command per request, folder banners and resolved variables', () async {
      await seedShop(repos);
      final shop = (await repos.collectionRepository.watchCollections().first).singleWhere((c) => c.name == 'Shop');
      final useCase = ExportCurlScriptUseCase(
        repos.loader,
        GenerateCodeSnippetUseCase(
          BuildVariableResolverUseCase(repos.collectionVariableRepository, repos.environmentRepository, repos.globalVariableRepository),
          repos.collectionAuthRepository,
        ),
      );

      final result = await useCase(shop.id);

      expect(result.itemCount, 6);
      expect(result.text, contains('# --- Orders / Archive ---'));
      expect(result.text, contains("curl --location --request GET 'https://shop.test/orders?limit=10'"));
      expect(RegExp(r'^curl ', multiLine: true).allMatches(result.text), hasLength(6));
    });
  });
}
