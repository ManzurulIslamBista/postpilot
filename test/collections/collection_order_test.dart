// The canonical order every consumer shares. Expected values are worked out by hand from the rule: depth-first,
// folders and requests of a level interleaved by index, ties folders-first then lower id.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/collections/domain/services/collection_order.dart';

OrderFolder folder(int id, {int? parent, int order = 0}) => (id: id, parentId: parent, orderIndex: order);
OrderRequest request(int id, {int? folder, int order = 0}) => (id: id, folderId: folder, orderIndex: order);

/// `F1` for folder 1, `r7` for request 7: the walk as one readable list.
List<String> walk(CollectionOrder order) => [for (final e in order.entries) e.isFolder ? 'F${e.id}' : 'r${e.id}'];

void main() {
  group('CollectionOrder.of', () {
    test('interleaves folders and requests of a level by index, folder content right after its folder', () {
      final order = CollectionOrder.of(
        folders: [folder(1, order: 2), folder(2, order: 3)],
        requests: [request(10, order: 0), request(11, order: 1), request(12, folder: 1, order: 0)],
      );

      // r10(0), r11(1), F1(2) with r12, F2(3)
      expect(walk(order), ['r10', 'r11', 'F1', 'r12', 'F2']);
    });

    test('a request created after a folder runs after it, a folder created later can run first', () {
      // The Login case: it lives in a folder that sits first, although it was created last.
      final order = CollectionOrder.of(
        folders: [folder(5, order: 0)],
        requests: [request(1, order: 1), request(2, order: 2), request(3, folder: 5, order: 0)],
      );

      expect(walk(order), ['F5', 'r3', 'r1', 'r2']);
      expect([for (final i in order.requestIndexes) [1, 2, 3][i]], [3, 1, 2]);
    });

    test('nests three folders deep and keeps every level in its own order', () {
      final order = CollectionOrder.of(
        folders: [folder(1), folder(2, parent: 1, order: 1), folder(3, parent: 2, order: 1)],
        requests: [
          request(10, folder: 3),
          request(11, folder: 2, order: 0),
          request(12, folder: 1, order: 0),
          request(13, order: 1),
        ],
      );

      // F1(0): r12(0), F2(1): r11(0), F3(1): r10 ; then r13(1)
      expect(walk(order), ['F1', 'r12', 'F2', 'r11', 'F3', 'r10', 'r13']);
      expect([for (final e in order.entries) e.depth], [0, 1, 1, 2, 2, 3, 0]);
      expect([for (final e in order.entries) e.parentId], [null, 1, 1, 2, 2, 3, null]);
    });

    test('equal indexes (a workspace from before ordering existed) list folders first, then by id', () {
      final order = CollectionOrder.of(
        folders: [folder(7), folder(3)],
        requests: [request(9), request(4), request(8, folder: 7), request(2, folder: 3)],
      );

      // folders by id: F3, F7; requests by id: r4, r9; each folder's content after it
      expect(walk(order), ['F3', 'r2', 'F7', 'r8', 'r4', 'r9']);
    });

    test('equal index and equal id fall back to the position in the input', () {
      // The ids of requests read from a backup file are all 0: the file's order is all there is.
      final order = CollectionOrder.of(requests: [request(0), request(0), request(0)]);

      expect(order.requestIndexes, [0, 1, 2]);
      final reversed = CollectionOrder.of(requests: [request(0, order: 5), request(0, order: 1), request(0, order: 3)]);
      expect(reversed.requestIndexes, [1, 2, 0]);
    });

    test('negative and sparse indexes sort numerically', () {
      final order = CollectionOrder.of(requests: [request(1, order: 10), request(2, order: -3), request(3, order: 2)]);

      expect(walk(order), ['r2', 'r3', 'r1']);
    });

    test('a request in a folder that does not exist counts as top level, a folder with a missing parent too', () {
      final order = CollectionOrder.of(
        folders: [folder(1, parent: 99, order: 1)],
        requests: [request(5, folder: 42, order: 0), request(6, folder: 1)],
      );

      expect(walk(order), ['r5', 'F1', 'r6']);
      expect(order.childrenOf(null).map((e) => e.ref), [const OrderRef.request(5), const OrderRef.folder(1)]);
    });

    test('folders caught in a parent cycle are listed at the top, not lost and not looped on', () {
      final order = CollectionOrder.of(
        folders: [folder(1, parent: 2), folder(2, parent: 1), folder(3, parent: 3)],
        requests: [request(10, folder: 2)],
      );

      // F3 points at itself; F1 and F2 point at each other. All three are listed at the top, as a restore puts them.
      expect(walk(order), ['F3', 'F1', 'F2', 'r10']);
      expect(order.entries.where((e) => e.isFolder).map((e) => (e.parentId, e.depth)), [(null, 0), (null, 0), (null, 0)]);
      expect(order.entries.last.parentId, 2, reason: 'a request stays in its folder');
    });

    test('a folder hanging off a cycle is re-rooted too, and keeps its requests', () {
      final order = CollectionOrder.of(
        folders: [folder(1, parent: 2), folder(2, parent: 1), folder(3, parent: 1)],
        requests: [request(10, folder: 3)],
      );

      expect(walk(order), ['F1', 'F2', 'F3', 'r10']);
      expect(order.entries.where((e) => e.isFolder).every((e) => e.parentId == null && e.depth == 0), isTrue);
    });

    test('an empty collection has an empty order', () {
      final order = CollectionOrder.of();

      expect(order.entries, isEmpty);
      expect(order.childrenOf(null), isEmpty);
      expect(order.requestIndexes, isEmpty);
    });

    test('indexes map back to the lists it was given', () {
      final folders = [folder(20, order: 1), folder(10, order: 0)];
      final requests = [request(2, order: 5), request(1, order: 0)];
      final order = CollectionOrder.of(folders: folders, requests: requests);

      expect([for (final i in order.folderIndexes) folders[i].id], [10, 20]);
      expect([for (final i in order.requestIndexes) requests[i].id], [1, 2]);
    });
  });

  group('subtrees', () {
    final order = CollectionOrder.of(
      folders: [folder(1), folder(2, parent: 1), folder(3, parent: 2), folder(4, order: 1)],
      requests: [request(10, folder: 1), request(11, folder: 3), request(12, folder: 4), request(13)],
    );

    test('folderSubtree is the folder and every folder under it', () {
      expect(order.folderSubtree(1), {1, 2, 3});
      expect(order.folderSubtree(3), {3});
      expect(order.folderSubtree(99), isEmpty);
    });

    test('requestIndexesIn lists the requests of the folder and of every folder under it, in run order', () {
      final requests = [10, 11, 12, 13];
      // F1 holds sub-folder F2 (index 0, a folder wins the tie) and r10; F2 holds F3 holds r11.
      expect([for (final i in order.requestIndexesIn(1)) requests[i]], [11, 10]);
      expect([for (final i in order.requestIndexesIn(3)) requests[i]], [11]);
      expect(order.requestIndexesIn(99), isEmpty);
    });

    test('positionOf and siblingsOf describe where something sits', () {
      // top level: F1 (0), r13 (0, after the folder it ties with), F4 (1)
      expect(order.positionOf(const OrderRef.folder(4)), 2);
      expect(order.positionOf(const OrderRef.request(10)), 1);
      expect(order.positionOf(const OrderRef.request(404)), -1);
      expect(order.siblingsOf(const OrderRef.request(10)).map((e) => e.ref), [
        const OrderRef.folder(2),
        const OrderRef.request(10),
      ]);
      expect(order.siblingsOf(const OrderRef.folder(404)), isEmpty);
    });
  });

  group('one level', () {
    LevelItem item(OrderRef ref, int index) => (ref: ref, orderIndex: index);
    const f1 = OrderRef.folder(1);
    const f2 = OrderRef.folder(2);
    const r1 = OrderRef.request(1);
    const r2 = OrderRef.request(2);
    const r3 = OrderRef.request(3);

    test('sortLevel orders by index, then folders first, then id', () {
      final sorted = CollectionOrder.sortLevel([item(r2, 0), item(f2, 0), item(r1, 0), item(f1, 0), item(r3, -1)]);

      expect(sorted.map((i) => i.ref), [r3, f1, f2, r1, r2]);
    });

    test('hasTies sees two siblings sharing an index and nothing else', () {
      expect(CollectionOrder.hasTies([item(r1, 0), item(r2, 1), item(f1, 5)]), isFalse);
      expect(CollectionOrder.hasTies([item(r1, 0), item(f1, 0)]), isTrue);
      expect(CollectionOrder.hasTies(const []), isFalse);
    });

    test('placed puts the item right before the anchor, or at the end', () {
      final level = [item(r1, 0), item(r2, 1), item(r3, 2)];

      expect(CollectionOrder.placed(level, r3, before: r1), [r3, r1, r2]);
      expect(CollectionOrder.placed(level, r1, before: r3), [r2, r1, r3]);
      expect(CollectionOrder.placed(level, r1), [r2, r3, r1]);
      expect(CollectionOrder.placed(level, r1, before: const OrderRef.request(99)), [r2, r3, r1]);
    });

    test('placed with the item itself as anchor leaves everything where it was', () {
      final level = [item(r1, 0), item(r2, 1), item(r3, 2)];

      expect(CollectionOrder.placed(level, r2, before: r2), [r1, r2, r3]);
    });

    test('placed accepts an item from another level and sorts ties first', () {
      final level = [item(r2, 0), item(f1, 0)];

      expect(CollectionOrder.placed(level, r3, before: r2), [f1, r3, r2]);
    });

    test('step finds the anchor for one place up or down', () {
      final siblings = [f1, r1, r2, r3];

      expect(CollectionOrder.step(siblings, r2, -1), (canMove: true, before: r1));
      expect(CollectionOrder.step(siblings, r1, 1), (canMove: true, before: r3));
      expect(CollectionOrder.step(siblings, r2, 1), (canMove: true, before: null));
      expect(CollectionOrder.step(siblings, f1, -1).canMove, isFalse);
      expect(CollectionOrder.step(siblings, r3, 1).canMove, isFalse);
      expect(CollectionOrder.step(siblings, const OrderRef.request(99), 1).canMove, isFalse);
    });

    test('a folder and a request with the same id are different things', () {
      expect(const OrderRef.folder(1), isNot(const OrderRef.request(1)));
      final refs = <OrderRef>{const OrderRef.folder(1), const OrderRef.request(1)}..add(const OrderRef.folder(1));
      expect(refs, hasLength(2));
    });
  });
}
