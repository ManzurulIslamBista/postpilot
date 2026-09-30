import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/git_sync/data/repositories/entity_uid_registry.dart';
import 'package:postpilot/features/git_sync/data/repositories/git_link_repository_impl.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_link.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';

const _v4Tables = [
  'entity_uids',
  'git_links',
  'git_base_entries',
  'setting_entries',
  'request_setting_entries',
  'entity_docs',
  'entity_tags',
];

void main() {
  group('with an in-memory database', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('setTags trims, drops empties and dedupes ignoring case, keeping the first spelling', () async {
      final tags = db.entityTagsDao;
      await tags.setTags('request', 1, ['  Api ', 'api', '', '   ', 'Auth', 'AUTH', 'beta']);
      expect(await tags.tagsOf('request', 1), ['Api', 'Auth', 'beta']);

      await tags.setTags('request', 2, ['BETA', 'zeta']);
      await tags.setTags('folder', 1, ['beta']);
      expect(await tags.localIdsWithTag('request', ' Beta '), {1, 2});
      expect(await tags.tagsByLocalId('request'), {
        1: ['Api', 'Auth', 'beta'],
        2: ['BETA', 'zeta'],
      });
      expect(await tags.watchAllTags().first, ['Api', 'Auth', 'BETA', 'zeta']);

      await tags.setTags('request', 1, []);
      expect(await tags.tagsOf('request', 1), isEmpty);
      expect(await tags.tagsOf('folder', 1), ['beta']);
    });

    test('entity uids: put upserts, lookups are per kind, a uid belongs to one entity', () async {
      final uids = db.entityUidsDao;
      expect(await uids.uidOf('request', 1), isNull);
      await uids.put('request', 1, 'u-1');
      await uids.put('folder', 1, 'u-2');
      expect(await uids.uidOf('request', 1), 'u-1');
      expect(await uids.localIdOf('folder', 'u-2'), 1);
      expect(await uids.localIdOf('request', 'u-2'), isNull);

      await uids.put('request', 1, 'u-3');
      expect(await uids.uidsByLocalId('request'), {1: 'u-3'});
      expect(await uids.localIdsByUid('request'), {'u-3': 1});

      await uids.putIfAbsent('request', 1, 'u-4');
      expect(await uids.uidOf('request', 1), 'u-3');

      await expectLater(uids.put('request', 2, 'u-3'), throwsA(anything));
    });

    test('uid registry hands out one stable uuid per entity and adopts remote uids', () async {
      final registry = EntityUidRegistry(db.entityUidsDao);
      final uid = await registry.uidFor(SyncKind.request, 7);
      expect(uid, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(await registry.uidFor(SyncKind.request, 7), uid);
      expect(await registry.localIdFor(SyncKind.request, uid), 7);
      expect(await registry.localIdFor(SyncKind.folder, uid), isNull);

      final concurrent = await Future.wait([for (var i = 0; i < 5; i++) registry.uidFor(SyncKind.folder, 3)]);
      expect(concurrent.toSet(), hasLength(1));

      await registry.adopt(SyncKind.request, 7, 'remote-uid');
      expect(await registry.uidFor(SyncKind.request, 7), 'remote-uid');
      expect(await registry.localIdFor(SyncKind.request, uid), isNull);
      expect(await registry.uidsFor(SyncKind.request), {7: 'remote-uid'});
    });

    test('git link repository saves, updates, stores base entries and removes', () async {
      final repo = GitLinkRepositoryImpl(db.gitLinksDao);
      final collectionId = await db.collectionsDao.createCollection('c');
      const ref = RepoRef(provider: GitProvider.github, owner: 'octo', repo: 'api');

      final saved = await repo.save(GitLink(id: 0, collectionId: collectionId, repo: ref, branch: 'main', basePath: ''));
      expect(saved.id, greaterThan(0));
      expect(saved.repo, ref);
      expect(saved.lastSyncedSha, isNull);
      expect(saved.lastSyncedAt, isNull);
      expect(saved.includeSecrets, isFalse);
      expect(await repo.readBase(saved.id), isEmpty);

      final syncedAt = DateTime.utc(2026, 5, 1, 12, 30, 15);
      final updated = await repo.save(
        saved.copyWith(branch: 'dev', basePath: 'apis/v1', lastSyncedSha: 'abc123', lastSyncedAt: syncedAt, includeSecrets: true),
      );
      expect(updated.id, saved.id);
      final found = (await repo.findByCollection(collectionId))!;
      expect(found.id, saved.id);
      expect(found.branch, 'dev');
      expect(found.basePath, 'apis/v1');
      expect(found.lastSyncedSha, 'abc123');
      expect(found.lastSyncedAt!.isAtSameMomentAs(syncedAt), isTrue);
      expect(found.includeSecrets, isTrue);
      expect((await repo.watchByCollection(collectionId).first)!.branch, 'dev');
      expect(await repo.watchLinkedCollectionIds().first, {collectionId});

      final requestDoc = SyncDoc(
        uid: 'r1',
        kind: SyncKind.request,
        parentUid: 'c1',
        name: 'List',
        order: 2,
        data: {
          'method': 'get',
          'headers': [
            {'key': 'a', 'value': 'b'},
          ],
        },
      );
      final collectionDoc = SyncDoc(uid: 'c1', kind: SyncKind.collection, parentUid: null, name: 'c');
      await repo.writeBase(saved.id, {
        'r1': BaseEntry(doc: requestDoc, path: 'list.json', blobSha: 'sha1'),
        'c1': BaseEntry(doc: collectionDoc, path: 'collection.json', blobSha: 'sha0'),
      });
      var base = await repo.readBase(saved.id);
      expect(base.keys, unorderedEquals(['r1', 'c1']));
      expect(base['r1']!.doc, requestDoc);
      expect(base['r1']!.path, 'list.json');
      expect(base['r1']!.blobSha, 'sha1');
      expect(base['c1']!.doc.parentUid, isNull);

      await repo.writeBase(saved.id, {'r1': BaseEntry(doc: requestDoc, path: 'moved.json', blobSha: 'sha2')});
      base = await repo.readBase(saved.id);
      expect(base.keys, ['r1']);
      expect(base['r1']!.path, 'moved.json');

      await repo.remove(collectionId);
      expect(await repo.findByCollection(collectionId), isNull);
      expect(await repo.readBase(saved.id), isEmpty);
      expect(await db.select(db.gitBaseEntries).get(), isEmpty);
      expect(await repo.watchLinkedCollectionIds().first, isEmpty);
    });

    test('a collection has at most one git link, and deleting it removes link and base', () async {
      final repo = GitLinkRepositoryImpl(db.gitLinksDao);
      final collectionId = await db.collectionsDao.createCollection('c');
      const ref = RepoRef(provider: GitProvider.github, owner: 'octo', repo: 'api');
      final link = GitLink(id: 0, collectionId: collectionId, repo: ref, branch: 'main', basePath: '');
      final saved = await repo.save(link);
      await repo.writeBase(saved.id, {
        'c1': BaseEntry(
          doc: SyncDoc(uid: 'c1', kind: SyncKind.collection, parentUid: null, name: 'c'),
          path: 'collection.json',
          blobSha: 'sha0',
        ),
      });

      await expectLater(repo.save(link), throwsA(anything));

      await db.collectionsDao.deleteCollection(collectionId);
      expect(await db.select(db.gitLinks).get(), isEmpty);
      expect(await db.select(db.gitBaseEntries).get(), isEmpty);
    });

    test('settings, request settings and entity docs round-trip', () async {
      final settings = db.settingsDao;
      expect(await settings.get('theme'), isNull);
      await settings.put('theme', 'dark');
      await settings.put('theme', 'light');
      expect(await settings.get('theme'), 'light');
      expect(await settings.watch('theme').first, 'light');
      await settings.remove('theme');
      expect(await settings.get('theme'), isNull);

      final collectionId = await db.collectionsDao.createCollection('c');
      final requestId = await db.requestsDao.createRequest(
        RequestsCompanion.insert(collectionId: collectionId, name: 'r'),
      );
      final requestSettings = db.requestSettingsDao;
      expect(await requestSettings.get(requestId), isNull);
      await requestSettings.put(requestId, '{"a":1}');
      await requestSettings.put(requestId, '{"a":2}');
      expect(await requestSettings.get(requestId), '{"a":2}');
      await db.requestsDao.deleteRequest(requestId);
      expect(await requestSettings.get(requestId), isNull);

      final docs = db.entityDocsDao;
      expect(await docs.markdownOf('request', 5), '');
      await docs.setMarkdown('request', 5, '# Hi');
      await docs.setMarkdown('folder', 5, 'folder doc');
      expect(await docs.markdownOf('request', 5), '# Hi');
      expect(await docs.watchMarkdown('request', 5).first, '# Hi');
      expect(await docs.markdownByLocalId('request'), {5: '# Hi'});
      await docs.setMarkdown('request', 5, '');
      expect(await docs.markdownOf('request', 5), '');
      expect(await db.select(db.entityDocs).get(), hasLength(1));
    });
  });

  test('upgrading a v3 database creates the v4 tables and indexes and keeps existing data', () async {
    final dir = Directory.systemTemp.createTempSync('postpilot_v4_');
    final file = File('${dir.path}/upgrade.sqlite');
    try {
      final fresh = AppDatabase.forTesting(NativeDatabase(file));
      await fresh.collectionsDao.createCollection('kept');
      for (final table in _v4Tables.reversed) {
        await fresh.customStatement('DROP TABLE $table');
      }
      await fresh.customStatement('PRAGMA user_version = 3');
      await fresh.close();

      final upgraded = AppDatabase.forTesting(NativeDatabase(file));
      final names = (await upgraded.customSelect("SELECT name FROM sqlite_master WHERE type IN ('table', 'index')").get())
          .map((row) => row.read<String>('name'))
          .toSet();
      expect(names, containsAll([..._v4Tables, 'entity_uids_uid', 'entity_tags_tag']));
      expect((await upgraded.collectionsDao.watchAllCollections().first).map((c) => c.name), ['kept']);

      await upgraded.entityTagsDao.setTags('request', 1, ['a']);
      expect(await upgraded.entityTagsDao.tagsOf('request', 1), ['a']);
      await upgraded.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
