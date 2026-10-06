import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/defaults/data/defaults_repository_impl.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/defaults/domain/services/defaults_resolver.dart';
import 'package:postpilot/features/defaults/domain/usecases/resolve_request_defaults_usecase.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';

import '../support/drift_repos.dart';

void main() {
  late AppDatabase db;
  late DefaultsRepositoryImpl repo;
  late DriftRepos repos;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DefaultsRepositoryImpl(db);
    repos = DriftRepos(db);
  });
  tearDown(() => db.close());

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle()).read<int>('n');

  KeyValueItem header(String key, String value, {bool enabled = true}) =>
      KeyValueItem(key: key, value: value, enabled: enabled);

  Future<int> folder(int collectionId, String name, {int? parent}) =>
      repos.collectionRepository.createFolder(collectionId: collectionId, parentFolderId: parent, name: name);

  group('a collection that never had any defaults', () {
    test('loads as empty, with no row created for it', () async {
      final shop = await repos.collectionRepository.createCollection('Shop');
      final orders = await folder(shop, 'Orders');

      final tree = await repo.loadTree(shop);
      expect(tree.isEmpty, isTrue);
      expect(tree.collectionName, 'Shop');
      expect((await repo.getCollection(shop)).isEmpty, isTrue);
      expect((await repo.getFolder(orders)).isEmpty, isTrue);
      final inherited = DefaultsResolver.resolve(tree.chainFor(orders));
      expect(inherited.headers, isEmpty);
      expect(inherited.auth, isNull);
      expect(inherited.tests, isEmpty);
      expect(await count('collection_defaults'), 0);
      expect(await count('folder_defaults'), 0);
    });

    test('an unknown collection loads as empty instead of failing', () async {
      final tree = await repo.loadTree(4242);
      expect(tree.isEmpty, isTrue);
      expect(tree.chainFor(7).scopes, hasLength(1));
    });
  });

  group('saving and loading', () {
    test('a folder keeps its headers, variables (with the secret flag), auth and tests', () async {
      final shop = await repos.collectionRepository.createCollection('Shop');
      final orders = await folder(shop, 'Orders');

      await repo.saveFolder(
        orders,
        LevelDefaults(
          headers: [header('X-Api-Version', '2'), header('X-Off', 'x', enabled: false)],
          variables: [DefaultVariable(key: 'region', value: 'eu'), DefaultVariable(key: 'apiKey', value: 'k-1', isSecret: true)],
          auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'folder-token'),
          assertions: [AssertionEntity(type: AssertionType.statusEquals, expected: '201')],
          extractors: [ExtractorEntity(path: r'$.id', variableKey: 'orderId')],
        ),
      );

      final loaded = await repo.getFolder(orders);
      expect([for (final h in loaded.headers) (h.key, h.value, h.enabled)], [('X-Api-Version', '2', true), ('X-Off', 'x', false)]);
      expect(loaded.variables, [DefaultVariable(key: 'region', value: 'eu'), DefaultVariable(key: 'apiKey', value: 'k-1', isSecret: true)]);
      expect(loaded.auth?.type, AuthType.bearer);
      expect(loaded.auth?.bearerToken, 'folder-token');
      expect(loaded.assertions.single.expected, '201');
      expect(loaded.extractors.single.variableKey, 'orderId');
      expect(await count('folder_defaults'), 1);
    });

    test('a collection keeps its headers and tests, and its auth comes from collection_auth', () async {
      final shop = await repos.collectionRepository.createCollection('Shop');
      await repos.collectionAuthRepository.setAuthJson(
        shop,
        const RequestAuth(type: AuthType.basic, basicUsername: 'ann', basicPassword: 'pw').toJsonString(),
      );
      await repo.saveCollection(
        shop,
        LevelDefaults(
          headers: [header('X-Tenant', 'acme')],
          // Variables and auth are not this table's: they must not be written to it.
          variables: [DefaultVariable(key: 'ignored')],
          auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'ignored'),
          assertions: [AssertionEntity(type: AssertionType.statusIn2xx)],
        ),
      );

      final own = await repo.getCollection(shop);
      expect(own.headers.single.key, 'X-Tenant');
      expect(own.variables, isEmpty);
      expect(own.auth, isNull);
      expect(own.assertions.single.type, AssertionType.statusIn2xx);

      final tree = await repo.loadTree(shop);
      expect(tree.collection.auth?.type, AuthType.basic);
      expect(tree.collection.auth?.basicUsername, 'ann');
    });

    test('a level that sets nothing keeps no row: saving it empty deletes the one it had', () async {
      final shop = await repos.collectionRepository.createCollection('Shop');
      final orders = await folder(shop, 'Orders');
      await repo.saveFolder(orders, LevelDefaults(headers: [header('A', '1')]));
      await repo.saveCollection(shop, LevelDefaults(headers: [header('B', '2')]));
      expect(await count('folder_defaults'), 1);
      expect(await count('collection_defaults'), 1);

      await repo.saveFolder(orders, LevelDefaults.empty);
      await repo.saveCollection(shop, LevelDefaults.empty);

      expect(await count('folder_defaults'), 0);
      expect(await count('collection_defaults'), 0);
    });

    test('saving twice replaces, never duplicates', () async {
      final shop = await repos.collectionRepository.createCollection('Shop');
      final orders = await folder(shop, 'Orders');
      await repo.saveFolder(orders, LevelDefaults(headers: [header('A', '1')]));
      await repo.saveFolder(orders, LevelDefaults(headers: [header('A', '2'), header('B', '3')]));

      expect(await count('folder_defaults'), 1);
      expect((await repo.getFolder(orders)).headers.map((h) => '${h.key}=${h.value}'), ['A=2', 'B=3']);
    });

    test('a row whose columns hold damaged text loads as empty, not as an error', () async {
      final shop = await repos.collectionRepository.createCollection('Shop');
      final orders = await folder(shop, 'Orders');
      await db.folderDefaultsDao.upsert(
        FolderDefaultsCompanion(
          folderId: Value(orders),
          headersJson: const Value('{{{'),
          variablesJson: const Value('"x"'),
          authJson: const Value('[]'),
          scriptsJson: const Value('nope'),
        ),
      );

      expect((await repo.getFolder(orders)).isEmpty, isTrue);
      expect((await repo.loadTree(shop)).folderDefaults, isEmpty);
    });
  });

  group('inheritance read from the database', () {
    test('three folders deep: each level adds, overrides and switches off', () async {
      final shop = await repos.collectionRepository.createCollection('Shop');
      final a = await folder(shop, 'A');
      final b = await folder(shop, 'B', parent: a);
      final c = await folder(shop, 'C', parent: b);
      await repo.saveCollection(shop, LevelDefaults(headers: [header('X-Level', 'collection'), header('X-Keep', 'k')]));
      await repo.saveFolder(a, LevelDefaults(headers: [header('X-Level', 'A')], variables: [DefaultVariable(key: 'who', value: 'A')]));
      await repo.saveFolder(b, LevelDefaults(headers: [header('X-Keep', '', enabled: false)], variables: [DefaultVariable(key: 'who', value: 'B')]));
      await repo.saveFolder(c, LevelDefaults(headers: [header('X-C', 'c')]));

      final inherited = DefaultsResolver.resolve((await repo.loadTree(shop)).chainFor(c));

      expect([for (final h in inherited.headers) '${h.item.key}=${h.item.value}@${h.origin.name}'], ['X-Level=A@A', 'X-C=c@C']);
      expect(inherited.variableScopes, [
        <String, String>{},
        {'who': 'B'},
        {'who': 'A'},
      ]);
    });

    test('a request moved between folders inherits from its new folder, even when the tab still holds the old one', () async {
      final shop = await repos.collectionRepository.createCollection('Shop');
      final a = await folder(shop, 'A');
      final b = await folder(shop, 'B');
      await repo.saveFolder(a, LevelDefaults(headers: [header('X-From', 'A')]));
      await repo.saveFolder(b, LevelDefaults(headers: [header('X-From', 'B')]));
      final id = await repos.requestRepository.createRequest(collectionId: shop, folderId: a, name: 'Get');
      final staleTab = (await repos.requestRepository.findById(id))!;
      final resolve = ResolveRequestDefaultsUseCase(repo);

      expect((await resolve(staleTab)).headers.single.item.value, 'A');

      await db.requestsDao.updateRequest(id, RequestsCompanion(folderId: Value(b)));

      expect(staleTab.folderId, a, reason: 'the entity in hand is stale on purpose');
      expect((await resolve(staleTab)).headers.single.item.value, 'B');

      await db.requestsDao.updateRequest(id, const RequestsCompanion(folderId: Value(null)));
      expect((await resolve(staleTab)).headers, isEmpty, reason: 'moved to the top level: no folder above it');
    });

    test('a request that is not stored uses the folder of the entity', () async {
      final shop = await repos.collectionRepository.createCollection('Shop');
      final a = await folder(shop, 'A');
      await repo.saveFolder(a, LevelDefaults(headers: [header('X-From', 'A')]));
      const unsaved = ApiRequestEntity(
        id: 9999,
        collectionId: 1,
        folderId: null,
        name: 'Ghost',
        method: HttpMethod.get,
        url: '',
        headers: [],
        queryParams: [],
        body: RequestBody.empty,
        auth: RequestAuth(),
      );
      final inherited = await ResolveRequestDefaultsUseCase(repo)
          .forRequest(requestId: unsaved.id, collectionId: shop, folderId: a);
      expect(inherited.headers.single.item.value, 'A');
    });
  });

  group('lifecycle', () {
    test('deleting a folder deletes its defaults and those of the folders inside it, and no others', () async {
      final shop = await repos.collectionRepository.createCollection('Shop');
      final keep = await folder(shop, 'Keep');
      final gone = await folder(shop, 'Gone');
      final inner = await folder(shop, 'Inner', parent: gone);
      for (final id in [keep, gone, inner]) {
        await repo.saveFolder(id, LevelDefaults(headers: [header('X', '$id')]));
      }

      await db.collectionsDao.deleteFolder(gone);

      expect(await count('folder_defaults'), 1);
      expect((await repo.getFolder(keep)).headers, hasLength(1));
    });

    test('deleting the collection deletes its defaults and its folders\'', () async {
      final shop = await repos.collectionRepository.createCollection('Shop');
      final other = await repos.collectionRepository.createCollection('Other');
      final a = await folder(shop, 'A');
      final z = await folder(other, 'Z');
      await repo.saveCollection(shop, LevelDefaults(headers: [header('S', '1')]));
      await repo.saveCollection(other, LevelDefaults(headers: [header('O', '1')]));
      await repo.saveFolder(a, LevelDefaults(headers: [header('A', '1')]));
      await repo.saveFolder(z, LevelDefaults(headers: [header('Z', '1')]));

      await repos.collectionRepository.deleteCollection(shop);

      expect(await count('collection_defaults'), 1);
      expect(await count('folder_defaults'), 1);
      expect((await repo.getCollection(other)).headers.single.key, 'O');
    });

    test('duplicating a collection copies its defaults and its nested folders\', and the copy is independent', () async {
      final shop = await repos.collectionRepository.createCollection('Shop');
      final a = await folder(shop, 'A');
      final b = await folder(shop, 'B', parent: a);
      await repo.saveCollection(shop, LevelDefaults(headers: [header('S', '1')], assertions: [AssertionEntity(type: AssertionType.statusIn2xx)]));
      await repo.saveFolder(a, LevelDefaults(variables: [DefaultVariable(key: 'k', value: 'a', isSecret: true)]));
      await repo.saveFolder(b, LevelDefaults(auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'b-token')));

      final copyId = await repos.collectionRepository.duplicateCollection(shop);

      final copy = await repo.loadTree(copyId);
      expect(copy.collection.headers.single.key, 'S');
      expect(copy.collection.assertions, hasLength(1));
      final copiedFolders = {for (final f in copy.folders) f.name: f};
      expect(copiedFolders.keys, {'A', 'B'});
      expect(copy.folderDefaults[copiedFolders['A']!.id]!.variables.single, DefaultVariable(key: 'k', value: 'a', isSecret: true));
      expect(copy.folderDefaults[copiedFolders['B']!.id]!.auth?.bearerToken, 'b-token');
      expect(copiedFolders['B']!.parentFolderId, copiedFolders['A']!.id);

      await repo.saveCollection(copyId, LevelDefaults(headers: [header('Changed', '2')]));
      expect((await repo.getCollection(shop)).headers.single.key, 'S', reason: 'the original is untouched');
      expect(await count('folder_defaults'), 4);
    });

    test('duplicating a folder copies its defaults and those of its sub-folders', () async {
      final shop = await repos.collectionRepository.createCollection('Shop');
      final a = await folder(shop, 'A');
      final b = await folder(shop, 'B', parent: a);
      await repo.saveFolder(a, LevelDefaults(headers: [header('X-A', '1')]));
      await repo.saveFolder(b, LevelDefaults(headers: [header('X-B', '2')]));

      final copyId = await repos.collectionRepository.duplicateFolder(a);

      final tree = await repo.loadTree(shop);
      final copy = tree.folders.firstWhere((f) => f.id == copyId);
      expect(copy.name, 'A copy');
      expect(tree.folderDefaults[copyId]!.headers.single.key, 'X-A');
      final copiedChild = tree.folders.firstWhere((f) => f.parentFolderId == copyId);
      expect(tree.folderDefaults[copiedChild.id]!.headers.single.key, 'X-B');
      expect(tree.folderDefaults[a]!.headers.single.key, 'X-A');
    });

    test('changes fires when a default of the collection is saved', () async {
      final shop = await repos.collectionRepository.createCollection('Shop');
      final a = await folder(shop, 'A');
      final fired = repo.changes(shop).first;

      await repo.saveFolder(a, LevelDefaults(headers: [header('X', '1')]));

      await fired.timeout(const Duration(seconds: 5));
    });
  });
}
