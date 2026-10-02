import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/dart_codegen/domain/services/api_layer_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/usecases/build_api_layer_usecase.dart';
import 'package:postpilot/features/import_export/domain/services/collection_loader.dart';
import 'package:postpilot/features/import_export/domain/services/imported_collection_writer.dart';
import 'package:postpilot/features/import_export/domain/services/openapi_refresh_planner.dart';
import 'package:postpilot/features/import_export/domain/usecases/refresh_openapi_usecase.dart';
import 'package:postpilot/features/mock_server/domain/usecases/build_mock_routes_usecase.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_json2.dart';
import 'package:postpilot/features/odoo/domain/usecases/create_odoo_workspace_usecase.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'package:postpilot/features/response_tools/domain/services/response_history.dart';
import 'package:postpilot/features/response_tools/presentation/view_models/response_tools_view_model.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/templates/domain/starter_templates.dart';
import 'package:postpilot/features/templates/domain/usecases/add_starter_template_usecase.dart';
import '../support/drift_repos.dart';
import '../support/shop_seed.dart';

const _spec = '''
{
  "openapi": "3.0.0",
  "info": {"title": "Pets", "version": "2"},
  "servers": [{"url": "https://pets.test"}],
  "tags": [{"name": "pets"}, {"name": "owners"}],
  "paths": {
    "/pets": {
      "get": {"tags": ["pets"], "summary": "List pets"},
      "post": {"tags": ["pets"], "summary": "Create pet"}
    },
    "/pets/{petId}": {
      "get": {"tags": ["pets"], "summary": "Get pet", "parameters": [{"name": "petId", "in": "path", "required": true, "schema": {"type": "string"}}]}
    },
    "/owners": {"get": {"tags": ["owners"], "summary": "List owners"}}
  }
}
''';

void main() {
  late AppDatabase db;
  late DriftRepos repos;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
  });
  tearDown(() => db.close());

  CollectionLoader loader() => CollectionLoader(repos.collectionRepository, repos.requestRepository, repos.collectionVariableRepository, repos.collectionAuthRepository);

  group('OpenAPI refresh', () {
    test('path matching ignores base URL, query and the spelling of parameters', () {
      expect(OpenApiRefreshPlanner.normalizePath('{{baseUrl}}/pets/{{petId}}?x=1'), '/pets/{}');
      expect(OpenApiRefreshPlanner.normalizePath('https://a.test/Pets/{id}/'), '/pets/{}');
      expect(OpenApiRefreshPlanner.normalizePath('/pets/:id'), '/pets/{}');
      expect(OpenApiRefreshPlanner.normalizePath('{{baseUrl}}'), '/');
    });

    test('adds only the new endpoints, keeps edits, and marks what left the spec', () async {
      final collection = await repos.collectionRepository.createCollection('Pets');
      final folder = await repos.collectionRepository.createFolder(collectionId: collection, name: 'pets');
      // What an earlier import made, plus a request the person edited and one that is no longer in the spec.
      final edited = await addRequest(repos, collection, 'My list pets', folderId: folder, url: '{{baseUrl}}/pets', headers: [KeyValueItem(key: 'X-Mine', value: '1')]);
      await addRequest(repos, collection, 'Old endpoint', folderId: folder, method: HttpMethod.delete, url: '{{baseUrl}}/legacy');
      await addRequest(repos, collection, 'Hand made', url: 'https://other.test/hand');

      final useCase = RefreshOpenApiUseCase(repos.collectionRepository, repos.requestRepository);
      final plan = await useCase.plan(collection, _spec);
      expect(plan.added.map((e) => '${e.item.method.label} ${OpenApiRefreshPlanner.normalizePath(e.item.url)}'),
          unorderedEquals(['POST /pets', 'GET /pets/{}', 'GET /owners']));
      expect(plan.removed.map((r) => r.name), ['Old endpoint'], reason: 'a request to another server is not the spec\'s business');
      expect(plan.unchanged, 1);

      final added = await useCase.apply(collection, plan);
      expect(added, 3);

      final all = await loader().load(collection);
      final names = all.requests.map((r) => r.name).toList();
      expect(names, containsAll(['My list pets', 'Create pet', 'Get pet', 'List owners', '⚠ Old endpoint', 'Hand made']));
      final mine = all.requests.firstWhere((r) => r.id == edited);
      expect(mine.headers.single.key, 'X-Mine', reason: 'an existing request is left exactly as it was');
      final owners = all.requests.firstWhere((r) => r.name == 'List owners');
      expect(all.folders.firstWhere((f) => f.id == owners.folderId).name, 'owners', reason: 'a missing tag folder is created');

      final again = await useCase.plan(collection, _spec);
      expect(again.added, isEmpty, reason: 'applying twice changes nothing more');
    });

    test('a spec that is not an OpenAPI document is reported, not swallowed', () async {
      final collection = await repos.collectionRepository.createCollection('Pets');
      await expectLater(RefreshOpenApiUseCase(repos.collectionRepository, repos.requestRepository).plan(collection, '{"hello": 1}'), throwsA(anything));
    });
  });

  group('Dart API layer from a real collection', () {
    test('folders become separate data sources and examples become DTOs', () async {
      final collection = await repos.collectionRepository.createCollection('Shop API');
      final folder = await repos.collectionRepository.createFolder(collectionId: collection, name: 'Orders');
      final get = await addRequest(repos, collection, 'Get order', folderId: folder, url: '{{baseUrl}}/orders/{{orderId}}?expand=items');
      await addRequest(
        repos,
        collection,
        'Create order',
        folderId: folder,
        method: HttpMethod.post,
        url: '{{baseUrl}}/orders',
        body: const RequestBody(type: BodyType.raw, rawText: '{"sku": "A1", "qty": 2}'),
      );
      await repos.exampleRepository.add(ResponseExampleEntity(
        id: 0,
        requestId: get,
        name: '200 OK',
        statusCode: 200,
        headers: const {},
        body: '{"id": 7, "total": 19.5, "created_at": "2026-10-02T10:00:00Z"}',
        savedAt: DateTime.utc(2026),
      ));

      final result = await BuildApiLayerUseCase(loader(), repos.exampleRepository)(collection, const ApiLayerOptions(packageName: 'shop_app'));
      final paths = result.files.map((f) => f.path);
      expect(paths, contains('lib/features/shop_api/data/datasources/orders_remote_data_source.dart'));
      expect(paths, contains('lib/features/shop_api/data/models/get_order_response.dart'));
      expect(paths, contains('lib/features/shop_api/data/models/create_order_request.dart'));
      final ds = result.files.firstWhere((f) => f.path.endsWith('orders_remote_data_source.dart')).content;
      expect(ds, contains('Future<GetOrderResponse> getOrder('));
      expect(ds, contains('required String orderId'));
      expect(ds, contains('required CreateOrderRequest body'));
      expect(result.files.firstWhere((f) => f.path.endsWith('get_order_response.dart')).content, contains('final DateTime createdAt;'));
    });
  });

  group('Mock server routes from a real collection', () {
    test('serve the newest successful example of each request', () async {
      final collection = await repos.collectionRepository.createCollection('Mock me');
      final list = await addRequest(repos, collection, 'List', url: '{{baseUrl}}/items');
      await addRequest(repos, collection, 'No example', url: '{{baseUrl}}/ghost');
      Future<void> example(int request, String name, int status, String body) => repos.exampleRepository.add(ResponseExampleEntity(
            id: 0,
            requestId: request,
            name: name,
            statusCode: status,
            headers: const {'content-type': 'application/json'},
            body: body,
            savedAt: DateTime.now(),
          ));
      await example(list, 'ok', 200, '[1]');
      await example(list, 'later error', 500, '{"error":true}');

      final table = await BuildMockRoutesUseCase(loader(), repos.exampleRepository)(collection);
      expect(table.routes.single.path, '/items');
      expect(table.routes.single.status, 200, reason: 'a 2xx example beats a newer failure');
      expect(table.routes.single.body, '[1]');
      expect(table.skipped, ['No example']);
      expect(table.match('GET', '/items?x=1'), isNotNull);
    });
  });

  group('Odoo workspace', () {
    test('creates an environment with a secret key and a collection of ready requests', () async {
      final useCase = CreateOdooWorkspaceUseCase(repos.environmentRepository, repos.collectionRepository, repos.requestRepository);
      final envId = await useCase.createEnvironment(name: 'Odoo · acme', url: 'https://acme.odoo.com', database: 'acme', apiKey: 'key-123');
      final vars = {for (final v in await repos.environmentRepository.watchVariables(envId).first) v.key: v};
      expect(vars['odooUrl']!.value, 'https://acme.odoo.com');
      expect(vars['odooDb']!.value, 'acme');
      expect(vars['odooApiKey']!.isSecret, isTrue);
      expect((await repos.environmentRepository.getActiveVariables())['odooUrl'], 'https://acme.odoo.com', reason: 'it is selected');

      final result = await useCase.createCollection(name: 'Odoo', models: ['res.partner', 'sale.order'], fieldsByModel: {'res.partner': ['name', 'email']});
      expect(result.requestCount, 20);
      final loaded = await loader().load(result.collectionId!);
      expect(loaded.folders.map((f) => f.name), unorderedEquals(['res.partner', 'sale.order']));
      final search = loaded.requests.firstWhere((r) => r.name == 'List res.partner');
      expect(search.method, HttpMethod.post);
      expect(search.url, '{{odooUrl}}/json/2/res.partner/search_read');
      expect(search.headers.map((h) => h.key), containsAll(['Authorization', 'X-Odoo-Database']));
      expect(search.headers.firstWhere((h) => h.key == 'Authorization').value, 'bearer {{odooApiKey}}');
      expect(jsonDecode(search.body.rawText)['fields'], ['name', 'email']);
      expect(search.body.type, BodyType.raw);
    });

    test('a single converted call can be added to a collection', () async {
      final useCase = CreateOdooWorkspaceUseCase(repos.environmentRepository, repos.collectionRepository, repos.requestRepository);
      final collection = await repos.collectionRepository.createCollection('Odoo');
      final id = await useCase.addRequest(collectionId: collection, draft: const OdooRequestDraftForTest().draft);
      final saved = (await repos.requestRepository.findById(id))!;
      expect(saved.url, contains('/json/2/res.partner/search'));
      expect(saved.method, HttpMethod.post);
    });
  });

  group('Starter templates', () {
    test('every template adds a collection whose {{variables}} are all defined', () async {
      final writer = ImportedCollectionWriter(repos.collectionRepository, repos.requestRepository, repos.collectionVariableRepository, repos.collectionAuthRepository);
      final useCase = AddStarterTemplateUseCase(writer, repos.environmentRepository);
      for (final template in StarterTemplates.all()) {
        final added = await useCase(template);
        expect(added.requests, template.requestCount, reason: template.title);
        final loaded = await loader().load(added.collectionId);
        expect(loaded.requests, hasLength(template.requestCount));

        final defined = {
          for (final v in template.environmentVariables) v.key,
          for (final v in loaded.variables) v.key,
        };
        final used = <String>{};
        final pattern = RegExp(r'\{\{([\w.$-]+)\}\}');
        for (final r in loaded.requests) {
          for (final text in [r.url, r.body.rawText, r.auth.bearerToken, ...r.headers.map((h) => h.value)]) {
            used.addAll(pattern.allMatches(text).map((m) => m[1]!));
          }
        }
        expect(defined.containsAll(used), isTrue, reason: '${template.title} uses undefined variables: ${used.difference(defined)}');
        if (template.environmentName != null) {
          expect(added.environmentId, isNotNull);
          final envVars = await repos.environmentRepository.watchVariables(added.environmentId!).first;
          expect(envVars.map((v) => v.key), unorderedEquals(template.environmentVariables.map((v) => v.key)));
        }
      }
    });

    test('secret variables are marked secret, and the environment is selected', () async {
      final writer = ImportedCollectionWriter(repos.collectionRepository, repos.requestRepository, repos.collectionVariableRepository, repos.collectionAuthRepository);
      final template = StarterTemplates.all().firstWhere((t) => t.id == 'odoo');
      final added = await AddStarterTemplateUseCase(writer, repos.environmentRepository)(template);
      final vars = {for (final v in await repos.environmentRepository.watchVariables(added.environmentId!).first) v.key: v};
      expect(vars['odooApiKey']!.isSecret, isTrue);
      expect(vars['odooUrl']!.isSecret, isFalse);
      expect((await repos.environmentRepository.getActiveVariables()).containsKey('odooUrl'), isTrue);
    });

    test('templates have unique ids and sensible content', () {
      final all = StarterTemplates.all();
      expect(all.map((t) => t.id).toSet().length, all.length);
      for (final t in all) {
        expect(t.title, isNotEmpty);
        expect(t.description.length, greaterThan(30));
        expect(t.requestCount, greaterThan(2));
      }
    });
  });

  group('Response tools write-back', () {
    test('"Use as variable" and "Add test" land in the request\'s Tests tab', () async {
      final collection = await repos.collectionRepository.createCollection('C');
      final request = await addRequest(repos, collection, 'Login', url: 'https://x.test/login');
      final response = ApiResponseEntity(
        statusCode: 200,
        statusMessage: 'OK',
        headers: const {},
        bodyBytes: Uint8List.fromList(utf8.encode('{"token":"abc","user":{"id":5}}')),
        duration: const Duration(milliseconds: 40),
      );
      final history = ResponseHistory()..record(request, response);
      final vm = ResponseToolsViewModel(
        repos.requestRepository,
        repos.scriptsRepository,
        repos.exampleRepository,
        history,
        ResponseToolsData.from(requestId: request, requestName: 'Login', response: response),
      );
      await vm.load();
      expect(vm.request!.name, 'Login');
      expect(vm.data.isJson, isTrue);

      await vm.addExtractor(path: 'token', key: 'authToken', scope: ExtractorScope.environment);
      await vm.addExtractor(path: 'token', key: 'authToken', scope: ExtractorScope.environment); // twice: stored once
      await vm.addAssertion(AssertionEntity(type: AssertionType.jsonPathEquals, path: 'user.id', expected: '5'));

      final scripts = (await repos.scriptsRepository.get(request))!;
      final extractors = ScriptsJsonCodec.decodeExtractors(scripts.extractorsJson);
      expect(extractors, hasLength(1));
      expect(extractors.single.variableKey, 'authToken');
      final assertions = ScriptsJsonCodec.decodeAssertions(scripts.assertionsJson);
      expect(assertions.single.type, AssertionType.jsonPathEquals);
      expect(assertions.single.expected, '5');
    });

    test('compare sources list earlier responses and saved examples', () async {
      final collection = await repos.collectionRepository.createCollection('C');
      final request = await addRequest(repos, collection, 'List');
      ApiResponseEntity response(String body) => ApiResponseEntity(statusCode: 200, statusMessage: 'OK', headers: const {}, bodyBytes: Uint8List.fromList(utf8.encode(body)), duration: Duration.zero);
      final first = response('{"v":1}');
      final second = response('{"v":2}');
      final history = ResponseHistory()
        ..record(request, first)
        ..record(request, second);
      await repos.exampleRepository.add(ResponseExampleEntity(id: 0, requestId: request, name: 'baseline', statusCode: 200, headers: const {}, body: '{"v":0}', savedAt: DateTime.now()));

      final vm = ResponseToolsViewModel(repos.requestRepository, repos.scriptsRepository, repos.exampleRepository, history, ResponseToolsData.from(requestId: request, requestName: 'List', response: second));
      await vm.load();
      final sources = vm.compareSources;
      expect(sources.map((s) => s.body), ['{"v":1}', '{"v":0}']);
      expect(sources.first.label, startsWith('Previous response'));
      expect(sources.last.label, contains('baseline'));
    });
  });
}

/// A draft like the Migrate tab produces, without importing the converter just for this.
final class OdooRequestDraftForTest {
  const OdooRequestDraftForTest();
  OdooRequestDraft get draft => const OdooRequestDraft(
        name: 'res.partner · search',
        url: '{{odooUrl}}/json/2/res.partner/search',
        headers: {'Authorization': 'bearer {{odooApiKey}}'},
        bodyText: '{"domain": []}',
      );
}
