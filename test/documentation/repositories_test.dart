import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/documentation/data/repositories/documentation_repository_impl.dart';
import 'package:postpilot/features/documentation/data/repositories/tag_repository_impl.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/documentation/presentation/view_models/all_tags_view_model.dart';
import 'package:postpilot/features/documentation/presentation/view_models/tag_filter_view_model.dart';
import 'package:postpilot/features/documentation/presentation/view_models/tags_view_model.dart';

import 'support/fakes.dart';

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('condition never became true');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Listens to a stream and lets a test wait for the newest value to be one it expects.
final class _Recorder<T> {
  final events = <T>[];
  late final StreamSubscription<T> _subscription;

  _Recorder(Stream<T> stream) {
    _subscription = stream.listen(events.add);
  }

  Future<T> until(bool Function(T latest) accept) async {
    await _waitUntil(() => events.isNotEmpty && accept(events.last));
    return events.last;
  }

  Future<void> close() => _subscription.cancel();
}

void main() {
  late AppDatabase db;
  late DocumentationRepositoryImpl docs;
  late TagRepositoryImpl tags;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    docs = DocumentationRepositoryImpl(db.entityDocsDao);
    tags = TagRepositoryImpl(db.entityTagsDao);
  });

  tearDown(() => db.close());

  Future<int> collection() => db.collectionsDao.createCollection('Shop');
  Future<int> folder(int collectionId) => db.collectionsDao.createFolder(collectionId: collectionId, name: 'Folder');
  Future<int> request(int collectionId, {int? folderId}) => db.requestsDao.createRequest(
        RequestsCompanion.insert(collectionId: collectionId, name: 'Req', folderId: Value(folderId)),
      );

  test('EntityKind maps to the kind strings the tables use', () {
    expect(EntityKind.values.map((k) => k.dbValue), ['collection', 'folder', 'request']);
  });

  group('DocumentationRepositoryImpl', () {
    test('stores a description per kind and id', () async {
      await docs.setMarkdown(EntityKind.request, 1, 'request one');
      await docs.setMarkdown(EntityKind.folder, 1, 'folder one');
      await docs.setMarkdown(EntityKind.request, 2, 'request two');

      expect(await docs.markdownOf(EntityKind.request, 1), 'request one');
      expect(await docs.markdownOf(EntityKind.folder, 1), 'folder one');
      expect(await docs.markdownOf(EntityKind.collection, 1), '');
      expect(await docs.markdownByLocalId(EntityKind.request), {1: 'request one', 2: 'request two'});
      expect(await db.entityDocsDao.markdownOf('folder', 1), 'folder one');
    });

    test('an empty description removes the row', () async {
      await docs.setMarkdown(EntityKind.request, 1, 'x');
      await docs.setMarkdown(EntityKind.request, 1, '');

      expect(await docs.markdownByLocalId(EntityKind.request), isEmpty);
    });

    test('overwrites the previous text', () async {
      await docs.setMarkdown(EntityKind.request, 1, 'first');
      await docs.setMarkdown(EntityKind.request, 1, 'second');

      expect(await docs.markdownOf(EntityKind.request, 1), 'second');
    });
  });

  group('TagRepositoryImpl', () {
    test('setTags normalises and every read agrees', () async {
      await tags.setTags(EntityKind.request, 1, ['  Api ', 'api', '', 'Auth', 'AUTH', 'beta']);

      expect(await tags.tagsByLocalId(EntityKind.request), {
        1: ['Api', 'Auth', 'beta'],
      });
      expect(await tags.watchTags(EntityKind.request, 1).first, ['Api', 'Auth', 'beta']);
      expect(await db.entityTagsDao.tagsOf('request', 1), ['Api', 'Auth', 'beta']);
    });

    test('tags of different kinds with the same id stay apart', () async {
      await tags.setTags(EntityKind.request, 1, ['r']);
      await tags.setTags(EntityKind.folder, 1, ['f']);
      await tags.setTags(EntityKind.collection, 1, ['c']);

      expect(await tags.tagsByLocalId(EntityKind.request), {1: ['r']});
      expect(await tags.tagsByLocalId(EntityKind.folder), {1: ['f']});
      expect(await tags.tagsByLocalId(EntityKind.collection), {1: ['c']});
    });

    test('watchTagsByLocalId starts with everything and follows each change', () async {
      await tags.setTags(EntityKind.request, 1, ['a']);
      final recorder = _Recorder(tags.watchTagsByLocalId(EntityKind.request));

      expect(await recorder.until((m) => m.length == 1), {1: ['a']});
      await tags.setTags(EntityKind.request, 2, ['b']);
      expect(await recorder.until((m) => m.length == 2), {1: ['a'], 2: ['b']});
      await tags.setTags(EntityKind.request, 1, []);
      expect(await recorder.until((m) => m.length == 1 && m.containsKey(2)), {2: ['b']});
      await recorder.close();
    });

    test('a watcher that cancelled hears nothing more and nothing breaks', () async {
      final recorder = _Recorder(tags.watchTagsByLocalId(EntityKind.request));
      await recorder.until((_) => true);
      await recorder.close();
      final seen = recorder.events.length;

      await tags.setTags(EntityKind.request, 1, ['late']);
      await pumpEventQueue();

      expect(recorder.events, hasLength(seen));
    });

    group('watchAllTags', () {
      test('lists each tag once, one spelling, sorted', () async {
        final c = await collection();
        final a = await request(c);
        final b = await request(c);
        await tags.setTags(EntityKind.request, a, ['zeta', 'API']);
        await tags.setTags(EntityKind.request, b, ['api', 'beta']);

        expect(await tags.watchAllTags().first, ['API', 'beta', 'zeta']);
      });

      test('counts tags of every kind while their entity exists', () async {
        final c = await collection();
        final f = await folder(c);
        final r = await request(c);
        await tags.setTags(EntityKind.collection, c, ['on-collection']);
        await tags.setTags(EntityKind.folder, f, ['on-folder']);
        await tags.setTags(EntityKind.request, r, ['on-request']);

        expect(await tags.watchAllTags().first, ['on-collection', 'on-folder', 'on-request']);
      });

      test('ignores tags left behind by a deleted request, folder or collection', () async {
        final c = await collection();
        final f = await folder(c);
        final inFolder = await request(c, folderId: f);
        final alone = await request(c);
        await tags.setTags(EntityKind.request, alone, ['gone-with-request']);
        await tags.setTags(EntityKind.request, inFolder, ['gone-with-folder-tree']);
        await tags.setTags(EntityKind.folder, f, ['gone-with-folder']);
        await tags.setTags(EntityKind.collection, c, ['gone-with-collection']);
        final recorder = _Recorder(tags.watchAllTags());
        expect(await recorder.until((t) => t.length == 4), hasLength(4));

        await db.requestsDao.deleteRequest(alone);
        expect(await recorder.until((t) => t.length == 3), isNot(contains('gone-with-request')));

        await db.collectionsDao.deleteFolder(f);
        expect(await recorder.until((t) => t.length == 1), ['gone-with-collection']);

        await db.collectionsDao.deleteCollection(c);
        expect(await recorder.until((t) => t.isEmpty), isEmpty);
        await recorder.close();

        // The rows themselves stay (there is no foreign key); the plain DAO still sees them.
        expect(await db.entityTagsDao.watchAllTags().first, hasLength(4));
      });

      test('a tag on an entity that does not exist is not listed', () async {
        await tags.setTags(EntityKind.request, 999, ['ghost']);
        expect(await tags.watchAllTags().first, isEmpty);
      });

      test('is not repeated when only something unrelated, like a request name, changes', () async {
        final c = await collection();
        final r = await request(c);
        await tags.setTags(EntityKind.request, r, ['v2']);
        final recorder = _Recorder(tags.watchAllTags());
        await recorder.until((t) => t.length == 1);

        for (var i = 0; i < 3; i++) {
          await db.requestsDao.updateRequest(r, RequestsCompanion(name: Value('Renamed $i')));
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }

        expect(recorder.events, hasLength(1));
        await recorder.close();
      });

      test('follows tags being added and removed', () async {
        final c = await collection();
        final r = await request(c);
        final recorder = _Recorder(tags.watchAllTags());
        await recorder.until((t) => t.isEmpty);

        await tags.setTags(EntityKind.request, r, ['new']);
        expect(await recorder.until((t) => t.isNotEmpty), ['new']);

        await tags.setTags(EntityKind.request, r, []);
        expect(await recorder.until((t) => t.isEmpty), isEmpty);
        await recorder.close();
      });
    });
  });

  test('the tags editor state, the suggestions and the sidebar filter agree on the real stores', () async {
    final c = await collection();
    final r1 = await request(c);
    final r2 = await request(c);

    final one = TagsViewModel(tags, EntityKind.request, r1);
    final all = AllTagsViewModel(tags);
    final filter = TagFilterViewModel(
      tags,
      FakeCollectionRepository(collections: [CollectionEntity(id: c, name: 'Shop')]),
      FakeRequestRepository({
        c: [requestEntity(r1, collectionId: c), requestEntity(r2, collectionId: c)],
      }),
    );

    await one.add('v2');
    await _waitUntil(() => all.tags.contains('v2') && filter.allTags.contains('v2'));
    expect(all.tags, ['v2']);

    filter.toggleTag('v2');
    await _waitUntil(() => filter.matchingRequestIds?.isNotEmpty ?? false);
    expect(filter.matchingRequestIds, {r1});

    await tags.setTags(EntityKind.request, r2, ['v2', 'v3']);
    await _waitUntil(() => (filter.matchingRequestIds?.length ?? 0) == 2);
    expect(filter.matchingRequestIds, {r1, r2});
    await _waitUntil(() => all.tags.length == 2);
    expect(all.tags, ['v2', 'v3']);

    await db.requestsDao.deleteRequest(r2);
    await _waitUntil(() => all.tags.length == 1);
    expect(all.tags, ['v2']);

    one.dispose();
    all.dispose();
    filter.dispose();
  });
}
