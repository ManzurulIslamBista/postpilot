// Moving and reordering against a real (in-memory SQLite) database: placement, dense renumbering, cycle guard,
// cross-collection moves, undo and rollback. Expectations are worked out by hand from the fixture below.
import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/features/collections/data/repositories/collection_order_repository_impl.dart';
import 'package:postpilot/features/collections/domain/entities/move_receipt.dart';
import 'package:postpilot/features/collections/domain/services/collection_order.dart';

void main() {
  late AppDatabase db;
  late CollectionOrderRepositoryImpl order;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    order = CollectionOrderRepositoryImpl(db.collectionsDao);
  });

  tearDown(() => db.close());

  Future<int> collection(String name) => db.collectionsDao.createCollection(name);
  Future<int> folder(int c, String name, {int? parent}) =>
      db.collectionsDao.createFolder(collectionId: c, parentFolderId: parent, name: name);
  Future<int> request(int c, String name, {int? folder}) =>
      db.requestsDao.createRequest(RequestsCompanion.insert(collectionId: c, folderId: Value(folder), name: name));

  /// A row with an explicit index, as an old workspace or a Git pull leaves it.
  Future<int> requestAt(int c, String name, int index, {int? folder}) => db.requestsDao.createRequest(
    RequestsCompanion.insert(collectionId: c, folderId: Value(folder), name: name, orderIndex: Value(index)),
  );
  Future<int> folderAt(int c, String name, int index, {int? parent}) => db
      .into(db.folders)
      .insert(
        FoldersCompanion.insert(collectionId: c, parentFolderId: Value(parent), name: name, orderIndex: Value(index)),
      );

  /// The collection as the sidebar draws it: indented names, folders in brackets.
  Future<List<String>> tree(int c) async {
    final folders = await (db.select(db.folders)..where((t) => t.collectionId.equals(c))).get();
    final requests = await (db.select(db.requests)..where((t) => t.collectionId.equals(c))).get();
    final canonical = CollectionOrder.of(
      folders: [for (final f in folders) (id: f.id, parentId: f.parentFolderId, orderIndex: f.orderIndex)],
      requests: [for (final r in requests) (id: r.id, folderId: r.folderId, orderIndex: r.orderIndex)],
    );
    return [
      for (final e in canonical.entries)
        '${'  ' * e.depth}${e.isFolder ? '[${folders[e.index].name}]' : requests[e.index].name}',
    ];
  }

  /// name -> stored index, for the children of one parent.
  Future<Map<String, int>> indexes(int c, {int? parent}) async {
    final folders =
        await (db.select(db.folders)..where(
              (t) => t.collectionId.equals(c) & (parent == null ? t.parentFolderId.isNull() : t.parentFolderId.equals(parent)),
            ))
            .get();
    final requests =
        await (db.select(db.requests)..where(
              (t) => t.collectionId.equals(c) & (parent == null ? t.folderId.isNull() : t.folderId.equals(parent)),
            ))
            .get();
    return {for (final f in folders) f.name: f.orderIndex, for (final r in requests) r.name: r.orderIndex};
  }

  Future<Request> row(int id) => (db.select(db.requests)..where((t) => t.id.equals(id))).getSingle();
  Future<Folder> folderRow(int id) => (db.select(db.folders)..where((t) => t.id.equals(id))).getSingle();

  /// C:  A, [F](X, Y, [Inner](Z)), B, [G]   created in that order, so appended with indexes 0..
  Future<({int c, int a, int f, int x, int y, int inner, int z, int b, int g})> fixture() async {
    final c = await collection('C');
    final a = await request(c, 'A');
    final f = await folder(c, 'F');
    final x = await request(c, 'X', folder: f);
    final y = await request(c, 'Y', folder: f);
    final inner = await folder(c, 'Inner', parent: f);
    final z = await request(c, 'Z', folder: inner);
    final b = await request(c, 'B');
    final g = await folder(c, 'G');
    return (c: c, a: a, f: f, x: x, y: y, inner: inner, z: z, b: b, g: g);
  }

  group('creating appends', () {
    test('new folders and requests go after everything in their level, folders and requests sharing one order', () async {
      final t = await fixture();

      expect(await indexes(t.c), {'A': 0, 'F': 1, 'B': 2, 'G': 3});
      expect(await indexes(t.c, parent: t.f), {'X': 0, 'Y': 1, 'Inner': 2});
      expect(await indexes(t.c, parent: t.inner), {'Z': 0});
      expect(await tree(t.c), ['A', '[F]', '  X', '  Y', '  [Inner]', '    Z', 'B', '[G]']);
    });

    test('another collection starts at 0 again', () async {
      final one = await collection('One');
      final two = await collection('Two');
      await request(one, 'a');
      await request(one, 'b');
      await request(two, 'x');

      expect(await indexes(two), {'x': 0});
    });

    test('an entry that carries an index keeps it, the next one goes after the highest', () async {
      final c = await collection('C');
      await request(c, 'first');
      await requestAt(c, 'pinned', 40);
      await request(c, 'after pinned');

      expect(await indexes(c), {'first': 0, 'pinned': 40, 'after pinned': 41});
    });

    test('duplicating puts the copy right behind the original and renumbers the level', () async {
      final c = await collection('C');
      final a = await request(c, 'A');
      await request(c, 'B');
      await request(c, 'C');

      final copy = await db.collectionsDao.duplicateRequest(a);

      expect(await indexes(c), {'A': 0, 'A copy': 1, 'B': 2, 'C': 3});
      expect((await row(copy)).orderIndex, 1);
    });

    test('duplicating a folder puts the copy behind it and keeps the order inside', () async {
      final c = await collection('C');
      final f = await folder(c, 'F');
      await request(c, 'after');
      await request(c, 'one', folder: f);
      await request(c, 'two', folder: f);

      final copy = await db.collectionsDao.duplicateFolder(f);

      expect(await tree(c), ['[F]', '  one', '  two', '[F copy]', '  one', '  two', 'after']);
      expect((await folderRow(copy)).orderIndex, 1);
    });

    test('duplicating a collection keeps the order of everything in it', () async {
      final t = await fixture();

      final copy = await db.collectionsDao.duplicateCollection(t.c);

      expect(await tree(copy), await tree(t.c));
    });

    test('rows listed by the DAO come in canonical order even when ids and indexes disagree', () async {
      final c = await collection('C');
      await requestAt(c, 'last', 5);
      await requestAt(c, 'first', 1);
      await requestAt(c, 'tie-b', 3);
      await requestAt(c, 'tie-a', 3);

      final listed = (await db.requestsDao.watchByCollection(c).first).map((r) => r.name);

      // by index, equal indexes by id (creation order)
      expect(listed, ['first', 'tie-b', 'tie-a', 'last']);
    });
  });

  group('normalize', () {
    test('levels whose siblings share an index get distinct ones: folders first, then by id', () async {
      final c = await collection('C');
      await requestAt(c, 'r-late', 0);
      final f = await folderAt(c, 'F', 0);
      await requestAt(c, 'r-early', 0);
      await requestAt(c, 'in-1', 0, folder: f);
      await requestAt(c, 'in-2', 0, folder: f);

      final written = await order.normalize(c);

      // top: F stays 0, r-late 0 -> 1, r-early 0 -> 2; inside F: in-1 stays 0, in-2 0 -> 1
      expect(await indexes(c), {'F': 0, 'r-late': 1, 'r-early': 2});
      expect(await indexes(c, parent: f), {'in-1': 0, 'in-2': 1});
      expect(written, 3);
    });

    test('keeps the order a tied level was already shown in', () async {
      final c = await collection('C');
      await requestAt(c, 'b', 0);
      await requestAt(c, 'a', 0);
      await folderAt(c, 'Z', 0);
      final before = await tree(c);

      await order.normalize(c);

      expect(before, ['[Z]', 'b', 'a']);
      expect(await tree(c), before);
    });

    test('does nothing the second time, nor for a level that only has gaps', () async {
      final c = await collection('C');
      await requestAt(c, 'a', 0);
      await requestAt(c, 'b', 7);
      await requestAt(c, 'c', 7);
      final gaps = await folderAt(c, 'Gaps', 1);
      await requestAt(c, 'g1', 3, folder: gaps);
      await requestAt(c, 'g2', 9, folder: gaps);

      // top: a 0, Gaps 1, b 7, c 7 -> a 0, Gaps 1, b 2, c 3 (b and c change); Gaps' content has no tie
      expect(await order.normalize(c), 2);
      expect(await indexes(c), {'a': 0, 'Gaps': 1, 'b': 2, 'c': 3});
      expect(await indexes(c, parent: gaps), {'g1': 3, 'g2': 9});
      expect(await order.normalize(c), 0);
    });

    test('only touches its own collection', () async {
      final one = await collection('One');
      final two = await collection('Two');
      await requestAt(one, 'a', 0);
      await requestAt(one, 'b', 0);
      await requestAt(two, 'x', 0);
      await requestAt(two, 'y', 0);

      await order.normalize(one);

      expect(await indexes(one), {'a': 0, 'b': 1});
      expect(await indexes(two), {'x': 0, 'y': 0});
    });
  });

  group('moving a request', () {
    test('before a sibling renumbers the level densely', () async {
      final t = await fixture();

      final receipt = await order.moveRequest(t.b, collectionId: t.c, before: OrderRef.request(t.a));

      // before A: B 0, A 1, F 2, G 3
      expect(await indexes(t.c), {'B': 0, 'A': 1, 'F': 2, 'G': 3});
      expect(receipt.replaced, hasLength(3), reason: 'G keeps its place, so only A, F and B were written');
      expect(receipt.changedCollection, isFalse);
    });

    test('to the end of its level', () async {
      final t = await fixture();

      await order.moveRequest(t.a, collectionId: t.c);

      expect(await tree(t.c), ['[F]', '  X', '  Y', '  [Inner]', '    Z', 'B', '[G]', 'A']);
      expect(await indexes(t.c), {'F': 0, 'B': 1, 'G': 2, 'A': 3});
    });

    test('into a folder at the end: both levels are dense afterwards', () async {
      final t = await fixture();

      await order.moveRequest(t.b, collectionId: t.c, folderId: t.f);

      expect(await indexes(t.c, parent: t.f), {'X': 0, 'Y': 1, 'Inner': 2, 'B': 3});
      expect(await indexes(t.c), {'A': 0, 'F': 1, 'G': 2});
      expect((await row(t.b)).folderId, t.f);
    });

    test('into a folder before one of its children', () async {
      final t = await fixture();

      await order.moveRequest(t.b, collectionId: t.c, folderId: t.f, before: OrderRef.request(t.y));

      expect(await indexes(t.c, parent: t.f), {'X': 0, 'B': 1, 'Y': 2, 'Inner': 3});
      expect(await tree(t.c), ['A', '[F]', '  X', '  B', '  Y', '  [Inner]', '    Z', '[G]']);
    });

    test('out to the top level, three folders deep, in front of a folder', () async {
      final t = await fixture();

      await order.moveRequest(t.z, collectionId: t.c, before: OrderRef.folder(t.f));

      expect(await tree(t.c), ['A', 'Z', '[F]', '  X', '  Y', '  [Inner]', 'B', '[G]']);
      expect(await indexes(t.c), {'A': 0, 'Z': 1, 'F': 2, 'B': 3, 'G': 4});
      expect(await indexes(t.c, parent: t.inner), isEmpty);
      expect((await row(t.z)).folderId, isNull);
    });

    test('into a sub-folder of a sub-folder', () async {
      final t = await fixture();

      await order.moveRequest(t.a, collectionId: t.c, folderId: t.inner, before: OrderRef.request(t.z));

      expect(await tree(t.c), ['[F]', '  X', '  Y', '  [Inner]', '    A', '    Z', 'B', '[G]']);
    });

    test('an anchor that is not in the target level means the end', () async {
      final t = await fixture();

      await order.moveRequest(t.a, collectionId: t.c, folderId: t.f, before: const OrderRef.request(9999));

      expect(await indexes(t.c, parent: t.f), {'X': 0, 'Y': 1, 'Inner': 2, 'A': 3});
    });

    test('dropped where it already is, nothing is written and there is nothing to undo', () async {
      final t = await fixture();

      final receipt = await order.moveRequest(t.b, collectionId: t.c, before: OrderRef.folder(t.g));
      final onItself = await order.moveRequest(t.a, collectionId: t.c, before: OrderRef.request(t.a));
      final toEnd = await order.moveFolder(t.g, collectionId: t.c);

      expect(receipt.isNoop, isTrue);
      expect(onItself.isNoop, isTrue);
      expect(toEnd.isNoop, isTrue);
      expect(await indexes(t.c), {'A': 0, 'F': 1, 'B': 2, 'G': 3});
    });

    test('keeps its id, name and everything saved on it', () async {
      final t = await fixture();
      await db.requestsDao.updateRequest(
        t.a,
        const RequestsCompanion(url: Value('https://api.test/a'), method: Value('post'), bodyText: Value('{"a":1}')),
      );

      await order.moveRequest(t.a, collectionId: t.c, folderId: t.f);

      final moved = await row(t.a);
      expect((moved.id, moved.name, moved.url, moved.method, moved.bodyText), (t.a, 'A', 'https://api.test/a', 'post', '{"a":1}'));
    });

    test('a request that no longer exists, or a destination that is gone, is refused', () async {
      final t = await fixture();

      await expectLater(order.moveRequest(9999, collectionId: t.c), throwsA(isA<NotFoundException>()));
      await expectLater(order.moveRequest(t.a, collectionId: 9999), throwsA(isA<MoveRefusedException>()));
      await expectLater(order.moveRequest(t.a, collectionId: t.c, folderId: 9999), throwsA(isA<MoveRefusedException>()));
      expect(await tree(t.c), ['A', '[F]', '  X', '  Y', '  [Inner]', '    Z', 'B', '[G]']);
    });

    test('a folder of another collection is not a destination', () async {
      final t = await fixture();
      final other = await collection('Other');
      final foreign = await folder(other, 'Foreign');

      await expectLater(
        order.moveRequest(t.a, collectionId: t.c, folderId: foreign),
        throwsA(isA<MoveRefusedException>()),
      );
      expect((await row(t.a)).folderId, isNull);
    });
  });

  group('moving a folder', () {
    test('within its level, content and all', () async {
      final t = await fixture();

      await order.moveFolder(t.f, collectionId: t.c);

      expect(await tree(t.c), ['A', 'B', '[G]', '[F]', '  X', '  Y', '  [Inner]', '    Z']);
      expect(await indexes(t.c), {'A': 0, 'B': 1, 'G': 2, 'F': 3});
    });

    test('into another folder, bringing every request and sub-folder', () async {
      final t = await fixture();

      await order.moveFolder(t.f, collectionId: t.c, parentFolderId: t.g);

      expect(await tree(t.c), ['A', 'B', '[G]', '  [F]', '    X', '    Y', '    [Inner]', '      Z']);
      expect((await folderRow(t.f)).parentFolderId, t.g);
      expect((await row(t.z)).folderId, t.inner, reason: 'nesting inside the moved folder is untouched');
    });

    test('out to the top level', () async {
      final t = await fixture();

      await order.moveFolder(t.inner, collectionId: t.c, before: OrderRef.request(t.b));

      expect(await tree(t.c), ['A', '[F]', '  X', '  Y', '[Inner]', '  Z', 'B', '[G]']);
    });

    test('a folder cannot go into itself', () async {
      final t = await fixture();

      await expectLater(
        order.moveFolder(t.f, collectionId: t.c, parentFolderId: t.f),
        throwsA(isA<MoveRefusedException>().having((e) => e.message, 'message', contains('itself'))),
      );
      expect(await tree(t.c), ['A', '[F]', '  X', '  Y', '  [Inner]', '    Z', 'B', '[G]']);
    });

    test('a folder cannot go into a child or a grandchild, and nothing is changed by the attempt', () async {
      final t = await fixture();
      final deep = await folder(t.c, 'Deep', parent: t.inner);
      final before = await tree(t.c);
      final levels = [await indexes(t.c), await indexes(t.c, parent: t.f), await indexes(t.c, parent: t.inner)];

      await expectLater(order.moveFolder(t.f, collectionId: t.c, parentFolderId: t.inner), throwsA(isA<MoveRefusedException>()));
      await expectLater(order.moveFolder(t.f, collectionId: t.c, parentFolderId: deep), throwsA(isA<MoveRefusedException>()));
      await expectLater(order.moveFolder(t.inner, collectionId: t.c, parentFolderId: deep), throwsA(isA<MoveRefusedException>()));

      expect(await tree(t.c), before);
      expect([await indexes(t.c), await indexes(t.c, parent: t.f), await indexes(t.c, parent: t.inner)], levels);
    });

    test('into a collection of its own with the whole subtree: ids stay, nesting and order stay', () async {
      final t = await fixture();
      final other = await collection('Other');
      await request(other, 'existing');
      await db.entityTagsDao.setTags('folder', t.f, ['core']);
      await db.entityDocsDao.setMarkdown('request', t.x, '# X docs');

      final receipt = await order.moveFolder(t.f, collectionId: other);

      expect(receipt.changedCollection, isTrue);
      expect(await tree(other), ['existing', '[F]', '  X', '  Y', '  [Inner]', '    Z']);
      expect(await tree(t.c), ['A', 'B', '[G]']);
      expect(await indexes(t.c), {'A': 0, 'B': 1, 'G': 2}, reason: 'the level it left is dense again');
      expect([(await folderRow(t.f)).collectionId, (await folderRow(t.inner)).collectionId], [other, other]);
      expect([(await row(t.x)).collectionId, (await row(t.z)).collectionId], [other, other]);
      expect(await db.entityTagsDao.tagsOf('folder', t.f), ['core']);
      expect(await db.entityDocsDao.markdownOf('request', t.x), '# X docs');
    });

    test('into a folder of another collection', () async {
      final t = await fixture();
      final other = await collection('Other');
      final target = await folder(other, 'Target');

      await order.moveFolder(t.inner, collectionId: other, parentFolderId: target);

      expect(await tree(other), ['[Target]', '  [Inner]', '    Z']);
      expect(await tree(t.c), ['A', '[F]', '  X', '  Y', 'B', '[G]']);
    });

    test('a folder keeps the defaults that belong to it when it changes collection', () async {
      final t = await fixture();
      final other = await collection('Other');
      await db.folderDefaultsDao.upsert(FolderDefaultsCompanion.insert(folderId: Value(t.f), headersJson: const Value('[{"key":"X","value":"1"}]')));

      await order.moveFolder(t.f, collectionId: other);

      expect((await db.folderDefaultsDao.findByFolder(t.f))?.headersJson, contains('"X"'));
      expect((await db.folderDefaultsDao.allForCollection(other)).map((d) => d.folderId), [t.f]);
      expect(await db.folderDefaultsDao.allForCollection(t.c), isEmpty);
    });
  });

  group('moving a request to another collection', () {
    test('what hangs off the request stays with it; what belongs to a collection stays where it is', () async {
      final t = await fixture();
      final other = await collection('Other');
      final target = await folder(other, 'Target');
      await db.into(db.collectionVariables).insert(
        CollectionVariablesCompanion.insert(collectionId: t.c, key: 'baseUrl', value: const Value('https://old.test')),
      );
      await db.requestScriptsDao.upsert(
        RequestScriptsCompanion.insert(requestId: Value(t.a), assertionsJson: const Value('[{"type":"statusIn2xx"}]')),
      );
      await db.responseExamplesDao.add(ResponseExamplesCompanion.insert(requestId: t.a, name: '200 OK', statusCode: 200));
      await db.requestSettingsDao.put(t.a, '{"followRedirects":false}');
      await db.entityTagsDao.setTags('request', t.a, ['smoke']);
      await db.entityDocsDao.setMarkdown('request', t.a, 'Docs of A');
      await db.entityUidsDao.put('request', t.a, 'uid-a');
      await db.entityUidsDao.put('request', t.b, 'uid-b');

      final receipt = await order.moveRequest(t.a, collectionId: other, folderId: target);

      final moved = await row(t.a);
      expect((moved.collectionId, moved.folderId), (other, target));
      expect(receipt.changedCollection, isTrue);
      expect((await db.requestScriptsDao.findByRequest(t.a))?.assertionsJson, contains('statusIn2xx'));
      expect((await db.responseExamplesDao.watchByRequest(t.a).first).map((e) => e.name), ['200 OK']);
      expect(await db.requestSettingsDao.get(t.a), '{"followRedirects":false}');
      expect(await db.entityTagsDao.tagsOf('request', t.a), ['smoke']);
      expect(await db.entityDocsDao.markdownOf('request', t.a), 'Docs of A');
      final variables = await db.select(db.collectionVariables).get();
      expect(variables.map((v) => (v.collectionId, v.key)), [(t.c, 'baseUrl')], reason: 'variables do not move');
      expect(await db.entityUidsDao.uidOf('request', t.a), isNull, reason: 'a request in a new collection is new to Git');
      expect(await db.entityUidsDao.uidOf('request', t.b), 'uid-b');
      expect(await tree(other), ['[Target]', '  A']);
    });

    test('lands before the chosen request of the other collection', () async {
      final t = await fixture();
      final other = await collection('Other');
      await request(other, 'o1');
      final o2 = await request(other, 'o2');

      await order.moveRequest(t.a, collectionId: other, before: OrderRef.request(o2));

      expect(await indexes(other), {'o1': 0, 'A': 1, 'o2': 2});
      expect(await indexes(t.c), {'F': 0, 'B': 1, 'G': 2});
    });
  });

  group('undo', () {
    test('puts a reorder back exactly', () async {
      final t = await fixture();
      final before = await indexes(t.c);

      final receipt = await order.moveRequest(t.b, collectionId: t.c, before: OrderRef.request(t.a));
      expect(await indexes(t.c), isNot(before));
      await order.undo(receipt);

      expect(await indexes(t.c), before);
    });

    test('puts a move into a folder back: parent, order of both levels', () async {
      final t = await fixture();
      final root = await indexes(t.c);
      final inside = await indexes(t.c, parent: t.f);

      final receipt = await order.moveRequest(t.a, collectionId: t.c, folderId: t.f, before: OrderRef.request(t.y));
      await order.undo(receipt);

      expect(await indexes(t.c), root);
      expect(await indexes(t.c, parent: t.f), inside);
      expect((await row(t.a)).folderId, isNull);
    });

    test('puts a folder and its whole subtree back into the collection it came from', () async {
      final t = await fixture();
      final other = await collection('Other');
      final before = await tree(t.c);
      final root = await indexes(t.c);

      final receipt = await order.moveFolder(t.f, collectionId: other);
      await order.undo(receipt);

      expect(await tree(t.c), before);
      expect(await indexes(t.c), root);
      expect(await tree(other), isEmpty);
      expect((await row(t.z)).collectionId, t.c);
    });

    test('skips what was deleted in the meantime, and re-roots what sat in a folder that is gone', () async {
      final t = await fixture();
      final receipt = await order.moveRequest(t.z, collectionId: t.c, before: OrderRef.folder(t.f));
      await db.collectionsDao.deleteFolder(t.inner);
      await db.requestsDao.deleteRequest(t.a);

      await order.undo(receipt);

      expect((await row(t.z).then((r) => r.id)), t.z);
      expect((await row(t.z)).folderId, isNull, reason: 'its folder is gone, so it stays at the top level');
    });

    test('an empty receipt is nothing to undo', () async {
      final t = await fixture();
      final receipt = await order.moveRequest(t.b, collectionId: t.c, before: OrderRef.folder(t.g));

      await order.undo(receipt);

      expect(await indexes(t.c), {'A': 0, 'F': 1, 'B': 2, 'G': 3});
    });
  });

  group('all or nothing', () {
    test('a failure part-way through a move leaves every row as it was', () async {
      final t = await fixture();
      // Writes to B fail, and moving A to the end has to write B (it shifts up).
      await db.customStatement(
        "CREATE TRIGGER no_writes_to_b BEFORE UPDATE ON requests WHEN NEW.id = ${t.b} "
        "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
      );
      final before = await indexes(t.c);

      await expectLater(order.moveRequest(t.a, collectionId: t.c), throwsA(anything));

      expect(await indexes(t.c), before, reason: 'the write that happened before the failure was rolled back');
      expect((await row(t.a)).orderIndex, 0);
    });

    test('a failed folder move into another collection changes nothing in either', () async {
      final t = await fixture();
      final other = await collection('Other');
      await db.customStatement(
        "CREATE TRIGGER no_writes_to_z BEFORE UPDATE ON requests WHEN NEW.id = ${t.z} "
        "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
      );
      final before = await tree(t.c);

      await expectLater(order.moveFolder(t.f, collectionId: other), throwsA(anything));

      expect(await tree(t.c), before);
      expect(await tree(other), isEmpty);
      expect((await folderRow(t.inner)).collectionId, t.c);
    });
  });
}
