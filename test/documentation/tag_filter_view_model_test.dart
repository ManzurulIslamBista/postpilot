import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/documentation/presentation/view_models/tag_filter_view_model.dart';

import 'support/fakes.dart';

void main() {
  late FakeTagRepository tags;
  late FakeCollectionRepository collections;
  late FakeRequestRepository requests;
  late TagFilterViewModel filter;

  // Shop (1): folder 10 > folder 11; requests 100 (root), 101 (in 10), 102 (in 11).
  // Blog (2): request 200.
  setUp(() async {
    tags = FakeTagRepository()
      ..seed(EntityKind.folder, 10, ['v3'])
      ..seed(EntityKind.request, 100, ['v2'])
      ..seed(EntityKind.request, 200, ['v2']);
    collections = FakeCollectionRepository(
      collections: const [CollectionEntity(id: 1, name: 'Shop'), CollectionEntity(id: 2, name: 'Blog')],
      folders: {
        1: [folderEntity(10), folderEntity(11, parent: 10)],
      },
    );
    requests = FakeRequestRepository({
      1: [requestEntity(100), requestEntity(101, folderId: 10), requestEntity(102, folderId: 11)],
      2: [requestEntity(200, collectionId: 2)],
    });
    filter = TagFilterViewModel(tags, collections, requests);
    await pumpEventQueue();
  });

  tearDown(() async {
    filter.dispose();
    await tags.close();
  });

  test('starts with every tag in use and no filter', () {
    expect(filter.allTags, ['v2', 'v3']);
    expect(filter.isFiltering, isFalse);
    expect(filter.selectedTags, isEmpty);
    expect(filter.matchingRequestIds, isNull);
    expect(filter.value, isNull);
  });

  test('selecting a tag narrows to the requests that carry it', () async {
    filter.toggleTag('v2');
    await pumpEventQueue();

    expect(filter.isFiltering, isTrue);
    expect(filter.isSelected('v2'), isTrue);
    expect(filter.isSelected('V2'), isTrue);
    expect(filter.isSelected('v3'), isFalse);
    expect(filter.selectedTags, {'v2'});
    expect(filter.matchingRequestIds, {100, 200});
    expect(filter.value, {100, 200});
  });

  test('a folder tag matches everything inside the folder, nested folders too', () async {
    filter.toggleTag('v3');
    await pumpEventQueue();

    expect(filter.matchingRequestIds, {101, 102});
  });

  test('several tags match any of them', () async {
    filter
      ..toggleTag('v2')
      ..toggleTag('v3');
    await pumpEventQueue();

    expect(filter.matchingRequestIds, {100, 101, 102, 200});
    expect(filter.selectedTags, {'v2', 'v3'});
  });

  test('toggling a selected tag again deselects it', () async {
    filter
      ..toggleTag('v2')
      ..toggleTag('v3');
    await pumpEventQueue();
    filter.toggleTag('v2');
    await pumpEventQueue();

    expect(filter.matchingRequestIds, {101, 102});
  });

  test('clear drops the filter', () async {
    filter.toggleTag('v2');
    await pumpEventQueue();
    filter.clear();

    expect(filter.isFiltering, isFalse);
    expect(filter.matchingRequestIds, isNull);
  });

  test('a collection tag matches all its requests', () async {
    await tags.setTags(EntityKind.collection, 2, ['public']);
    await pumpEventQueue();
    filter.toggleTag('public');
    await pumpEventQueue();

    expect(filter.matchingRequestIds, {200});
  });

  test('follows tags changed while the filter is on', () async {
    filter.toggleTag('v2');
    await pumpEventQueue();

    await tags.setTags(EntityKind.request, 102, ['v2']);
    await pumpEventQueue();
    expect(filter.matchingRequestIds, {100, 102, 200});

    await tags.setTags(EntityKind.request, 100, []);
    await pumpEventQueue();
    expect(filter.matchingRequestIds, {102, 200});
  });

  test('a request added to a tagged folder shows up at once', () async {
    filter.toggleTag('v3');
    await pumpEventQueue();

    requests.setRequests(1, [
      requestEntity(100),
      requestEntity(101, folderId: 10),
      requestEntity(102, folderId: 11),
      requestEntity(103, folderId: 11),
    ]);
    await pumpEventQueue();

    expect(filter.matchingRequestIds, {101, 102, 103});
  });

  test('a request moved out of a tagged folder drops out', () async {
    filter.toggleTag('v3');
    await pumpEventQueue();

    requests.setRequests(1, [requestEntity(100), requestEntity(101), requestEntity(102, folderId: 11)]);
    await pumpEventQueue();

    expect(filter.matchingRequestIds, {102});
  });

  test('a folder moved under a tagged folder brings its requests in', () async {
    collections.setFolders(1, [folderEntity(10), folderEntity(11, parent: 10), folderEntity(20)]);
    requests.setRequests(1, [requestEntity(100), requestEntity(105, folderId: 20)]);
    filter.toggleTag('v3');
    await pumpEventQueue();
    expect(filter.matchingRequestIds, isEmpty);

    collections.setFolders(1, [folderEntity(10), folderEntity(11, parent: 10), folderEntity(20, parent: 10)]);
    await pumpEventQueue();
    expect(filter.matchingRequestIds, {105});
  });

  test('a tag nobody uses any more leaves the selection and lifts the filter', () async {
    filter.toggleTag('v3');
    await pumpEventQueue();
    expect(filter.matchingRequestIds, {101, 102});

    await tags.setTags(EntityKind.folder, 10, []);
    await pumpEventQueue();

    expect(filter.allTags, ['v2']);
    expect(filter.isFiltering, isFalse);
    expect(filter.matchingRequestIds, isNull);
  });

  test('other selected tags survive when one disappears', () async {
    filter
      ..toggleTag('v2')
      ..toggleTag('v3');
    await pumpEventQueue();

    await tags.setTags(EntityKind.folder, 10, []);
    await pumpEventQueue();

    expect(filter.selectedTags, {'v2'});
    expect(filter.matchingRequestIds, {100, 200});
  });

  test('tags that differ only in case are one tag', () async {
    await tags.setTags(EntityKind.request, 101, ['V2']);
    await pumpEventQueue();
    expect(filter.allTags, ['v2', 'v3']);

    filter.toggleTag('v2');
    await pumpEventQueue();
    expect(filter.matchingRequestIds, {100, 101, 200});
  });

  test('listeners hear about selection changes and about matches that change', () async {
    final seen = <Set<int>?>[];
    filter.addListener(() => seen.add(filter.value == null ? null : {...filter.value!}));

    filter.toggleTag('v2');
    await pumpEventQueue();
    await tags.setTags(EntityKind.request, 102, ['v2']);
    await pumpEventQueue();
    filter.clear();

    expect(seen.first, anyOf(isNull, isEmpty));
    expect(seen, contains(equals({100, 200})));
    expect(seen, contains(equals({100, 102, 200})));
    expect(seen.last, isNull);
  });

  test('works as a ValueListenable of the matching ids', () async {
    final ValueListenable<Set<int>?> asListenable = filter;
    var calls = 0;
    asListenable.addListener(() => calls++);

    filter.toggleTag('v3');
    await pumpEventQueue();

    expect(asListenable.value, {101, 102});
    expect(calls, greaterThan(0));
  });

  test('does not watch any collection while no tag is selected', () async {
    final idle = TagFilterViewModel(tags, _ThrowingCollections(), requests);
    await pumpEventQueue();

    expect(idle.matchingRequestIds, isNull);
    idle.dispose();
  });

  test('stops updating after dispose', () async {
    final other = TagFilterViewModel(tags, collections, requests);
    await pumpEventQueue();
    other.toggleTag('v2');
    await pumpEventQueue();
    other.dispose();

    await tags.setTags(EntityKind.request, 102, ['v2']);
    requests.setRequests(1, [requestEntity(100)]);
    await pumpEventQueue();
  });
}

/// Fails the test if anything watches the collections.
final class _ThrowingCollections extends FakeCollectionRepository {
  @override
  Stream<List<CollectionEntity>> watchCollections() => throw StateError('the filter is off, nothing should be watched');
}
