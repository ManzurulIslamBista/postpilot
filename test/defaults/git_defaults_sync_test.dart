// A collection's Git sync carries what it and its folders pass down: pushed, cloned, merged field by field.
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/collections/data/repositories/collection_repository_impl.dart';
import 'package:postpilot/features/defaults/data/defaults_repository_impl.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/git_sync/data/repositories/entity_uid_registry.dart';
import 'package:postpilot/features/git_sync/data/repositories/git_link_repository_impl.dart';
import 'package:postpilot/features/git_sync/data/repositories/local_collection_store_impl.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_sync_results.dart';
import 'package:postpilot/features/git_sync/domain/services/sync_engine.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_clone_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_commit_push_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_connect_usecase.dart';
import 'package:postpilot/features/git_sync/domain/usecases/git_pull_usecase.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';

import '../git_sync/fakes/fake_git_host.dart';

KeyValueItem _h(String key, String value, {bool enabled = true}) => KeyValueItem(key: key, value: value, enabled: enabled);

const _basePath = 'apis/shop';

/// One installation: its own database, the real store and the real Git use cases, one shared host.
final class _Device {
  final FakeGitHost host;
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  late final uids = EntityUidRegistry(db.entityUidsDao);
  late final store = LocalCollectionStoreImpl(db, uids);
  late final links = GitLinkRepositoryImpl(db.gitLinksDao);
  late final defaults = DefaultsRepositoryImpl(db);
  late final collections = CollectionRepositoryImpl(db.collectionsDao);
  late final engine = SyncEngine(host, store);
  late final connect = GitConnectUseCase(links, host, store);
  late final clone = GitCloneUseCase(host, store, links, engine);
  late final push = GitCommitPushUseCase(links, host, engine);
  late final pull = GitPullUseCase(links, store, host, engine);

  _Device(this.host);

  Future<PullResult> pullAll(int collectionId, [ConflictResolutions? resolutions]) =>
      pull(GitPullParams(collectionId: collectionId, resolutions: resolutions));

  Future<PushResult> pushAll(int collectionId) => push(GitCommitPushParams(collectionId: collectionId, message: 'Update'));

  Future<Map<String, int>> foldersByName(int collectionId) async =>
      {for (final f in await collections.watchFolders(collectionId).first) f.name: f.id};
}

String _file(FakeGitHost host, dynamic repo, String suffix) =>
    host.filesAt(repo).entries.firstWhere((e) => e.key.endsWith(suffix)).value;

void main() {
  late FakeGitHost host;
  late _Device alice;
  late _Device bob;

  setUp(() => host = FakeGitHost());

  Future<({int aliceShop, int aliceOrders, dynamic repo})> aliceWithDefaults({bool includeSecrets = false}) async {
    alice = _Device(host);
    addTearDown(alice.db.close);
    final repo = host.seedRepo('acme/shop');
    final shop = await alice.collections.createCollection('Shop');
    final orders = await alice.collections.createFolder(collectionId: shop, name: 'Orders');
    await alice.collections.createFolder(collectionId: shop, parentFolderId: orders, name: 'Archive');
    await alice.defaults.saveCollection(
      shop,
      LevelDefaults(
        headers: [_h('X-Tenant', 'acme'), _h('Authorization', 'Bearer collection-secret-token')],
        assertions: [AssertionEntity(type: AssertionType.statusIn2xx)],
      ),
    );
    await alice.defaults.saveFolder(
      orders,
      LevelDefaults(
        headers: [_h('X-Api-Version', '2')],
        variables: [DefaultVariable(key: 'region', value: 'eu'), DefaultVariable(key: 'tenantKey', value: 'folder-secret-value', isSecret: true)],
        auth: const RequestAuth(type: AuthType.bearer, bearerToken: 'folder-bearer-secret'),
      ),
    );
    await alice.connect(GitConnectParams(collectionId: shop, repo: repo, branch: 'main', basePath: _basePath, includeSecrets: includeSecrets));
    await alice.pushAll(shop);
    return (aliceShop: shop, aliceOrders: orders, repo: repo);
  }

  Future<int> bobClones(dynamic repo, {bool includeSecrets = false}) async {
    bob = _Device(host);
    addTearDown(bob.db.close);
    return (await bob.clone(GitCloneParams(repo: repo, branch: 'main', basePath: _basePath, includeSecrets: includeSecrets))).collectionId;
  }

  group('push', () {
    test('the collection doc carries its headers and tests, a folder doc its headers, variables, auth and tests', () async {
      final setup = await aliceWithDefaults(includeSecrets: true);

      final collection = jsonDecode(_file(host, setup.repo, 'collection.json')) as Map;
      expect((collection['headers'] as List).map((h) => h['key']), ['X-Tenant', 'Authorization']);
      expect((collection['tests']['assertions'] as List).single['type'], 'statusIn2xx');
      final orders = jsonDecode(host.filesAt(setup.repo).entries.firstWhere((e) => e.key.endsWith('_folder.json') && (jsonDecode(e.value) as Map)['name'] == 'Orders').value) as Map;
      expect((orders['headers'] as List).single['key'], 'X-Api-Version');
      expect((orders['variables'] as List).map((v) => v['key']), ['region', 'tenantKey']);
      expect((orders['variables'] as List).last['secret'], true);
      expect(orders['auth']['bearerToken'], 'folder-bearer-secret', reason: 'this link opted in to syncing secrets');
    });

    test('without the opt-in, credentials are blanked in the files and everything else is kept', () async {
      final setup = await aliceWithDefaults();

      final files = host.filesAt(setup.repo).values.join('\n');
      for (final secret in ['collection-secret-token', 'folder-secret-value', 'folder-bearer-secret']) {
        expect(files, isNot(contains(secret)), reason: secret);
      }
      final collection = jsonDecode(_file(host, setup.repo, 'collection.json')) as Map;
      final headers = {for (final h in collection['headers'] as List) h['key']: h['value']};
      expect(headers, {'X-Tenant': 'acme', 'Authorization': ''});
      expect(files, contains('"region"'));
      expect(files, contains('"eu"'));
    });

    test('a collection with no defaults pushes the same files it always did', () async {
      alice = _Device(host);
      addTearDown(alice.db.close);
      final repo = host.seedRepo('acme/shop');
      final shop = await alice.collections.createCollection('Shop');
      await alice.collections.createFolder(collectionId: shop, name: 'Orders');
      await alice.connect(GitConnectParams(collectionId: shop, repo: repo, branch: 'main', basePath: _basePath));
      await alice.pushAll(shop);

      final collection = jsonDecode(_file(host, repo, 'collection.json')) as Map;
      expect(collection.keys.toSet().intersection({'headers', 'tests', 'variables'}), isEmpty);
      final folder = jsonDecode(_file(host, repo, '_folder.json')) as Map;
      expect(folder.keys.toSet().intersection({'headers', 'tests', 'variables', 'auth'}), isEmpty);
    });
  });

  group('clone', () {
    test('brings the defaults along, with the secrets left blank when they were not synced', () async {
      final setup = await aliceWithDefaults();

      final bobShop = await bobClones(setup.repo);

      final tree = await bob.defaults.loadTree(bobShop);
      expect([for (final h in tree.collection.headers) (h.key, h.value)], [('X-Tenant', 'acme'), ('Authorization', '')]);
      expect(tree.collection.assertions.single.type, AssertionType.statusIn2xx);
      final orders = tree.folderDefaults[(await bob.foldersByName(bobShop))['Orders']]!;
      expect(orders.headers.single.key, 'X-Api-Version');
      expect(orders.variables, [DefaultVariable(key: 'region', value: 'eu'), DefaultVariable(key: 'tenantKey', value: '', isSecret: true)]);
      expect(orders.auth?.type, AuthType.bearer);
      expect(orders.auth?.bearerToken, '');
    });

    test('a clone with the opt-in gets the secrets too', () async {
      final setup = await aliceWithDefaults(includeSecrets: true);

      final bobShop = await bobClones(setup.repo, includeSecrets: true);

      final orders = (await bob.defaults.loadTree(bobShop)).folderDefaults[(await bob.foldersByName(bobShop))['Orders']]!;
      expect(orders.auth?.bearerToken, 'folder-bearer-secret');
      expect(orders.variables.last.value, 'folder-secret-value');
    });
  });

  group('pull', () {
    test('a teammate\'s change to a folder\'s defaults arrives, and a secret of ours that the files leave blank is kept', () async {
      final setup = await aliceWithDefaults();
      final bobShop = await bobClones(setup.repo);
      final bobOrders = (await bob.foldersByName(bobShop))['Orders']!;
      final theirs = await bob.defaults.getFolder(bobOrders);
      await bob.defaults.saveFolder(bobOrders, theirs.copyWith(headers: [...theirs.headers, _h('X-Added-By-Bob', '1')]));
      await bob.pushAll(bobShop);

      final result = await alice.pullAll(setup.aliceShop);

      expect(result, isA<PullApplied>());
      final mine = await alice.defaults.getFolder(setup.aliceOrders);
      expect(mine.headers.map((h) => h.key), ['X-Api-Version', 'X-Added-By-Bob']);
      expect(mine.auth?.bearerToken, 'folder-bearer-secret', reason: 'the token only this device has stays');
      expect(mine.variables.last.value, 'folder-secret-value');
      final collection = await alice.defaults.getCollection(setup.aliceShop);
      expect(collection.headers.last.value, 'Bearer collection-secret-token');
    });

    test('changes to different fields of one folder merge without a conflict', () async {
      final setup = await aliceWithDefaults();
      final bobShop = await bobClones(setup.repo);
      final bobOrders = (await bob.foldersByName(bobShop))['Orders']!;

      final mine = await alice.defaults.getFolder(setup.aliceOrders);
      await alice.defaults.saveFolder(setup.aliceOrders, mine.copyWith(headers: [...mine.headers, _h('X-From-Alice', 'a')]));
      final theirs = await bob.defaults.getFolder(bobOrders);
      await bob.defaults.saveFolder(bobOrders, theirs.copyWith(variables: [...theirs.variables, DefaultVariable(key: 'extra', value: 'b')]));
      await bob.pushAll(bobShop);

      final result = await alice.pullAll(setup.aliceShop);

      expect(result, isA<PullApplied>(), reason: 'headers and variables are different fields');
      final merged = await alice.defaults.getFolder(setup.aliceOrders);
      expect(merged.headers.map((h) => h.key), ['X-Api-Version', 'X-From-Alice']);
      expect(merged.variables.map((v) => v.key), ['extra', 'region', 'tenantKey'], reason: 'a doc keeps variables sorted by name');
      expect(merged.variables.last.value, 'folder-secret-value', reason: 'our own secret survives the merge');
    });

    test('both sides changing the same field is a conflict about that field, and either side can be kept', () async {
      final setup = await aliceWithDefaults();
      final bobShop = await bobClones(setup.repo);
      final bobOrders = (await bob.foldersByName(bobShop))['Orders']!;

      final mine = await alice.defaults.getFolder(setup.aliceOrders);
      await alice.defaults.saveFolder(setup.aliceOrders, mine.copyWith(headers: [_h('X-Api-Version', '3')]));
      final theirs = await bob.defaults.getFolder(bobOrders);
      await bob.defaults.saveFolder(bobOrders, theirs.copyWith(headers: [_h('X-Api-Version', '4')]));
      await bob.pushAll(bobShop);

      final conflicted = await alice.pullAll(setup.aliceShop);

      expect(conflicted, isA<PullConflicts>());
      final conflict = (conflicted as PullConflicts).conflicts.single;
      expect(conflict.name, 'Orders');
      expect(conflict.fields.map((f) => f.field), ['headers']);

      final resolved = await alice.pullAll(setup.aliceShop, {conflict.uid: ConflictChoice.remote});
      expect(resolved, isA<PullApplied>());
      expect((await alice.defaults.getFolder(setup.aliceOrders)).headers.single.value, '4');
    });

    test('the collection\'s own headers and tests merge too, and removing the last header removes the key', () async {
      final setup = await aliceWithDefaults();
      final bobShop = await bobClones(setup.repo);
      final bobCollection = await bob.defaults.getCollection(bobShop);
      await bob.defaults.saveCollection(bobShop, LevelDefaults(headers: const [], assertions: bobCollection.assertions));
      await bob.pushAll(bobShop);

      await alice.pullAll(setup.aliceShop);

      final collection = await alice.defaults.getCollection(setup.aliceShop);
      expect(collection.headers, isEmpty);
      expect(collection.assertions, hasLength(1));
    });
  });
}
