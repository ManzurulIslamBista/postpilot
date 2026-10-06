// The sidebar's view model over a real (in-memory SQLite) database: what it shows, first-use normalisation of an old
// collection, steps, moves with undo, and the state that must survive a move.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/collections/data/repositories/collection_order_repository_impl.dart';
import 'package:postpilot/features/collections/domain/entities/move_receipt.dart';
import 'package:postpilot/features/collections/domain/services/collection_order.dart';
import 'package:postpilot/features/collections/presentation/view_models/collections_view_model.dart';
import '../support/drift_repos.dart';

void main() {
  late AppDatabase db;
  late DriftRepos repos;
  late CollectionsViewModel vm;
  late int shop;
  late int blog;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = DriftRepos(db);
    shop = await repos.collectionRepository.createCollection('Shop');
    blog = await repos.collectionRepository.createCollection('Blog');
    vm = CollectionsViewModel(
      repos.collectionRepository,
      repos.requestRepository,
      orderRepository: CollectionOrderRepositoryImpl(db.collectionsDao),
    );
    await pumpEventQueue();
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  Future<int> request(int c, String name, {int? folder, int? index}) => db.requestsDao.createRequest(
    RequestsCompanion.insert(
      collectionId: c,
      folderId: Value(folder),
      name: name,
      orderIndex: index == null ? const Value.absent() : Value(index),
    ),
  );
  Future<int> folder(int c, String name, {int? parent}) =>
      repos.collectionRepository.createFolder(collectionId: c, parentFolderId: parent, name: name);

  Future<void> open(int c) async {
    vm.expandCollection(c);
    for (var i = 0; i < 20 && (vm.foldersByCollection[c] == null || vm.requestsByCollection[c] == null); i++) {
      await pumpEventQueue();
    }
    await pumpEventQueue();
  }

  List<String> names(int c, int? parent) =>
      [for (final item in vm.childrenOf(c, parent)) item.folder?.name ?? item.request!.name];

  Future<Map<String, int>> stored(int c) async {
    final requests = await (db.select(db.requests)..where((t) => t.collectionId.equals(c))).get();
    final folders = await (db.select(db.folders)..where((t) => t.collectionId.equals(c))).get();
    return {for (final r in requests) r.name: r.orderIndex, for (final f in folders) f.name: f.orderIndex};
  }

  test('shows the folders and requests of a level interleaved, in order', () async {
    await request(shop, 'a');
    final f = await folder(shop, 'F');
    await request(shop, 'b');
    await request(shop, 'in F', folder: f);
    await open(shop);

    expect(names(shop, null), ['a', 'F', 'b']);
    expect(names(shop, f), ['in F']);
    expect(vm.childrenOf(shop, null).map((i) => i.entry.depth), everyElement(0));
  });

  test('a collection from before ordering existed (every index 0) is put in order the first time it is opened', () async {
    final f = await folder(shop, 'F');
    await request(shop, 'r-late', index: 0);
    await request(shop, 'r-early', index: 0);
    await request(shop, 'inside', folder: f, index: 0);
    await db.customStatement('UPDATE folders SET order_index = 0');
    final before = await stored(shop);
    expect(before.values, everyElement(0));

    await open(shop);
    await pumpEventQueue();

    expect(names(shop, null), ['F', 'r-late', 'r-early'], reason: 'folders first, then by creation: how it was always shown');
    expect(await stored(shop), {'F': 0, 'r-late': 1, 'r-early': 2, 'inside': 0});
  });

  test('an already ordered collection is left exactly as it is', () async {
    await request(shop, 'a');
    await request(shop, 'b');
    await db.customStatement('UPDATE requests SET order_index = order_index * 10');
    final before = await stored(shop);

    await open(shop);
    await pumpEventQueue();

    expect(await stored(shop), before);
  });

  test('an empty folder lists nothing', () async {
    final f = await folder(shop, 'Empty');
    await open(shop);

    expect(names(shop, f), isEmpty);
  });

  test('moveStep swaps with the neighbour in either direction and refuses at the ends', () async {
    final a = await request(shop, 'a');
    await request(shop, 'b');
    final c = await request(shop, 'c');
    await open(shop);

    expect(vm.canStep(OrderRef.request(a), collectionId: shop, delta: -1), isFalse);
    expect(vm.canStep(OrderRef.request(a), collectionId: shop, delta: 1), isTrue);
    expect(vm.canStep(OrderRef.request(c), collectionId: shop, delta: 1), isFalse);

    expect((await vm.moveStep(OrderRef.request(c), collectionId: shop, delta: -1)).moved, isTrue);
    await pumpEventQueue();
    expect(names(shop, null), ['a', 'c', 'b']);
    expect((await vm.moveStep(OrderRef.request(a), collectionId: shop, delta: 1)).moved, isTrue);
    await pumpEventQueue();
    expect(names(shop, null), ['c', 'a', 'b']);
    expect((await vm.moveStep(OrderRef.request(c), collectionId: shop, delta: -1)).moved, isFalse, reason: 'already first');
  });

  test('moveStep works on folders, which swap with whatever sits next to them', () async {
    await request(shop, 'a');
    final f = await folder(shop, 'F');
    await request(shop, 'b');
    await open(shop);

    await vm.moveStep(OrderRef.folder(f), collectionId: shop, delta: -1);
    await pumpEventQueue();
    expect(names(shop, null), ['F', 'a', 'b']);

    await vm.moveStep(OrderRef.folder(f), collectionId: shop, delta: 1);
    await pumpEventQueue();
    expect(names(shop, null), ['a', 'F', 'b']);
    await vm.moveStep(OrderRef.folder(f), collectionId: shop, delta: 1);
    await pumpEventQueue();
    expect(names(shop, null), ['a', 'b', 'F']);
  });

  test('a move opens its target so the item is in view, and keeps folders that are closed closed', () async {
    final f = await folder(shop, 'F');
    final g = await folder(shop, 'G');
    final a = await request(shop, 'a');
    await open(shop);
    vm.toggleFolder(g);
    expect(vm.isFolderExpanded(g), isFalse);
    expect(vm.isFolderExpanded(f), isTrue);

    await vm.moveRequest(a, collectionId: shop, folderId: g);
    await pumpEventQueue();

    expect(vm.isFolderExpanded(g), isTrue, reason: 'the target opens');
    expect(names(shop, g), ['a']);
  });

  test('a folder keeps being closed when it moves into another folder', () async {
    final f = await folder(shop, 'F');
    final g = await folder(shop, 'G');
    await open(shop);
    vm.toggleFolder(f);

    await vm.moveFolder(f, collectionId: shop, parentFolderId: g);
    await pumpEventQueue();

    expect(names(shop, g), ['F']);
    expect(vm.isFolderExpanded(f), isFalse);
  });

  test('moving into another collection opens it and shows the request there; undo brings it back', () async {
    final a = await request(shop, 'a');
    await request(blog, 'post');
    await open(shop);
    expect(vm.isExpanded(blog), isFalse);

    final outcome = await vm.moveRequest(a, collectionId: blog);
    await pumpEventQueue();
    await open(blog);

    expect(outcome.receipt!.changedCollection, isTrue);
    expect(vm.isExpanded(blog), isTrue);
    expect(names(blog, null), ['post', 'a']);
    expect(names(shop, null), isEmpty);

    expect(await vm.undoMove(outcome.receipt!), isTrue);
    await pumpEventQueue();
    expect(names(shop, null), ['a']);
    expect(names(blog, null), ['post']);
  });

  test('a refused move comes back as a message, not an exception, and changes nothing', () async {
    final f = await folder(shop, 'F');
    final inner = await folder(shop, 'Inner', parent: f);
    await open(shop);

    final outcome = await vm.moveFolder(f, collectionId: shop, parentFolderId: inner);

    expect(outcome.error, contains('itself'));
    expect(outcome.receipt, isNull);
    expect(outcome.moved, isFalse);
    expect(names(shop, null), ['F']);
  });

  test('undoing a move after its rows were deleted skips them instead of failing', () async {
    final a = await request(shop, 'a');
    final b = await request(shop, 'b');
    await open(shop);
    final outcome = await vm.moveRequest(a, collectionId: shop);

    await db.requestsDao.deleteRequest(a);
    await db.requestsDao.deleteRequest(b);

    expect(await vm.undoMove(outcome.receipt!), isTrue, reason: 'rows that are gone are skipped, nothing to restore');
    expect(await vm.undoMove(const MoveReceipt(replaced: [])), isFalse, reason: 'an empty receipt has nothing to put back');
  });

  test('moveDestinations lists collections and their folders in tree order, and blocks a folder\'s own inside', () async {
    final f = await folder(shop, 'F');
    await folder(shop, 'Inner', parent: f);
    await folder(shop, 'Other');
    await folder(blog, 'Drafts');
    await pumpEventQueue();

    final plain = await vm.moveDestinations();
    final forFolder = await vm.moveDestinations(moving: OrderRef.folder(f));

    String line(MoveDestination d) => '${'  ' * d.depth}${d.label}${d.enabled ? '' : ' (blocked)'}';
    expect(plain.map(line), ['Shop', '  F', '    Inner', '  Other', 'Blog', '  Drafts']);
    expect(forFolder.map(line), ['Shop', '  F (blocked)', '    Inner (blocked)', '  Other', 'Blog', '  Drafts']);
  });

  test('without an order repository nothing can be moved, and the tree still reads', () async {
    final readOnly = CollectionsViewModel(repos.collectionRepository, repos.requestRepository);
    addTearDown(readOnly.dispose);
    final a = await request(shop, 'a');

    final outcome = await readOnly.moveRequest(a, collectionId: shop);

    expect(readOnly.canMove, isFalse);
    expect(readOnly.canStep(OrderRef.request(a), collectionId: shop, delta: 1), isFalse);
    expect(outcome.error, isNotNull);
    final receipt = MoveReceipt(
      replaced: [Placement(ref: OrderRef.request(a), collectionId: shop, parentId: null, orderIndex: 0)],
    );
    expect(await readOnly.undoMove(receipt), isFalse);
  });
}
