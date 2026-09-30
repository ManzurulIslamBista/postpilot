import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/documentation/domain/services/tag_matcher.dart';
import 'package:postpilot/features/documentation/domain/services/tag_normalizer.dart';
import 'package:postpilot/features/documentation/presentation/view_models/all_tags_view_model.dart';
import 'package:postpilot/features/documentation/presentation/view_models/tags_view_model.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';

import 'support/fakes.dart';

void main() {
  group('TagNormalizer', () {
    test('trims, drops blanks and sorts ignoring case', () {
      expect(TagNormalizer.normalise(['  beta ', '', '   ', 'Alpha', 'gamma']), ['Alpha', 'beta', 'gamma']);
    });

    test('collapses duplicates ignoring case to the first spelling', () {
      expect(TagNormalizer.normalise(['API', 'api', 'Api', 'auth', 'AUTH']), ['API', 'auth']);
    });

    test('same compares ignoring case and surrounding space', () {
      expect(TagNormalizer.same(' V2', 'v2 '), isTrue);
      expect(TagNormalizer.same('v2', 'v3'), isFalse);
    });

    test('agrees with what the fake store (a stand-in for the DAO) keeps', () async {
      final repo = FakeTagRepository();
      await repo.setTags(EntityKind.request, 1, ['  Api ', 'api', '', 'Auth', 'AUTH', 'beta']);
      expect(repo.tagsFor(EntityKind.request, 1), ['Api', 'Auth', 'beta']);
    });
  });

  group('TagsViewModel', () {
    late FakeTagRepository repo;
    late TagsViewModel vm;

    setUp(() async {
      repo = FakeTagRepository()..seed(EntityKind.request, 7, ['users']);
      vm = TagsViewModel(repo, EntityKind.request, 7);
      await pumpEventQueue();
    });

    tearDown(() async {
      vm.dispose();
      await repo.close();
    });

    test('starts with the stored tags', () {
      expect(vm.tags, ['users']);
    });

    test('add trims the tag and stores the normalised list', () async {
      await vm.add('  v2 ');
      expect(vm.tags, ['users', 'v2']);
      expect(repo.tagsFor(EntityKind.request, 7), ['users', 'v2']);
    });

    test('add keeps the list sorted ignoring case', () async {
      await vm.add('Alpha');
      await vm.add('zed');
      expect(vm.tags, ['Alpha', 'users', 'zed']);
    });

    test('a blank tag is ignored without a write', () async {
      await vm.add('   ');
      await vm.add('');
      expect(repo.writes, isEmpty);
      expect(vm.tags, ['users']);
    });

    test('a duplicate ignoring case is ignored and keeps the first spelling', () async {
      await vm.add('USERS');
      await vm.add(' users ');
      expect(repo.writes, isEmpty);
      expect(vm.tags, ['users']);
    });

    test('remove ignores case and only writes when something changed', () async {
      await vm.add('v2');
      await vm.remove('USERS');
      expect(vm.tags, ['v2']);
      expect(repo.tagsFor(EntityKind.request, 7), ['v2']);
      final writes = repo.writes.length;
      await vm.remove('missing');
      expect(repo.writes, hasLength(writes));
    });

    test('tags of another entity are not touched', () async {
      repo.seed(EntityKind.folder, 7, ['folder-tag']);
      await vm.add('v2');
      expect(repo.tagsFor(EntityKind.folder, 7), ['folder-tag']);
    });

    test('two quick adds both stick and the chips never step back', () async {
      final shown = <List<String>>[];
      vm.addListener(() => shown.add(vm.tags));

      final first = vm.add('a');
      final second = vm.add('b');
      await Future.wait([first, second]);
      await pumpEventQueue();

      expect(vm.tags, ['a', 'b', 'users']);
      expect(repo.tagsFor(EntityKind.request, 7), ['a', 'b', 'users']);
      for (var i = 1; i < shown.length; i++) {
        expect(shown[i].length, greaterThanOrEqualTo(shown[i - 1].length), reason: '$shown');
      }
    });

    test('follows a change made elsewhere', () async {
      await repo.setTags(EntityKind.request, 7, ['users', 'from-git']);
      await pumpEventQueue();
      expect(vm.tags, ['from-git', 'users']);
    });

    test('a failed save puts the chips back and reports it', () async {
      repo.failWith = 'disk full';
      await vm.add('v2');
      expect(vm.tags, ['users']);
      expect(vm.saveError, contains('disk full'));

      repo.failWith = null;
      await vm.add('v2');
      expect(vm.tags, ['users', 'v2']);
      expect(vm.saveError, isNull);
    });

    test('a save finishing after dispose does not notify', () async {
      final failing = FakeTagRepository()..failWith = 'boom';
      final other = TagsViewModel(failing, EntityKind.request, 1);
      await pumpEventQueue();
      final pending = other.add('x');
      other.dispose();
      await pending;
      await failing.close();
    });
  });

  group('AllTagsViewModel', () {
    test('lists every tag in use, one spelling each, and follows changes', () async {
      final repo = FakeTagRepository()
        ..seed(EntityKind.request, 1, ['v2', 'API'])
        ..seed(EntityKind.folder, 1, ['api', 'v3']);
      final vm = AllTagsViewModel(repo);
      await pumpEventQueue();
      expect(vm.tags, ['API', 'v2', 'v3']);

      await repo.setTags(EntityKind.collection, 1, ['zeta']);
      await pumpEventQueue();
      expect(vm.tags, ['API', 'v2', 'v3', 'zeta']);

      vm.dispose();
      await repo.close();
    });

    test('is quiet while the list of tags stays the same', () async {
      final repo = FakeTagRepository()..seed(EntityKind.request, 1, ['v2']);
      final vm = AllTagsViewModel(repo);
      await pumpEventQueue();
      var notifications = 0;
      vm.addListener(() => notifications++);

      await repo.setTags(EntityKind.request, 2, ['V2']);
      await repo.setTags(EntityKind.folder, 1, ['v2']);
      await pumpEventQueue();
      expect(notifications, 0);

      await repo.setTags(EntityKind.folder, 1, ['v2', 'v3']);
      await pumpEventQueue();
      expect(notifications, 1);

      vm.dispose();
      await repo.close();
    });
  });

  group('TagMatcher', () {
    // Collection 1: folder 10 (root) > folder 11; folder 12 (root).
    // requests: 100 root, 101 in 10, 102 in 11, 103 in 12, 104 in a missing folder.
    // Collection 2: no folders; requests 200, 201.
    final folders = {
      1: [folderEntity(10), folderEntity(11, parent: 10), folderEntity(12)],
    };
    RequestSummaryEntity request(int id, int? folderId) =>
        RequestSummaryEntity(id: id, folderId: folderId, name: 'r$id', method: HttpMethod.get);
    final requests = {
      1: [request(100, null), request(101, 10), request(102, 11), request(103, 12), request(104, 999)],
      2: [request(200, null), request(201, null)],
    };

    Set<int> match(
      Set<String> selected, {
      Map<int, List<String>> onRequests = const {},
      Map<int, List<String>> onFolders = const {},
      Map<int, List<String>> onCollections = const {},
      Map<int, List<FolderEntity>>? withFolders,
      Map<int, List<RequestSummaryEntity>>? withRequests,
    }) =>
        TagMatcher.matchingRequestIds(
          selected: selected,
          requestTags: onRequests,
          folderTags: onFolders,
          collectionTags: onCollections,
          foldersByCollection: withFolders ?? folders,
          requestsByCollection: withRequests ?? requests,
        );

    test('a request matches through its own tag', () {
      expect(match({'v2'}, onRequests: {100: ['v2'], 200: ['v3']}), {100});
    });

    test('a folder tag reaches every request inside it, at any depth, and no other', () {
      expect(match({'v3'}, onFolders: {10: ['v3']}), {101, 102});
    });

    test('a nested folder tag does not reach its parent', () {
      expect(match({'v3'}, onFolders: {11: ['v3']}), {102});
    });

    test('a collection tag reaches all its requests, including those outside any folder', () {
      expect(match({'public'}, onCollections: {1: ['public']}), {100, 101, 102, 103, 104});
      expect(match({'public'}, onCollections: {2: ['public']}), {200, 201});
    });

    test('any selected tag is enough', () {
      expect(
        match({'v2', 'v3'}, onRequests: {100: ['v2']}, onFolders: {10: ['v3']}, onCollections: {2: ['nope']}),
        {100, 101, 102},
      );
    });

    test('a request carrying several tags is listed once', () {
      expect(match({'a', 'b'}, onRequests: {100: ['a', 'b']}), {100});
    });

    test('tags compare ignoring case; the selection is lower case', () {
      expect(match({'v2'}, onRequests: {100: ['V2']}, onFolders: {12: ['V2']}), {100, 103});
    });

    test('nothing selected, or nothing tagged, matches nothing', () {
      expect(match({}, onRequests: {100: ['v2']}), isEmpty);
      expect(match({'v2'}), isEmpty);
    });

    test('a folder missing from the loaded tree still tags its own requests, just not through parents', () {
      expect(match({'x'}, onFolders: {999: ['x']}), {104});
      expect(match({'x'}, onRequests: {104: ['x']}), {104});
      expect(match({'x'}, onFolders: {10: ['x']}), {101, 102});
    });

    test('a loop in the folder tree cannot hang the filter', () {
      final looped = {
        1: [folderEntity(20, parent: 21), folderEntity(21, parent: 20)],
      };
      final inLoop = {
        1: [request(300, 21)],
      };
      expect(match({'t'}, withFolders: looped, withRequests: inLoop), isEmpty);
      expect(match({'t'}, onFolders: {20: ['t']}, withFolders: looped, withRequests: inLoop), {300});
    });

    test('only requests of loaded collections can match', () {
      expect(match({'x'}, onCollections: {1: ['x']}, withRequests: {2: requests[2]!}), isEmpty);
    });
  });

  test('the fake store in these tests reports every change to a watcher', () async {
    final repo = FakeTagRepository();
    final seen = <List<String>>[];
    final sub = repo.watchTags(EntityKind.request, 1).listen(seen.add);
    await pumpEventQueue();
    await repo.setTags(EntityKind.request, 1, ['a']);
    await repo.setTags(EntityKind.request, 1, ['a', 'b']);
    await pumpEventQueue();
    expect(seen, [<String>[], ['a'], ['a', 'b']]);
    await sub.cancel();
    await repo.close();
  });
}
