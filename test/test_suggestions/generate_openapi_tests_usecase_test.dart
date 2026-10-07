import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/request_flow/domain/services/run_if_evaluator.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/test_suggestions/domain/openapi/generated_case.dart';
import 'package:postpilot/features/test_suggestions/domain/openapi/openapi_test_generator.dart';
import 'package:postpilot/features/test_suggestions/domain/usecases/generate_openapi_tests_usecase.dart';
import '../support/drift_repos.dart';
import 'openapi_specs.dart';

/// Delegates to the real repository, and fails the n-th save.
final class _FailingRequests implements RequestRepository {
  final RequestRepository _inner;
  final int failOn;
  int _saves = 0;
  _FailingRequests(this._inner, this.failOn);

  @override
  Stream<List<RequestSummaryEntity>> watchByCollection(int collectionId) => _inner.watchByCollection(collectionId);
  @override
  Stream<ApiRequestEntity?> watchById(int id) => _inner.watchById(id);
  @override
  Future<ApiRequestEntity?> findById(int id) => _inner.findById(id);
  @override
  Future<int> createRequest({required int collectionId, int? folderId, required String name}) =>
      _inner.createRequest(collectionId: collectionId, folderId: folderId, name: name);
  @override
  Future<void> saveRequest(ApiRequestEntity request) async {
    if (++_saves == failOn) throw StateError('disk full');
    await _inner.saveRequest(request);
  }

  @override
  Future<void> deleteRequest(int id) => _inner.deleteRequest(id);
}

void main() {
  late AppDatabase database;
  late DriftRepos repos;
  late int collection;
  late GenerateOpenApiTestsUseCase useCase;
  final suite = OpenApiTestGenerator.generate(petShopSpec);

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(database);
    collection = await repos.collectionRepository.createCollection('Pets');
    useCase = GenerateOpenApiTestsUseCase(
      repos.collectionRepository,
      repos.requestRepository,
      repos.scriptsRepository,
      repos.requestSettingsRepository,
      repos.collectionVariableRepository,
    );
  });

  tearDown(() => database.close());

  Future<List<FolderEntity>> folders() => repos.collectionRepository.watchFolders(collection).first;

  Future<Map<String, ApiRequestEntity>> requestsByName(int id) async {
    final out = <String, ApiRequestEntity>{};
    for (final summary in await repos.requestRepository.watchByCollection(id).first) {
      out[summary.name] = (await repos.requestRepository.findById(summary.id))!;
    }
    return out;
  }

  test('writes a Tests folder with one sub-folder per category, in the order the categories are listed', () async {
    final result = await useCase(collection, suite, suite.select());
    final all = await folders();
    final root = all.singleWhere((f) => f.parentFolderId == null);
    expect(root.name, 'Tests');
    expect(all.where((f) => f.parentFolderId == root.id).map((f) => f.name), ['Contract', 'Negative', 'Boundary', 'Auth']);
    expect(result.folderName, 'Tests');
    expect(result.created, 39);
  });

  test('every request is written with its method, URL, body, auth and assertions, in the folder of its category', () async {
    await useCase(collection, suite, suite.select());
    final byName = await requestsByName(collection);
    expect(byName.keys.toSet(), petShopCases.toSet());
    final all = await folders();
    String folderOf(String name) => all.firstWhere((f) => f.id == byName[name]!.folderId).name;
    expect(folderOf('GET /pets (contract)'), 'Contract');
    expect(folderOf('POST /pets (missing name)'), 'Negative');
    expect(folderOf('POST /pets (age above maximum)'), 'Boundary');
    expect(folderOf('GET /pets (no credentials)'), 'Auth');

    final create = byName['POST /pets (contract)']!;
    expect(create.method, HttpMethod.post);
    expect(create.url, '{{baseUrl}}/pets');
    expect(create.body.rawText, contains('"species": "dog"'));
    expect(create.auth.type, AuthType.bearer);
    final saved = await repos.scriptsRepository.get(create.id);
    final assertions = ScriptsJsonCodec.decodeAssertions(saved!.assertionsJson);
    expect(assertions.map((a) => a.type), [AssertionType.statusEquals, AssertionType.headerExists, AssertionType.jsonSchema]);
    expect(assertions.first.expected, '201');

    final list = byName['GET /pets (query limit above maximum)']!;
    expect(list.queryParams.firstWhere((q) => q.key == 'limit').value, '101');
  });

  test('requests that change data wait for a variable; reads do not', () async {
    final result = await useCase(collection, suite, suite.select());
    final byName = await requestsByName(collection);
    expect(result.gated, 24);

    final post = await repos.requestSettingsRepository.get(byName['POST /pets (contract)']!.id);
    final delete = await repos.requestSettingsRepository.get(byName['DELETE /pets/{petId} (no credentials)']!.id);
    final get = await repos.requestSettingsRepository.get(byName['GET /pets (contract)']!.id);
    expect(get.flow.runIf.isActive, isFalse);
    for (final settings in [post, delete]) {
      expect(settings.flow.runIf.isActive, isTrue);
      expect(settings.flow.runIf.conditions.single.text, '{{allowDataChanging}} equals "true"');
    }

    // With the variable off (as it is added) or absent the request is skipped, with a reason; with it on it runs.
    RunIfDecision decide(Map<String, String> variables) =>
        RunIfEvaluator.evaluate(post.flow.runIf, RunIfContext(resolver: VariableResolver.layered([variables])));
    expect(decide({'allowDataChanging': 'false'}).run, isFalse);
    expect(decide({'allowDataChanging': 'false'}).reason, 'Skipped: {{allowDataChanging}} is "false", but this runs only when it equals "true"');
    expect(decide(const {}).run, isFalse);
    expect(decide({'allowDataChanging': 'true'}).run, isTrue);
  });

  test('adds the server as baseUrl and the gate as false, unless the collection has them', () async {
    final first = await useCase(collection, suite, suite.select());
    expect(first.variablesAdded, ['baseUrl', 'allowDataChanging']);
    final variables = await repos.collectionVariableRepository.getEnabledMap(collection);
    expect(variables['baseUrl'], 'https://api.petshop.test/v1');
    expect(variables['allowDataChanging'], 'false');

    final other = await repos.collectionRepository.createCollection('Staging');
    await repos.collectionVariableRepository.upsert(CollectionVariableEntity(id: 0, collectionId: other, key: 'baseUrl', value: 'https://staging.test', enabled: true));
    await repos.collectionVariableRepository.upsert(CollectionVariableEntity(id: 0, collectionId: other, key: 'allowDataChanging', value: 'true', enabled: true));
    final second = await useCase(other, suite, suite.select());
    expect(second.variablesAdded, isEmpty);
    final kept = await repos.collectionVariableRepository.getEnabledMap(other);
    expect(kept['baseUrl'], 'https://staging.test');
    expect(kept['allowDataChanging'], 'true', reason: 'a person\'s choice is never changed');
  });

  test('a selection with nothing that changes data adds no gate', () async {
    final reads = GeneratedSelection([for (final c in suite.cases) if (!c.changesData && c.category == TestCategory.contract) c], 0);
    final result = await useCase(collection, suite, reads);
    expect(result.created, 3);
    expect(result.gated, 0);
    expect(result.variablesAdded, ['baseUrl']);
    final all = await folders();
    expect(all.where((f) => f.parentFolderId != null).map((f) => f.name), ['Contract'], reason: 'no empty sub-folders');
  });

  test('a second generation does not mix with the first: the folder is called Tests 2', () async {
    await useCase(collection, suite, suite.select());
    final second = await useCase(collection, suite, suite.select());
    final third = await useCase(collection, suite, suite.select());
    expect((second.folderName, third.folderName), ('Tests 2', 'Tests 3'));
    expect((await folders()).where((f) => f.parentFolderId == null).map((f) => f.name), ['Tests', 'Tests 2', 'Tests 3']);
  });

  test('only the selected cases are written', () async {
    final selection = suite.select(categories: {TestCategory.auth}, cap: 3);
    final result = await useCase(collection, suite, selection);
    expect(result.created, 3);
    expect((await requestsByName(collection)).keys, unorderedEquals(['GET /pets (no credentials)', 'GET /pets (malformed token)', 'POST /pets (no credentials)']));
  });

  test('a failure half way leaves nothing behind, and adds no variables', () async {
    final failing = GenerateOpenApiTestsUseCase(
      repos.collectionRepository,
      _FailingRequests(repos.requestRepository, 5),
      repos.scriptsRepository,
      repos.requestSettingsRepository,
      repos.collectionVariableRepository,
    );
    await expectLater(failing(collection, suite, suite.select()), throwsA(isA<StateError>()));
    expect(await folders(), isEmpty);
    expect(await repos.requestRepository.watchByCollection(collection).first, isEmpty);
    expect(await repos.collectionVariableRepository.getEnabledMap(collection), isEmpty);
  });
}
