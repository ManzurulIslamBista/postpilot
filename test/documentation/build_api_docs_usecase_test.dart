import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/documentation/domain/services/api_docs_generator.dart';
import 'package:postpilot/features/documentation/domain/usecases/build_api_docs_usecase.dart';
import 'package:postpilot/features/documentation/presentation/view_models/collection_docs_view_model.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';

import 'support/fakes.dart';

const _secretBearer = 'SECRET_BEARER_TOKEN_123';
const _secretPassword = 'SECRET_BASIC_PASSWORD_456';
const _secretApiKey = 'SECRET_API_KEY_789';

ResponseExampleEntity _example(int id, int requestId, String name, {int status = 200, String body = ''}) =>
    ResponseExampleEntity(
      id: id,
      requestId: requestId,
      name: name,
      statusCode: status,
      headers: const {},
      body: body,
      savedAt: DateTime(2026, 1, id),
    );

KeyValueItem _kv(String key, String value, {bool enabled = true}) => KeyValueItem(key: key, value: value, enabled: enabled);

void main() {
  late FakeDocumentationRepository docs;
  late FakeTagRepository tags;
  late BuildApiDocsUseCase useCase;

  // Shop (1)
  //  ├─ Users (10)
  //  │   ├─ Admin (11)      Ban user (101, POST)
  //  │   └─ List users (100, GET)
  //  ├─ Health (102, GET, no folder)
  //  └─ Orphan (103, folder 999 that does not exist)
  setUp(() {
    docs = FakeDocumentationRepository()
      ..seed(EntityKind.collection, 1, 'About the shop')
      ..seed(EntityKind.folder, 10, 'User endpoints')
      ..seed(EntityKind.request, 100, 'Lists users');
    tags = FakeTagRepository()
      ..seed(EntityKind.collection, 1, ['v2'])
      ..seed(EntityKind.folder, 10, ['users'])
      ..seed(EntityKind.request, 100, ['read', 'Beta']);

    final requests = FakeRequestRepository({
      1: [
        requestEntity(
          100,
          folderId: 10,
          name: 'List users',
          url: '{{baseUrl}}/users',
          headers: [_kv('Accept', 'application/json'), _kv('X-Debug', '1', enabled: false), _kv('  ', 'blank key')],
          queryParams: [_kv('page', '1'), _kv('off', 'x', enabled: false)],
          auth: const RequestAuth(type: AuthType.bearer, bearerToken: _secretBearer),
          body: const RequestBody(type: BodyType.raw, rawContentType: RawContentType.json, rawText: '{"a": 1}'),
        ),
        requestEntity(
          101,
          folderId: 11,
          name: 'Ban user',
          method: HttpMethod.post,
          url: '/ban',
          auth: const RequestAuth(type: AuthType.inherit),
        ),
        requestEntity(102, name: 'Health', url: '/health', auth: const RequestAuth(type: AuthType.none)),
        requestEntity(103, folderId: 999, name: 'Orphan', method: HttpMethod.put, url: '/orphan'),
      ],
    });
    useCase = BuildApiDocsUseCase(
      FakeCollectionRepository(
        collections: const [CollectionEntity(id: 1, name: 'Shop'), CollectionEntity(id: 2, name: 'Empty')],
        folders: {
          1: [folderEntity(10, name: 'Users'), folderEntity(11, parent: 10, name: 'Admin')],
        },
      ),
      requests,
      FakeResponseExampleRepository({
        100: [_example(2, 100, 'Second', status: 404, body: '{"error": "nope"}'), _example(1, 100, 'First', body: '{"users": []}')],
      }),
      const FakeCollectionVariableRepository({
        1: [
          CollectionVariableEntity(id: 1, collectionId: 1, key: 'baseUrl', value: 'https://api.example.com', enabled: true),
          CollectionVariableEntity(id: 2, collectionId: 1, key: 'off', value: 'x', enabled: false),
          CollectionVariableEntity(id: 3, collectionId: 1, key: '  ', value: 'blank', enabled: true),
        ],
      }),
      FakeCollectionAuthRepository({
        1: const RequestAuth(type: AuthType.basic, basicUsername: 'u', basicPassword: _secretPassword).toJsonString(),
      }),
      docs,
      tags,
    );
  });

  tearDown(() => tags.close());

  test('assembles the tree: folders first, requests in their folder, strays at the top level', () async {
    final model = await useCase(1);

    expect(model.name, 'Shop');
    expect(model.folders.map((f) => f.name), ['Users']);
    final users = model.folders.single;
    expect(users.folders.map((f) => f.name), ['Admin']);
    expect(users.folders.single.requests.map((r) => r.name), ['Ban user']);
    expect(users.requests.map((r) => r.name), ['List users']);
    expect(model.requests.map((r) => r.name), ['Health', 'Orphan']);
  });

  test('carries descriptions and tags of the collection, folders and requests', () async {
    final model = await useCase(1);
    final users = model.folders.single;
    final list = users.requests.single;

    expect(model.description, 'About the shop');
    expect(model.tags, ['v2']);
    expect(users.description, 'User endpoints');
    expect(users.tags, ['users']);
    expect(list.description, 'Lists users');
    expect(list.tags, ['Beta', 'read']);
    expect(users.folders.single.description, '');
    expect(users.folders.single.tags, isEmpty);
  });

  test('keeps enabled headers and parameters with a name, and enabled variables', () async {
    final model = await useCase(1);
    final list = model.folders.single.requests.single;

    expect(list.headers.map((h) => (h.key, h.value)), [('Accept', 'application/json')]);
    expect(list.queryParams.map((p) => (p.key, p.value)), [('page', '1')]);
    expect(model.variables.map((v) => (v.key, v.value)), [('baseUrl', 'https://api.example.com')]);
  });

  test('maps the method, url and body', () async {
    final model = await useCase(1);
    final list = model.folders.single.requests.single;

    expect(list.method, 'GET');
    expect(list.url, '{{baseUrl}}/users');
    expect(list.body!.typeLabel, 'JSON');
    expect(list.body!.language, 'json');
    expect(list.body!.text, '{"a": 1}');
    expect(model.requests.first.method, 'GET');
    expect(model.requests.last.method, 'PUT');
    expect(model.requests.first.body, isNull);
  });

  test('lists saved examples oldest first', () async {
    final model = await useCase(1);
    final examples = model.folders.single.requests.single.examples;

    expect(examples.map((e) => (e.name, e.statusCode)), [('First', 200), ('Second', 404)]);
    expect(examples.first.body, '{"users": []}');
  });

  group('authentication is only ever a type', () {
    test('a request shows its own type', () async {
      final model = await useCase(1);
      expect(model.folders.single.requests.single.authSummary, 'Bearer Token');
    });

    test('an inheriting request shows what it inherits from the collection', () async {
      final model = await useCase(1);
      expect(model.folders.single.folders.single.requests.single.authSummary, 'Basic Auth (inherited from the collection)');
    });

    test('the collection shows its default type; a request without auth shows nothing', () async {
      final model = await useCase(1);
      expect(model.authSummary, 'Basic Auth');
      expect(model.requests.first.authSummary, '');
    });

    test('inheriting with no collection default shows nothing', () async {
      final none = BuildApiDocsUseCase(
        FakeCollectionRepository(collections: const [CollectionEntity(id: 1, name: 'Shop')]),
        FakeRequestRepository({
          1: [requestEntity(1, auth: const RequestAuth(type: AuthType.inherit))],
        }),
        const FakeResponseExampleRepository(),
        const FakeCollectionVariableRepository(),
        const FakeCollectionAuthRepository(),
        docs,
        tags,
      );
      final model = await none(1);
      expect(model.authSummary, '');
      expect(model.requests.single.authSummary, '');
    });

    test('a corrupt stored collection default is ignored, not fatal', () async {
      final broken = BuildApiDocsUseCase(
        FakeCollectionRepository(collections: const [CollectionEntity(id: 1, name: 'Shop')]),
        FakeRequestRepository({
          1: [requestEntity(1, auth: const RequestAuth(type: AuthType.inherit))],
        }),
        const FakeResponseExampleRepository(),
        const FakeCollectionVariableRepository(),
        const FakeCollectionAuthRepository({1: 'not json {'}),
        docs,
        tags,
      );
      final model = await broken(1);
      expect(model.authSummary, '');
      expect(model.requests.single.authSummary, '');
    });

    test('no credential from the collection or its requests reaches either output', () async {
      final model = await useCase(1);
      for (final output in [ApiDocsGenerator.toMarkdown(model), ApiDocsGenerator.toHtml(model)]) {
        for (final secret in [_secretBearer, _secretPassword]) {
          expect(output, isNot(contains(secret)));
        }
        expect(output, contains('Bearer Token'));
        expect(output, contains('Basic Auth'));
      }
    });

    test('a token typed into a header or parameter by hand is masked too', () async {
      final leaky = BuildApiDocsUseCase(
        FakeCollectionRepository(collections: const [CollectionEntity(id: 1, name: 'Shop')]),
        FakeRequestRepository({
          1: [
            requestEntity(
              1,
              url: 'https://x/?api_key=$_secretApiKey',
              headers: [_kv('Authorization', 'Bearer $_secretBearer')],
              queryParams: [_kv('api_key', _secretApiKey)],
            ),
          ],
        }),
        const FakeResponseExampleRepository(),
        const FakeCollectionVariableRepository(),
        const FakeCollectionAuthRepository(),
        docs,
        tags,
      );
      final model = await leaky(1);
      for (final output in [ApiDocsGenerator.toMarkdown(model), ApiDocsGenerator.toHtml(model)]) {
        expect(output, isNot(contains(_secretApiKey)));
        expect(output, isNot(contains(_secretBearer)));
      }
    });
  });

  group('bodies', () {
    Future<List<Object?>> bodiesOf(List<RequestBody> bodies) async {
      final useCase = BuildApiDocsUseCase(
        FakeCollectionRepository(collections: const [CollectionEntity(id: 1, name: 'Shop')]),
        FakeRequestRepository({
          1: [for (var i = 0; i < bodies.length; i++) requestEntity(i + 1, body: bodies[i])],
        }),
        const FakeResponseExampleRepository(),
        const FakeCollectionVariableRepository(),
        const FakeCollectionAuthRepository(),
        docs,
        tags,
      );
      final model = await useCase(1);
      return [
        for (final r in model.requests)
          r.body == null ? null : (r.body!.typeLabel, r.body!.language, r.body!.text, r.body!.variablesText, r.body!.fields.length),
      ];
    }

    test('each kind is described, empty ones are left out', () async {
      expect(
        await bodiesOf([
          const RequestBody(),
          const RequestBody(type: BodyType.raw, rawText: '   '),
          const RequestBody(type: BodyType.raw, rawContentType: RawContentType.xml, rawText: '<a/>'),
          const RequestBody(type: BodyType.raw, rawContentType: RawContentType.text, rawText: 'hi'),
          RequestBody(type: BodyType.formData, formFields: [_kv('a', '1'), _kv('b', '2', enabled: false)]),
          RequestBody(type: BodyType.formData, formFields: [_kv('b', '2', enabled: false)]),
          RequestBody(type: BodyType.urlEncoded, urlEncodedFields: [_kv('q', 'x')]),
          const RequestBody(type: BodyType.graphql, graphqlQuery: '{ me }', graphqlVariables: '{"id": 1}'),
          const RequestBody(type: BodyType.graphql, graphqlQuery: '{ me }'),
          const RequestBody(type: BodyType.graphql, graphqlQuery: '  '),
        ]),
        [
          null,
          null,
          ('XML', 'xml', '<a/>', '', 0),
          ('Text', '', 'hi', '', 0),
          ('Form Data', '', '', '', 1),
          null,
          ('x-www-form-urlencoded', '', '', '', 1),
          ('GraphQL', 'graphql', '{ me }', '{"id": 1}', 0),
          ('GraphQL', 'graphql', '{ me }', '', 0),
          null,
        ],
      );
    });
  });

  test('an unknown collection is reported', () async {
    await expectLater(useCase(42), throwsA(isA<NotFoundException>()));
  });

  test('a collection with nothing in it still produces a document', () async {
    final model = await useCase(2);
    expect(model.name, 'Empty');
    expect(model.folders, isEmpty);
    expect(model.requests, isEmpty);
    expect(ApiDocsGenerator.toMarkdown(model), '# Empty\n');
  });

  test('a loop in the folder tree does not repeat folders or hang', () async {
    final looped = BuildApiDocsUseCase(
      FakeCollectionRepository(
        collections: const [CollectionEntity(id: 1, name: 'Loop')],
        folders: {
          1: [folderEntity(1, parent: 2), folderEntity(2, parent: 1)],
        },
      ),
      FakeRequestRepository({
        1: [requestEntity(1, folderId: 1)],
      }),
      const FakeResponseExampleRepository(),
      const FakeCollectionVariableRepository(),
      const FakeCollectionAuthRepository(),
      docs,
      tags,
    );
    final model = await looped(1);
    expect(model.folders, isEmpty);
    expect(model.requests.map((r) => r.name), ['Request 1']);
  });

  group('CollectionDocsViewModel', () {
    late List<({String fileName, String text, String mimeType})> saved;
    late String? savedPath;
    late Object? saveFailure;

    setUp(() {
      saved = [];
      savedPath = r'C:\Downloads\Shop docs.md';
      saveFailure = null;
    });

    CollectionDocsViewModel viewModel() => CollectionDocsViewModel(
          useCase,
          saveFile: ({required String fileName, required Uint8List bytes, required String mimeType}) async {
            final failure = saveFailure;
            if (failure != null) throw failure;
            saved.add((fileName: fileName, text: utf8.decode(bytes), mimeType: mimeType));
            return savedPath;
          },
        );

    test('builds the markdown for the preview and copying', () async {
      final vm = viewModel();
      expect(vm.isReady, isFalse);
      final loading = vm.load(1);
      expect(vm.isLoading, isTrue);
      await loading;

      expect(vm.isLoading, isFalse);
      expect(vm.isReady, isTrue);
      expect(vm.error, isNull);
      expect(vm.markdown, startsWith('# Shop\n'));
      expect(vm.markdown, contains('### List users'));
      vm.dispose();
    });

    test('an unknown collection ends in an error message', () async {
      final vm = viewModel();
      await vm.load(42);

      expect(vm.isLoading, isFalse);
      expect(vm.isReady, isFalse);
      expect(vm.error, 'Collection not found.');
      vm.dispose();
    });

    test('saves the markdown as a .md file named after the collection', () async {
      final vm = viewModel();
      await vm.load(1);

      final message = await vm.saveMarkdown();

      expect(message, r'Saved to C:\Downloads\Shop docs.md');
      expect(saved.single.fileName, 'Shop docs.md');
      expect(saved.single.mimeType, 'text/markdown;charset=utf-8');
      expect(saved.single.text, vm.markdown);
      vm.dispose();
    });

    test('saves a self-contained .html page with no credentials in it', () async {
      final vm = viewModel();
      await vm.load(1);

      await vm.saveHtml();

      expect(saved.single.fileName, 'Shop docs.html');
      expect(saved.single.mimeType, 'text/html;charset=utf-8');
      expect(saved.single.text, startsWith('<!doctype html>'));
      expect(saved.single.text, isNot(contains(_secretBearer)));
      vm.dispose();
    });

    test('on the web, where the browser owns the download, it says a download started', () async {
      savedPath = null;
      final vm = viewModel();
      await vm.load(1);

      expect(await vm.saveMarkdown(), 'Download started');
      vm.dispose();
    });

    test('a failing write is reported instead of thrown', () async {
      saveFailure = 'read-only disk';
      final vm = viewModel();
      await vm.load(1);

      expect(await vm.saveMarkdown(), 'Could not save the file: read-only disk');
      expect(await vm.saveHtml(), 'Could not save the file: read-only disk');
      vm.dispose();
    });

    test('nothing is saved before the docs are ready', () async {
      final vm = viewModel();

      expect(await vm.saveMarkdown(), 'There is nothing to save yet');
      expect(saved, isEmpty);
      vm.dispose();
    });

    test('a collection name is made safe to use as a file name', () async {
      final tricky = BuildApiDocsUseCase(
        FakeCollectionRepository(collections: const [CollectionEntity(id: 1, name: r'../a:b/c\d?')]),
        FakeRequestRepository(),
        const FakeResponseExampleRepository(),
        const FakeCollectionVariableRepository(),
        const FakeCollectionAuthRepository(),
        docs,
        tags,
      );
      final vm = CollectionDocsViewModel(
        tricky,
        saveFile: ({required String fileName, required Uint8List bytes, required String mimeType}) async {
          saved.add((fileName: fileName, text: '', mimeType: mimeType));
          return null;
        },
      );
      await vm.load(1);
      await vm.saveMarkdown();

      expect(saved.single.fileName, matches(RegExp(r'^[^/\\:?]+\.md$')));
      vm.dispose();
    });

    test('a load that finishes after dispose does not notify', () async {
      final vm = viewModel();
      final loading = vm.load(1);
      vm.dispose();
      await loading;
    });
  });
}
