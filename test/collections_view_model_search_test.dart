import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_repository.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';

void main() {
  late CollectionsViewModel vm;

  CollectionEntity collection(String name) => vm.collections.firstWhere((c) => c.name == name);

  setUp(() async {
    vm = CollectionsViewModel(_FakeCollections(), _FakeRequests());
    await pumpEventQueue();
  });

  tearDown(() => vm.dispose());

  test('nothing is expanded while there is no search', () {
    expect(vm.isCollectionExpanded(collection('Users API')), isFalse);
    expect(vm.isCollectionExpanded(collection('Billing')), isFalse);
  });

  test('searching opens the collections that hold a match, and only those', () async {
    vm.setSearchQuery('login');
    await pumpEventQueue();

    expect(vm.isCollectionExpanded(collection('Users API')), isTrue);
    expect(vm.isCollectionExpanded(collection('Billing')), isFalse);
  });

  test('a collection matching by its own name alone stays closed', () async {
    vm.setSearchQuery('billing');
    await pumpEventQueue();

    expect(vm.isCollectionVisible(collection('Billing')), isTrue);
    expect(vm.isCollectionExpanded(collection('Billing')), isFalse);
  });

  test('clearing the search closes them again', () async {
    vm.setSearchQuery('login');
    await pumpEventQueue();
    vm.setSearchQuery('');

    expect(vm.isCollectionExpanded(collection('Users API')), isFalse);
  });

  test('a collection expanded by hand stays open without a search', () async {
    vm.toggleExpand(collection('Billing').id);
    await pumpEventQueue();

    expect(vm.isCollectionExpanded(collection('Billing')), isTrue);
  });
}

final class _FakeCollections implements CollectionRepository {
  @override
  Stream<List<CollectionEntity>> watchCollections() =>
      Stream.value(const [CollectionEntity(id: 1, name: 'Users API'), CollectionEntity(id: 2, name: 'Billing')]);

  @override
  Stream<List<FolderEntity>> watchFolders(int collectionId) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeRequests implements RequestRepository {
  @override
  Stream<List<RequestSummaryEntity>> watchByCollection(int collectionId) => Stream.value(
        collectionId == 1
            ? const [RequestSummaryEntity(id: 10, folderId: null, name: 'Login', method: HttpMethod.post)]
            : const [RequestSummaryEntity(id: 20, folderId: null, name: 'List invoices', method: HttpMethod.get)],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
