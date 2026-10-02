import 'dart:convert';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/git_sync/data/repositories/drift_git_state_store.dart';
import 'package:postpilot/features/import_export/domain/services/backup_codec.dart';
import 'support/drift_repos.dart';
import 'support/in_memory_import_export_fakes.dart';

/// A collection linked to a Git repository keeps that link, and everything the
/// sync engine remembers about it, when the workspace is written to a file and
/// read back: that is what makes several workplaces, each with its own linked
/// collections, safe to switch between.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DriftRepos repos;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
  });

  tearDown(() => db.close());

  const baseDocs = {
    'u-shop': ('shop/collection.json', 'blob-shop', '{"uid":"u-shop","kind":"collection","name":"Shop"}'),
    'u-users': ('shop/users/_folder.json', 'blob-users', '{"uid":"u-users","kind":"folder","name":"Users"}'),
    'u-list': ('shop/users/list.request.json', 'blob-list', '{"uid":"u-list","kind":"request","name":"List users"}'),
    'u-health': ('shop/health.request.json', 'blob-health', '{"uid":"u-health","kind":"request","name":"Health"}'),
  };

  /// Collection "Shop" (folder Users with "List users", plus "Health") linked the
  /// way a connect and a first push leave it.
  Future<int> seedLinkedShop({String branch = 'main', String sha = 'abc123'}) async {
    final shop = await repos.collectionRepository.createCollection('Shop');
    final users = await repos.collectionRepository.createFolder(collectionId: shop, name: 'Users');
    final list = await repos.requestRepository.createRequest(collectionId: shop, folderId: users, name: 'List users');
    final health = await repos.requestRepository.createRequest(collectionId: shop, name: 'Health');

    final linkId = await db.gitLinksDao.insertLink(GitLinksCompanion.insert(
      collectionId: shop,
      provider: 'github',
      owner: 'acme',
      repo: 'api',
      branch: branch,
      basePath: const Value('shop'),
      lastSyncedSha: Value(sha),
      lastSyncedAt: Value(DateTime.utc(2026, 10, 1, 12)),
      includeSecrets: const Value(true),
    ));
    await db.gitLinksDao.replaceBase(linkId, [
      for (final e in baseDocs.entries)
        GitBaseEntriesCompanion.insert(linkId: linkId, uid: e.key, path: e.value.$1, blobSha: e.value.$2, docJson: e.value.$3),
    ]);
    await db.entityUidsDao.put('collection', shop, 'u-shop');
    await db.entityUidsDao.put('folder', users, 'u-users');
    await db.entityUidsDao.put('request', list, 'u-list');
    await db.entityUidsDao.put('request', health, 'u-health');
    return shop;
  }

  /// What the sync engine would find: the link, its base, and which uid each entity has, by name.
  Future<Map<String, Object?>> gitStateOf(AppDatabase database, DriftRepos r, String collectionName) async {
    final loaded = (await r.loader.loadAll()).firstWhere((c) => c.collection.name == collectionName);
    final link = await database.gitLinksDao.findByCollection(loaded.collection.id);
    return {
      'link': link == null
          ? null
          : '${link.provider} ${link.owner}/${link.repo}@${link.branch} path=${link.basePath} sha=${link.lastSyncedSha} '
              'at=${link.lastSyncedAt?.toUtc().toIso8601String()} secrets=${link.includeSecrets}',
      'base': link == null
          ? null
          : {for (final b in await database.gitLinksDao.baseEntries(link.id)) b.uid: (b.path, b.blobSha, b.docJson)},
      'collectionUid': await database.entityUidsDao.uidOf('collection', loaded.collection.id),
      'folderUids': {for (final f in loaded.folders) f.name: await database.entityUidsDao.uidOf('folder', f.id)},
      'requestUids': {for (final q in loaded.requests) q.name: await database.entityUidsDao.uidOf('request', q.id)},
    };
  }

  group('the file format', () {
    test('a backup the user exports carries no Git state, and stays version 2', () async {
      await seedLinkedShop();
      final service = repos.backupServiceWith(DriftGitStateStore(db));

      final exported = (await service.export()).text;

      expect(exported, isNot(contains('"git"')));
      expect(exported, isNot(contains('u-shop')));
      expect(jsonDecode(exported)['version'], 2);
    });

    test('a mirror of the database carries it, as version 3', () async {
      await seedLinkedShop();
      final snapshot = await repos.backupServiceWith(DriftGitStateStore(db)).snapshot(includeGit: true);

      final json = jsonDecode(BackupCodec.encode(snapshot, includeGit: true)) as Map<String, dynamic>;
      final shop = (json['collections'] as List).single as Map<String, dynamic>;

      expect(json['version'], BackupCodec.gitVersion);
      expect(shop['uid'], 'u-shop');
      expect((shop['git'] as Map)['owner'], 'acme');
      expect(((shop['git'] as Map)['base'] as List), hasLength(4));
      expect(((shop['folders'] as List).single as Map)['uid'], 'u-users');
      expect(((shop['requests'] as List).map((r) => (r as Map)['uid'])), unorderedEquals(['u-list', 'u-health']));
    });

    test('with no linked collection even the mirror is plain version 2', () async {
      await repos.collectionRepository.createCollection('Plain');
      final snapshot = await repos.backupServiceWith(DriftGitStateStore(db)).snapshot(includeGit: true);

      expect(jsonDecode(BackupCodec.encode(snapshot, includeGit: true))['version'], 2);
    });

    test('decoding restores the Git state exactly, and an older file without it still reads', () async {
      await seedLinkedShop();
      final snapshot = await repos.backupServiceWith(DriftGitStateStore(db)).snapshot(includeGit: true);

      final decoded = BackupCodec.decode(BackupCodec.encode(snapshot, includeGit: true)).collections.single;

      expect(decoded.uid, 'u-shop');
      expect(decoded.git!.branch, 'main');
      expect(decoded.git!.basePath, 'shop');
      expect(decoded.git!.lastSyncedSha, 'abc123');
      expect(decoded.git!.lastSyncedAt, DateTime.utc(2026, 10, 1, 12));
      expect(decoded.git!.includeSecrets, isTrue);
      expect({for (final b in decoded.git!.base) b.uid: b.doc}, {for (final e in baseDocs.entries) e.key: e.value.$3});
      expect(decoded.folderUids.values, ['u-users']);

      final v2 = BackupCodec.decode(BackupCodec.encode(snapshot)).collections.single;
      expect(v2.git, isNull);
      expect(v2.uid, isNull);
      expect(v2.requests.every((r) => r.uid == null), isTrue);
    });

    test('a damaged git section is dropped whole instead of half applied', () {
      Map<String, dynamic> file(Object? git) => {
            'format': 'postpilot-backup',
            'version': 3,
            'collections': [
              {
                'name': 'Shop',
                'uid': 'u-shop',
                'git': git,
                'folders': [],
                'requests': [
                  {'name': 'A', 'method': 'get', 'url': 'x', 'uid': 'u-a'},
                ],
              },
            ],
          };
      final goodBase = {'uid': 'u', 'path': 'p', 'blobSha': 's', 'doc': '{}'};
      final link = {'provider': 'github', 'owner': 'o', 'repo': 'r', 'branch': 'main'};

      BackupCollection decode(Object? git) => BackupCodec.decode(jsonEncode(file(git))).collections.single;

      expect(decode({...link, 'base': [goodBase]}).git, isNotNull);
      expect(decode({...link, 'base': [goodBase, {'uid': 'x'}]}).git, isNull, reason: 'a base entry is missing fields');
      expect(decode({...link, 'base': 'nope'}).git, isNull);
      expect(decode({'provider': 'github', 'owner': 'o'}).git, isNull, reason: 'no repo or branch');
      expect(decode('garbage').git, isNull);
      final unlinked = decode(null);
      expect(unlinked.uid, isNull, reason: 'a uid means nothing without its link');
      expect(unlinked.requests.single.uid, isNull);
    });

    test('a file from a newer app is refused instead of read with its links dropped', () {
      final text = jsonEncode({'format': 'postpilot-backup', 'version': 4, 'collections': []});

      expect(() => BackupCodec.decode(text), throwsA(anything));
    });
  });

  group('restoring into a database', () {
    Future<String> mirrorOfLinkedShop() async {
      await seedLinkedShop();
      final snapshot = await repos.backupServiceWith(DriftGitStateStore(db)).snapshot(includeGit: true);
      return BackupCodec.encode(snapshot, includeGit: true);
    }

    test('re-creates the link, the sync base and every uid on the new rows', () async {
      final text = await mirrorOfLinkedShop();
      final before = await gitStateOf(db, repos, 'Shop');

      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final otherRepos = DriftRepos(other);
      await otherRepos.backupServiceWith(DriftGitStateStore(other)).restore(text, restoreGit: true);

      expect(await gitStateOf(other, otherRepos, 'Shop'), before);
    });

    test('an ordinary restore (the user importing a backup) does not link anything', () async {
      final text = await mirrorOfLinkedShop();

      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final otherRepos = DriftRepos(other);
      await otherRepos.backupServiceWith(DriftGitStateStore(other)).restore(text);

      final state = await gitStateOf(other, otherRepos, 'Shop');
      expect(state['link'], isNull);
      expect((state['requestUids'] as Map).values, everyElement(isNull));
    });

    test('a collection whose uids another entity already owns comes back unlinked, never as a second claimant', () async {
      final text = await mirrorOfLinkedShop();
      // The same database still holds the original linked Shop: restoring on top must not link the copy too.
      await repos.backupServiceWith(DriftGitStateStore(db)).restore(text, restoreGit: true);

      final collections = await repos.loader.loadAll();
      final copy = collections.firstWhere((c) => c.collection.name == 'Shop (restored)');
      final original = collections.firstWhere((c) => c.collection.name == 'Shop');

      expect(await db.gitLinksDao.findByCollection(copy.collection.id), isNull);
      expect(await db.gitLinksDao.findByCollection(original.collection.id), isNotNull);
      expect(await db.entityUidsDao.uidOf('collection', original.collection.id), 'u-shop');
    });

    test('a link to a provider this app does not know is not recreated', () async {
      await seedLinkedShop();
      final snapshot = await repos.backupServiceWith(DriftGitStateStore(db)).snapshot(includeGit: true);
      final text = BackupCodec.encode(snapshot, includeGit: true).replaceFirst('"provider": "github"', '"provider": "gitea"');

      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final otherRepos = DriftRepos(other);
      await otherRepos.backupServiceWith(DriftGitStateStore(other)).restore(text, restoreGit: true);

      expect((await gitStateOf(other, otherRepos, 'Shop'))['link'], isNull);
    });

    test('two linked collections keep separate state', () async {
      await seedLinkedShop();
      final blog = await repos.collectionRepository.createCollection('Blog');
      await repos.requestRepository.createRequest(collectionId: blog, name: 'Posts');
      final blogLink = await db.gitLinksDao.insertLink(GitLinksCompanion.insert(
        collectionId: blog,
        provider: 'github',
        owner: 'acme',
        repo: 'blog-api',
        branch: 'develop',
        lastSyncedSha: const Value('def456'),
      ));
      await db.gitLinksDao.replaceBase(blogLink, [
        GitBaseEntriesCompanion.insert(linkId: blogLink, uid: 'u-blog', path: 'collection.json', blobSha: 'b9', docJson: '{"uid":"u-blog"}'),
      ]);
      await db.entityUidsDao.put('collection', blog, 'u-blog');
      final snapshot = await repos.backupServiceWith(DriftGitStateStore(db)).snapshot(includeGit: true);

      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final otherRepos = DriftRepos(other);
      await otherRepos.backupServiceWith(DriftGitStateStore(other)).restore(BackupCodec.encode(snapshot, includeGit: true), restoreGit: true);

      final shop = await gitStateOf(other, otherRepos, 'Shop');
      final blogState = await gitStateOf(other, otherRepos, 'Blog');
      expect(shop['link'], contains('acme/api@main'));
      expect(blogState['link'], contains('acme/blog-api@develop'));
      expect((blogState['base'] as Map).keys, ['u-blog']);
      expect((shop['base'] as Map).keys, hasLength(4));
    });
  });
}
