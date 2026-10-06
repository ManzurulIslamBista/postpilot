// Git carries order_index as the `order` of each doc. These tests check that what a move writes is small and local
// enough that two people arranging different parts of a collection merge without a conflict.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/collections/data/repositories/collection_order_repository_impl.dart';
import 'package:postpilot/features/collections/domain/services/collection_order.dart';
import 'package:postpilot/features/git_sync/data/repositories/entity_uid_registry.dart';
import 'package:postpilot/features/git_sync/data/repositories/local_collection_store_impl.dart';
import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/services/three_way_merger.dart';

/// One installation: its own database, uid registry, sync store and mover.
final class _Device {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  late final uids = EntityUidRegistry(db.entityUidsDao);
  late final store = LocalCollectionStoreImpl(db, uids);
  late final order = CollectionOrderRepositoryImpl(db.collectionsDao);

  Future<SyncSnapshot> read(int collectionId) => store.readSnapshot(collectionId, includeSecrets: true);

  Future<int> localId(SyncSnapshot snapshot, String name, SyncKind kind) async {
    final doc = snapshot.docs.values.firstWhere((d) => d.name == name && d.kind == kind);
    return (await uids.localIdFor(kind, doc.uid))!;
  }
}

SyncDoc _doc(SyncSnapshot s, String name) => s.docs.values.firstWhere((d) => d.name == name && d.kind != SyncKind.collection);

/// The request names of [parentName]'s level (or the top level when null) by `order`.
List<String> _level(SyncSnapshot s, String? parentName) {
  final parent = parentName == null ? s.root!.uid : _doc(s, parentName).uid;
  final docs = s.docs.values.where((d) => d.parentUid == parent).toList()..sort((a, b) => a.order.compareTo(b.order));
  return [for (final d in docs) d.name];
}

void main() {
  late _Device a;
  late _Device b;
  late int c;
  late int cB;
  late SyncSnapshot base;

  setUp(() async {
    a = _Device();
    b = _Device();
    c = await a.db.collectionsDao.createCollection('C');
    Future<int> request(String name, {int? folder}) => a.db.requestsDao.createRequest(
      RequestsCompanion.insert(collectionId: c, folderId: Value(folder), name: name),
    );
    final f1 = await a.db.collectionsDao.createFolder(collectionId: c, name: 'F1');
    for (final n in ['a1', 'a2', 'a3']) {
      await request(n, folder: f1);
    }
    final f2 = await a.db.collectionsDao.createFolder(collectionId: c, name: 'F2');
    for (final n in ['b1', 'b2']) {
      await request(n, folder: f2);
    }
    await request('r1');
    await request('r2');
    base = await a.read(c);
    cB = (await b.store.applySnapshot(base)).collectionId;
  });

  tearDown(() async {
    await a.db.close();
    await b.db.close();
  });

  test('what Git sees: every sibling carries its position, folders and requests of a level on one scale', () {
    expect(_level(base, null), ['F1', 'F2', 'r1', 'r2']);
    expect(_level(base, 'F1'), ['a1', 'a2', 'a3']);
    expect({for (final d in base.docs.values.where((d) => d.parentUid == base.root!.uid)) d.name: d.order}, {
      'F1': 0,
      'F2': 1,
      'r1': 2,
      'r2': 3,
    });
  });

  test('two people arranging different folders merge without a conflict, and both arrangements survive', () async {
    await a.order.moveRequest(await a.localId(base, 'a3', SyncKind.request), collectionId: c,
        folderId: await a.localId(base, 'F1', SyncKind.folder), before: OrderRef.request(await a.localId(base, 'a1', SyncKind.request)));
    await b.order.moveRequest(await b.localId(base, 'b2', SyncKind.request), collectionId: cB,
        folderId: await b.localId(base, 'F2', SyncKind.folder), before: OrderRef.request(await b.localId(base, 'b1', SyncKind.request)));

    final mine = await a.read(c);
    final theirs = await b.read(cB);
    final outcome = ThreeWayMerger.merge(base: base, local: mine, remote: theirs);

    expect(outcome.conflicts, isEmpty);
    expect(_level(outcome.merged, 'F1'), ['a3', 'a1', 'a2']);
    expect(_level(outcome.merged, 'F2'), ['b2', 'b1']);
    for (final untouched in ['F1', 'F2', 'r1', 'r2']) {
      expect(_doc(outcome.merged, untouched).canonicalText, _doc(base, untouched).canonicalText, reason: untouched);
    }
    // Applying the merge leaves the database in that arrangement.
    await a.store.applySnapshot(outcome.merged, collectionId: c);
    final again = await a.read(c);
    expect(_level(again, 'F1'), ['a3', 'a1', 'a2']);
    expect(_level(again, 'F2'), ['b2', 'b1']);
  });

  test('a move touches only the rows of the levels it changes', () async {
    await a.order.moveRequest(await a.localId(base, 'a3', SyncKind.request), collectionId: c,
        folderId: await a.localId(base, 'F1', SyncKind.folder), before: OrderRef.request(await a.localId(base, 'a1', SyncKind.request)));

    final after = await a.read(c);

    final changed = {
      for (final d in after.docs.values)
        if (d.canonicalText != base.docs[d.uid]!.canonicalText) d.name,
    };
    expect(changed, {'a1', 'a2', 'a3'}, reason: 'the other folder, the top level and the collection are byte-for-byte as before');
  });

  test('one person moves a request to another folder while the other reorders the top level: no conflict', () async {
    await a.order.moveRequest(await a.localId(base, 'a1', SyncKind.request), collectionId: c,
        folderId: await a.localId(base, 'F2', SyncKind.folder));
    await b.order.moveRequest(await b.localId(base, 'r2', SyncKind.request), collectionId: cB,
        before: OrderRef.request(await b.localId(base, 'r1', SyncKind.request)));

    final outcome = ThreeWayMerger.merge(base: base, local: await a.read(c), remote: await b.read(cB));

    expect(outcome.conflicts, isEmpty);
    expect(_doc(outcome.merged, 'a1').parentUid, _doc(base, 'F2').uid);
    expect(_level(outcome.merged, null), ['F1', 'F2', 'r2', 'r1']);
    expect(_level(outcome.merged, 'F2'), ['b1', 'b2', 'a1']);
  });

  test('two people rearranging the same level differently do conflict, and only on what they disagree about', () async {
    final f1A = await a.localId(base, 'F1', SyncKind.folder);
    final f1B = await b.localId(base, 'F1', SyncKind.folder);
    await a.order.moveRequest(await a.localId(base, 'a3', SyncKind.request), collectionId: c, folderId: f1A,
        before: OrderRef.request(await a.localId(base, 'a1', SyncKind.request)));
    await b.order.moveRequest(await b.localId(base, 'a2', SyncKind.request), collectionId: cB, folderId: f1B,
        before: OrderRef.request(await b.localId(base, 'a1', SyncKind.request)));

    final outcome = ThreeWayMerger.merge(base: base, local: await a.read(c), remote: await b.read(cB));

    // a1 ends up second for both, a3 only moved for A: the one real disagreement is a2 (A: last, B: first)
    expect(outcome.conflicts.map((x) => x.name), ['a2']);
  });

  test('a clone gets the order the original had, interleaving of folders and requests included', () async {
    // top level of the original: F1, F2, r1, r2. Move r2 in front of F1 and check what a clone lists.
    await a.order.moveRequest(await a.localId(base, 'r2', SyncKind.request), collectionId: c,
        before: OrderRef.folder(await a.localId(base, 'F1', SyncKind.folder)));
    final arranged = await a.read(c);
    final clone = _Device();
    addTearDown(clone.db.close);

    final cloneId = (await clone.store.applySnapshot(arranged)).collectionId;

    expect(_level(await clone.read(cloneId), null), ['r2', 'F1', 'F2', 'r1']);
    final folders = await (clone.db.select(clone.db.folders)..where((t) => t.collectionId.equals(cloneId))).get();
    final requests = await (clone.db.select(clone.db.requests)..where((t) => t.collectionId.equals(cloneId))).get();
    final canonical = CollectionOrder.of(
      folders: [for (final f in folders) (id: f.id, parentId: f.parentFolderId, orderIndex: f.orderIndex)],
      requests: [for (final r in requests) (id: r.id, folderId: r.folderId, orderIndex: r.orderIndex)],
    );
    expect(
      [for (final e in canonical.childrenOf(null)) e.isFolder ? folders[e.index].name : requests[e.index].name],
      ['r2', 'F1', 'F2', 'r1'],
    );
  });
}
