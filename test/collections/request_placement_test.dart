// The request that is open in the editor follows it when it is moved: sending resolves variables and auth from
// the collection the request is in now, and the next save must not put it back.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/services/collection_order.dart';
import '../support/in_memory_tree.dart';
import '../support/run_harness.dart';

void main() {
  late InMemoryTree tree;
  late int login;
  late int folder;

  setUp(() {
    tree = InMemoryTree(const [CollectionEntity(id: 1, name: 'Shop'), CollectionEntity(id: 2, name: 'Blog')]);
    folder = tree.addFolder(1, 'Auth');
    login = tree.addRequest(1, 'Login');
    tree.addFolder(2, 'Drafts', id: 200);
  });

  tearDown(() => tree.close());

  test('the editor takes up the collection and folder a move gave the request', () async {
    final builder = buildBuilder(tree, FakeRunClient());
    addTearDown(builder.dispose);
    await builder.load(login);
    expect((builder.request!.collectionId, builder.request!.folderId), (1, null));

    await tree.moveRequest(login, collectionId: 2, folderId: 200);
    await pumpEventQueue();

    expect((builder.request!.collectionId, builder.request!.folderId), (2, 200));
    expect(builder.request!.name, 'Login');
  });

  test('a move inside the collection is taken up too', () async {
    final builder = buildBuilder(tree, FakeRunClient());
    addTearDown(builder.dispose);
    await builder.load(login);

    await tree.moveRequest(login, collectionId: 1, folderId: folder);
    await pumpEventQueue();

    expect((builder.request!.collectionId, builder.request!.folderId), (1, folder));
  });

  test('reordering the request among its siblings leaves the open request as it is', () async {
    final other = tree.addRequest(1, 'Logout');
    final builder = buildBuilder(tree, FakeRunClient());
    addTearDown(builder.dispose);
    await builder.load(login);
    final before = builder.request;

    await tree.moveRequest(other, collectionId: 1, before: OrderRef.request(login));
    await pumpEventQueue();

    expect(builder.request!.id, before!.id);
    expect((builder.request!.collectionId, builder.request!.folderId), (1, null));
  });
}
