import 'package:postpilot/features/git_sync/domain/entities/sync_doc.dart';
import 'package:postpilot/features/git_sync/domain/repositories/local_collection_store.dart';
import 'package:postpilot/features/git_sync/domain/services/secret_fields.dart';

/// In-memory stand-in for the local database: docs per collection id.
class FakeLocalStore implements LocalCollectionStore {
  final collections = <int, Map<String, SyncDoc>>{};

  var _nextCollectionId = 1;
  var _nextRequestId = 1;
  final _requestIds = <String, int>{};

  /// Creates a collection holding only its own doc; returns the local id.
  int addCollection({String uid = 'col', String name = 'API', Map<String, Object?> data = const {}}) {
    final id = _nextCollectionId++;
    collections[id] = {
      uid: SyncDoc(uid: uid, kind: SyncKind.collection, parentUid: null, name: name, data: data),
    };
    return id;
  }

  /// A local edit: adds or replaces a doc.
  void upsert(int collectionId, SyncDoc doc) => collections[collectionId]![doc.uid] = doc;

  /// A local delete; like the app, it takes everything inside a folder along.
  void remove(int collectionId, String uid) {
    final docs = collections[collectionId]!;
    final doomed = {uid};
    var grew = true;
    while (grew) {
      grew = false;
      for (final doc in docs.values) {
        if (doomed.contains(doc.parentUid) && doomed.add(doc.uid)) grew = true;
      }
    }
    docs.removeWhere((key, _) => doomed.contains(key));
  }

  SyncDoc? doc(int collectionId, String uid) => collections[collectionId]?[uid];

  /// Local id of a request; stable per collection and uid.
  int requestId(int collectionId, String uid) => _requestIds.putIfAbsent('$collectionId/$uid', () => _nextRequestId++);

  @override
  Future<SyncSnapshot> readSnapshot(int collectionId, {required bool includeSecrets}) async {
    final docs = collections[collectionId] ?? (throw StateError('No collection $collectionId'));
    return SyncSnapshot({
      for (final doc in docs.values) doc.uid: includeSecrets ? doc : _withoutAuthSecrets(doc),
    });
  }

  @override
  Future<ApplyOutcome> applySnapshot(SyncSnapshot target, {int? collectionId}) async {
    final id = collectionId ?? _nextCollectionId++;
    final current = collections.putIfAbsent(id, () => {});
    var added = 0;
    var updated = 0;
    var deleted = 0;
    final changedRequests = <int>[];
    final deletedRequests = <int>[];

    for (final doc in target.docs.values) {
      final old = current[doc.uid];
      final next = _keepLocalSecrets(old, doc);
      if (old == null) {
        added++;
      } else if (old != next) {
        updated++;
        if (doc.kind == SyncKind.request) changedRequests.add(requestId(id, doc.uid));
      }
      current[doc.uid] = next;
    }
    for (final uid in current.keys.where((uid) => !target.docs.containsKey(uid)).toList()) {
      final old = current.remove(uid)!;
      deleted++;
      if (old.kind == SyncKind.request) deletedRequests.add(requestId(id, uid));
    }
    return ApplyOutcome(
      collectionId: id,
      added: added,
      updated: updated,
      deleted: deleted,
      changedRequestIds: changedRequests,
      deletedRequestIds: deletedRequests,
    );
  }

  static SyncDoc _withoutAuthSecrets(SyncDoc doc) {
    final auth = doc.data['auth'];
    if (auth is! Map) return doc;
    return _withAuth(doc, SecretFields.stripAuth(Map<String, Object?>.from(auth)));
  }

  static SyncDoc _keepLocalSecrets(SyncDoc? current, SyncDoc target) {
    final oldAuth = current?.data['auth'];
    final newAuth = target.data['auth'];
    if (oldAuth is! Map || newAuth is! Map) return target;
    final auth = Map<String, Object?>.from(newAuth);
    for (final key in SecretFields.authKeys) {
      if (_isFilled(oldAuth[key]) && !_isFilled(auth[key])) auth[key] = oldAuth[key];
    }
    return _withAuth(target, auth);
  }

  static bool _isFilled(Object? value) => value != null && value != '';

  static SyncDoc _withAuth(SyncDoc doc, Map<String, Object?> auth) => SyncDoc(
        uid: doc.uid,
        kind: doc.kind,
        parentUid: doc.parentUid,
        name: doc.name,
        order: doc.order,
        data: {...doc.data, 'auth': auth},
      );
}
