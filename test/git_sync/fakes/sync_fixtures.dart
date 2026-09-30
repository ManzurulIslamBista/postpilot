import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';

SyncDoc collectionDoc({String uid = 'col', String name = 'API', Map<String, Object?> data = const {}}) =>
    SyncDoc(uid: uid, kind: SyncKind.collection, parentUid: null, name: name, data: data);

SyncDoc folderDoc(
  String uid,
  String name, {
  String parent = 'col',
  int order = 0,
  Map<String, Object?> data = const {},
}) =>
    SyncDoc(uid: uid, kind: SyncKind.folder, parentUid: parent, name: name, order: order, data: data);

SyncDoc requestDoc(
  String uid,
  String name, {
  String parent = 'col',
  int order = 0,
  String url = 'https://api.test/things',
  Map<String, Object?> data = const {},
}) =>
    SyncDoc(
      uid: uid,
      kind: SyncKind.request,
      parentUid: parent,
      name: name,
      order: order,
      data: {'method': 'GET', 'url': url, ...data},
    );

SyncSnapshot snapshotOf(Iterable<SyncDoc> docs) => SyncSnapshot({for (final doc in docs) doc.uid: doc});

/// [doc] with some of its fields (`name`, `parentUid`, `order` or data keys) replaced.
SyncDoc edited(SyncDoc doc, Map<String, Object?> changes) => doc.withFields({...doc.fields, ...changes});

/// [doc] with a field removed altogether (not set to null).
SyncDoc without(SyncDoc doc, String key) => doc.withFields({...doc.fields}..remove(key));

/// [uid] plus the uids of everything below it.
Set<String> subtreeOf(Map<String, SyncDoc> docs, String uid) {
  final found = {uid};
  var grew = true;
  while (grew) {
    grew = false;
    for (final doc in docs.values) {
      if (found.contains(doc.parentUid) && found.add(doc.uid)) grew = true;
    }
  }
  return found;
}

/// [snapshot] with [docs] added or replaced and the uids in [drop] removed.
SyncSnapshot changed(SyncSnapshot snapshot, {Iterable<SyncDoc> docs = const [], Iterable<String> drop = const []}) {
  final replaced = docs.map((doc) => doc.uid).toSet();
  return snapshotOf([
    ...snapshot.docs.values.where((doc) => !drop.contains(doc.uid) && !replaced.contains(doc.uid)),
    ...docs,
  ]);
}
