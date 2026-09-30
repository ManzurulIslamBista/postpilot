import '../entities/git_sync_results.dart';
import '../entities/sync_doc.dart';
import 'doc_fields.dart';
import 'repo_layout.dart';

/// The merged collection plus the entities that still need a decision.
final class MergeOutcome {
  /// Unresolved entities are left as their local version; do not apply while
  /// [conflicts] is not empty.
  final SyncSnapshot merged;
  final List<SyncConflict> conflicts;

  const MergeOutcome({required this.merged, required this.conflicts});
}

typedef _Merge = ({SyncDoc? doc, SyncConflict? conflict});

/// Merges the local and the remote state of a collection against the state
/// both last shared (base), entity by entity on uid and field by field inside
/// an entity.
abstract final class ThreeWayMerger {
  static MergeOutcome merge({
    required SyncSnapshot base,
    required SyncSnapshot local,
    required SyncSnapshot remote,
    ConflictResolutions? resolutions,
  }) {
    var baseSide = base;
    var localSide = local;
    var remoteSide = remote;
    final rootUid = local.root?.uid ?? base.root?.uid ?? remote.root?.uid;
    if (rootUid != null) {
      baseSide = alignRoot(base, rootUid);
      remoteSide = _withRoot(alignRoot(remote, rootUid), rootUid, baseSide.docs[rootUid] ?? local.docs[rootUid]);
      localSide = _withRoot(local, rootUid, baseSide.docs[rootUid] ?? remoteSide.docs[rootUid]);
    }

    final baseText = _texts(baseSide);
    final localText = _texts(localSide);
    final remoteText = _texts(remoteSide);
    final merged = <String, SyncDoc>{};
    final conflicts = <SyncConflict>[];
    final uids = <String>{...localSide.docs.keys, ...remoteSide.docs.keys, ...baseSide.docs.keys};
    for (final uid in uids) {
      final result = _mergeDoc(
        base: baseSide.docs[uid],
        local: localSide.docs[uid],
        remote: remoteSide.docs[uid],
        baseText: baseText[uid],
        localText: localText[uid],
        remoteText: remoteText[uid],
        choice: resolutions?[uid],
      );
      final doc = result.doc;
      if (doc != null) merged[uid] = doc;
      final conflict = result.conflict;
      if (conflict != null) conflicts.add(conflict);
    }
    conflicts.sort((a, b) => DocFields.compareEntries(a.kind, a.name, a.uid, b.kind, b.name, b.uid));
    return MergeOutcome(merged: RepoLayout.repairParents(SyncSnapshot(merged)), conflicts: conflicts);
  }

  /// [snapshot] with its collection doc given the uid [rootUid] (and the
  /// top-level docs pointing at it), so two histories that created their
  /// collection doc independently still merge as one collection.
  static SyncSnapshot alignRoot(SyncSnapshot snapshot, String rootUid) {
    final root = snapshot.root;
    if (root == null || root.uid == rootUid) return snapshot;
    final docs = <String, SyncDoc>{};
    for (final doc in snapshot.docs.values) {
      if (doc.uid == root.uid) {
        docs[rootUid] = _copy(doc, uid: rootUid, parentUid: null);
      } else if (doc.parentUid == root.uid) {
        docs[doc.uid] = _copy(doc, uid: doc.uid, parentUid: rootUid);
      } else {
        docs[doc.uid] = doc;
      }
    }
    return SyncSnapshot(docs);
  }

  // The collection doc is never deleted by a merge: a side that lacks it is
  // treated as still holding [fallback].
  static SyncSnapshot _withRoot(SyncSnapshot snapshot, String rootUid, SyncDoc? fallback) =>
      snapshot.docs.containsKey(rootUid) || fallback == null
          ? snapshot
          : SyncSnapshot({...snapshot.docs, rootUid: fallback});

  static Map<String, String> _texts(SyncSnapshot snapshot) =>
      {for (final e in snapshot.docs.entries) e.key: e.value.canonicalText};

  static SyncDoc _copy(SyncDoc doc, {required String uid, required String? parentUid}) => SyncDoc(
        uid: uid,
        kind: doc.kind,
        parentUid: parentUid,
        name: doc.name,
        order: doc.order,
        data: doc.data,
      );

  static _Merge _mergeDoc({
    required SyncDoc? base,
    required SyncDoc? local,
    required SyncDoc? remote,
    required String? baseText,
    required String? localText,
    required String? remoteText,
    required ConflictChoice? choice,
  }) {
    if (base == null) {
      if (local == null) return (doc: remote, conflict: null);
      if (remote == null || localText == remoteText) return (doc: local, conflict: null);
      return _mergeFields(null, local, remote, choice);
    }

    final localChanged = local == null || localText != baseText;
    final remoteChanged = remote == null || remoteText != baseText;
    if (!localChanged) return (doc: remote, conflict: null);
    if (!remoteChanged) return (doc: local, conflict: null);
    if (local == null && remote == null) return (doc: null, conflict: null);

    if (local == null) {
      final conflict = _entityConflict(remote!, ConflictKind.deletedLocallyModifiedRemotely);
      return switch (choice) {
        ConflictChoice.remote => (doc: remote, conflict: null),
        ConflictChoice.local => (doc: null, conflict: null),
        null => (doc: null, conflict: conflict),
      };
    }
    if (remote == null) {
      final conflict = _entityConflict(local, ConflictKind.modifiedLocallyDeletedRemotely);
      return switch (choice) {
        ConflictChoice.local => (doc: local, conflict: null),
        ConflictChoice.remote => (doc: null, conflict: null),
        null => (doc: local, conflict: conflict),
      };
    }
    if (localText == remoteText) return (doc: local, conflict: null);
    return _mergeFields(base, local, remote, choice);
  }

  static _Merge _mergeFields(SyncDoc? base, SyncDoc local, SyncDoc remote, ConflictChoice? choice) {
    final baseFields = base?.fields;
    final localFields = local.fields;
    final remoteFields = remote.fields;
    final merged = <String, Object?>{};
    final clashes = <FieldConflict>[];

    for (final key in DocFields.ordered({...localFields.keys, ...remoteFields.keys, ...?baseFields?.keys})) {
      final Map<String, Object?> winner;
      if (DocFields.sameEntry(localFields, remoteFields, key)) {
        winner = localFields;
      } else if (baseFields != null && DocFields.sameEntry(localFields, baseFields, key)) {
        winner = remoteFields;
      } else if (baseFields != null && DocFields.sameEntry(remoteFields, baseFields, key)) {
        winner = localFields;
      } else {
        clashes.add(FieldConflict(
          field: key,
          base: baseFields?[key],
          local: localFields[key],
          remote: remoteFields[key],
        ));
        winner = choice == ConflictChoice.remote ? remoteFields : localFields;
      }
      if (winner.containsKey(key)) merged[key] = winner[key];
    }

    if (clashes.isEmpty || choice != null) return (doc: local.withFields(merged), conflict: null);
    return (
      doc: local,
      conflict: SyncConflict(
        uid: local.uid,
        kind: local.kind,
        name: local.name,
        type: ConflictKind.bothModified,
        fields: clashes,
      ),
    );
  }

  static SyncConflict _entityConflict(SyncDoc doc, ConflictKind type) =>
      SyncConflict(uid: doc.uid, kind: doc.kind, name: doc.name, type: type);
}
