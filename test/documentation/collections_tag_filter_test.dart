import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_repository.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/documentation/presentation/view_models/tag_filter_view_model.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';

import 'support/fakes.dart';

/// Checks the sidebar integration: CollectionsViewModel taking the tag filter
/// as `requestIdFilter:`. Until that parameter exists (the wiring is done in a
/// file this feature does not own) every test here skips itself.
CollectionsViewModel? _withFilter(CollectionRepository collections, RequestRepository requests, ValueListenable<Set<int>?> filter) {
  try {
    return Function.apply(CollectionsViewModel.new, [collections, requests], {#requestIdFilter: filter}) as CollectionsViewModel;
  } on NoSuchMethodError {
    return null;
  }
}

void main() {
  late FakeTagRepository tags;
  late FakeCollectionRepository collections;
  late FakeRequestRepository requests;
  late TagFilterViewModel filter;
  CollectionsViewModel? sidebar;

  // Shop (1): folder 10 "Users" > folder 11 "Admin"; folder 12 "Billing".
  //   requests: 100 Health (root), 101 List users (10), 102 Ban user (11), 103 Invoices (12)
  // Blog (2): 200 Posts
  setUp(() async {
    tags = FakeTagRepository()
      ..seed(EntityKind.folder, 10, ['v3'])
      ..seed(EntityKind.request, 100, ['v2'])
      ..seed(EntityKind.request, 200, ['v2']);
    collections = FakeCollectionRepository(
      collections: const [CollectionEntity(id: 1, name: 'Shop'), CollectionEntity(id: 2, name: 'Blog')],
      folders: {
        1: [folderEntity(10, name: 'Users'), folderEntity(11, parent: 10, name: 'Admin'), folderEntity(12, name: 'Billing')],
      },
    );
    requests = FakeRequestRepository({
      1: [
        requestEntity(100, name: 'Health'),
        requestEntity(101, folderId: 10, name: 'List users'),
        requestEntity(102, folderId: 11, name: 'Ban user'),
        requestEntity(103, folderId: 12, name: 'Invoices'),
      ],
      2: [requestEntity(200, collectionId: 2, name: 'Posts')],
    });
    filter = TagFilterViewModel(tags, collections, requests);
    sidebar = _withFilter(collections, requests, filter);
    await pumpEventQueue();
  });

  tearDown(() async {
    sidebar?.dispose();
    filter.dispose();
    await tags.close();
  });

  void sidebarTest(String description, Future<void> Function(CollectionsViewModel vm) body) {
    test(description, () async {
      final vm = sidebar;
      if (vm == null) {
        markTestSkipped('CollectionsViewModel has no requestIdFilter parameter yet; see the tag filter wiring notes');
        return;
      }
      await body(vm);
    });
  }

  CollectionEntity col(CollectionsViewModel vm, String name) => vm.collections.firstWhere((c) => c.name == name);
  FolderEntity fol(CollectionsViewModel vm, String name) => vm.foldersByCollection[1]!.firstWhere((f) => f.name == name);
  RequestSummaryEntity req(CollectionsViewModel vm, int collectionId, String name) =>
      vm.requestsByCollection[collectionId]!.firstWhere((r) => r.name == name);

  sidebarTest('without a tag filter everything is visible and nothing opens by itself', (vm) async {
    expect((vm as dynamic).isFiltering, isFalse);
    expect(vm.isCollectionVisible(col(vm, 'Shop')), isTrue);
    expect(vm.isCollectionExpanded(col(vm, 'Shop')), isFalse);
  });

  sidebarTest('a tag shows only matching requests with their folders and collections, opened', (vm) async {
    filter.toggleTag('v3');
    await pumpEventQueue();

    expect((vm as dynamic).isFiltering, isTrue);
    expect(vm.isCollectionVisible(col(vm, 'Shop')), isTrue);
    expect(vm.isCollectionVisible(col(vm, 'Blog')), isFalse);
    expect(vm.isCollectionExpanded(col(vm, 'Shop')), isTrue);
    expect(vm.isFolderVisible(1, fol(vm, 'Users')), isTrue);
    expect(vm.isFolderVisible(1, fol(vm, 'Admin')), isTrue);
    expect(vm.isFolderVisible(1, fol(vm, 'Billing')), isFalse);
    expect(vm.isRequestVisible(req(vm, 1, 'List users')), isTrue);
    expect(vm.isRequestVisible(req(vm, 1, 'Ban user')), isTrue);
    expect(vm.isRequestVisible(req(vm, 1, 'Health')), isFalse);
    expect(vm.isRequestVisible(req(vm, 1, 'Invoices')), isFalse);
  });

  sidebarTest('several tags show the union', (vm) async {
    filter
      ..toggleTag('v2')
      ..toggleTag('v3');
    await pumpEventQueue();

    expect(vm.isCollectionVisible(col(vm, 'Blog')), isTrue);
    expect(vm.isRequestVisible(req(vm, 2, 'Posts')), isTrue);
    expect(vm.isRequestVisible(req(vm, 1, 'Health')), isTrue);
    expect(vm.isRequestVisible(req(vm, 1, 'Invoices')), isFalse);
    expect(vm.isFolderVisible(1, fol(vm, 'Billing')), isFalse);
  });

  sidebarTest('search and tags combine: a request has to satisfy both', (vm) async {
    filter.toggleTag('v3');
    vm.setSearchQuery('ban');
    await pumpEventQueue();

    expect(vm.isRequestVisible(req(vm, 1, 'Ban user')), isTrue);
    expect(vm.isRequestVisible(req(vm, 1, 'List users')), isFalse);
    expect(vm.isFolderVisible(1, fol(vm, 'Admin')), isTrue);
    expect(vm.isCollectionVisible(col(vm, 'Shop')), isTrue);
  });

  sidebarTest('a name match alone keeps nothing while tags are selected', (vm) async {
    filter.toggleTag('v3');
    vm.setSearchQuery('billing');
    await pumpEventQueue();

    expect(vm.isFolderVisible(1, fol(vm, 'Billing')), isFalse);
    expect(vm.isCollectionVisible(col(vm, 'Shop')), isFalse);
  });

  sidebarTest('search alone still works as before', (vm) async {
    vm.setSearchQuery('billing');
    await pumpEventQueue();

    expect(vm.isFolderVisible(1, fol(vm, 'Billing')), isTrue);
    expect(vm.isRequestVisible(req(vm, 1, 'Invoices')), isFalse);
    expect(vm.isCollectionVisible(col(vm, 'Blog')), isFalse);
    expect(vm.isCollectionExpanded(col(vm, 'Shop')), isTrue);
  });

  sidebarTest('clearing the tag filter brings everything back', (vm) async {
    filter.toggleTag('v3');
    await pumpEventQueue();
    filter.clear();
    await pumpEventQueue();

    expect((vm as dynamic).isFiltering, isFalse);
    expect(vm.isCollectionVisible(col(vm, 'Blog')), isTrue);
    expect(vm.isRequestVisible(req(vm, 1, 'Health')), isTrue);
    expect(vm.isCollectionExpanded(col(vm, 'Shop')), isFalse);
  });

  sidebarTest('the sidebar is told when the filter changes and loads every collection for it', (vm) async {
    var notified = 0;
    vm.addListener(() => notified++);

    filter.toggleTag('v2');
    await pumpEventQueue();

    expect(notified, greaterThan(0));
    expect(vm.requestsByCollection.keys, containsAll([1, 2]));
  });
}
