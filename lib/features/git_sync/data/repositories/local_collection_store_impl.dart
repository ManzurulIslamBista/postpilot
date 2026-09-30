import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm, Value, innerJoin;

import '../../../../core/database/app_database.dart';
import '../../domain/entities/git_sync_exceptions.dart';
import '../../domain/entities/sync_doc.dart';
import '../../domain/repositories/local_collection_store.dart';
import '../../domain/services/doc_fields.dart';
import '../../domain/services/repo_layout.dart';
import '../../domain/services/secret_fields.dart';
import '../../domain/services/three_way_merger.dart';
import '../mappers/collection_doc_mapper.dart';
import '../mappers/folder_doc_mapper.dart';
import '../mappers/request_doc_mapper.dart';
import 'entity_uid_registry.dart';

final class LocalCollectionStoreImpl implements LocalCollectionStore {
  static const _idChunk = 400;
  static const _alreadyCloned = GitSyncException('This collection is already cloned on this device.');

  final AppDatabase _db;
  final EntityUidRegistry _uids;

  const LocalCollectionStoreImpl(this._db, this._uids);

  @override
  Future<SyncSnapshot> readSnapshot(int collectionId, {required bool includeSecrets}) => _db.transaction(() async {
        final local = await _load(collectionId);
        return SyncSnapshot({
          for (final doc in local.docs.values) doc.uid: includeSecrets ? doc : SecretFields.stripDoc(doc),
        });
      });

  @override
  Future<ApplyOutcome> applySnapshot(SyncSnapshot target, {int? collectionId}) =>
      _db.transaction(() => _apply(target, collectionId));

  Future<ApplyOutcome> _apply(SyncSnapshot snapshot, int? collectionId) async {
    if (snapshot.docs.values.where((doc) => doc.kind == SyncKind.collection).length != 1) {
      throw const GitSyncException('The synced files must describe exactly one collection.');
    }
    final local = collectionId == null ? null : await _load(collectionId);
    // The local collection keeps its own uid, whatever the remote calls its collection doc.
    final target = RepoLayout.repairParents(local == null ? snapshot : ThreeWayMerger.alignRoot(snapshot, local.uid));
    final root = target.root!;
    await _releaseStaleUids(target, local);

    final id = collectionId ?? await _db.into(_db.collections).insert(CollectionsCompanion.insert(name: root.name));
    if (local == null) await _uids.adopt(SyncKind.collection, id, root.uid);

    final tally = _Tally();
    await _applyCollection(id, root, local?.docs[root.uid], tally);
    final folderIds = await _applyFolders(id, target, local, tally);
    await _applyRequests(id, target, local, folderIds, tally);
    if (local != null) await _deleteAbsent(target, local, tally);
    return ApplyOutcome(
      collectionId: id,
      added: tally.added,
      updated: tally.updated,
      deleted: tally.deleted,
      changedRequestIds: tally.changedRequestIds,
      deletedRequestIds: tally.deletedRequestIds,
    );
  }

  /// A target uid that already belongs to a local entity elsewhere means the
  /// repository is cloned here already. One that belongs to an entity which no
  /// longer exists (a local delete leaves its binding behind) is freed so the
  /// uid can be adopted again.
  Future<void> _releaseStaleUids(SyncSnapshot target, _Local? local) async {
    final stale = <(SyncKind, int)>[];
    for (final kind in SyncKind.values) {
      for (final binding in (await _uids.uidsFor(kind)).entries) {
        final doc = target.docs[binding.value];
        if (doc == null || (doc.kind == kind && local != null && local.owns(kind, binding.key))) continue;
        if (await _exists(kind, binding.key)) throw _alreadyCloned;
        stale.add((kind, binding.key));
      }
    }
    for (final (kind, localId) in stale) {
      await (_db.delete(_db.entityUids)..where((t) => t.kind.equals(kind.name) & t.localId.equals(localId))).go();
    }
  }

  Future<bool> _exists(SyncKind kind, int id) async => switch (kind) {
        SyncKind.collection => await (_db.select(_db.collections)..where((t) => t.id.equals(id))).get(),
        SyncKind.folder => await (_db.select(_db.folders)..where((t) => t.id.equals(id))).get(),
        SyncKind.request => await (_db.select(_db.requests)..where((t) => t.id.equals(id))).get(),
      }
          .isNotEmpty;

  Future<void> _applyCollection(int id, SyncDoc root, SyncDoc? before, _Tally tally) async {
    final after = _parsed(root, () => CollectionDocMapper.canonical(root, local: before));
    if (before == null) {
      tally.added++;
    } else if (before == after) {
      return;
    } else {
      tally.updated++;
    }
    if (before != null && before.name != after.name) await _db.collectionsDao.renameCollection(id, after.name);
    if (_differs(before, after, 'variables')) {
      await (_db.delete(_db.collectionVariables)..where((t) => t.collectionId.equals(id))).go();
      for (final variable in after.data['variables'] as List? ?? const []) {
        await _db.into(_db.collectionVariables).insert(CollectionVariablesCompanion.insert(
              collectionId: id,
              key: variable['key'] as String,
              value: Value(variable['value'] as String),
              enabled: Value(variable['enabled'] as bool),
            ));
      }
    }
    if (_differs(before, after, 'auth')) {
      final authJson = CollectionDocMapper.authJson(after);
      if (authJson == null) {
        await (_db.delete(_db.collectionAuth)..where((t) => t.collectionId.equals(id))).go();
      } else {
        await _db.collectionAuthDao.upsert(id, authJson);
      }
    }
    await _writeNotes(SyncKind.collection, id, after, before);
  }

  /// Creates or updates every folder, parents before children. Returns the
  /// local id of every folder by uid.
  Future<Map<String, int>> _applyFolders(int collectionId, SyncSnapshot target, _Local? local, _Tally tally) async {
    final ids = {...?local?.folderIds};
    for (final doc in _foldersParentFirst(target)) {
      final before = local?.docs[doc.uid];
      final after = _parsed(doc, () => FolderDocMapper.canonical(doc));
      final parentId = after.parentUid == target.root!.uid ? null : ids[after.parentUid];
      final existingId = ids[doc.uid];
      if (existingId == null) {
        final id = await _db.into(_db.folders).insert(FoldersCompanion.insert(
              collectionId: collectionId,
              parentFolderId: Value(parentId),
              name: after.name,
              orderIndex: Value(after.order),
            ));
        await _uids.adopt(SyncKind.folder, id, doc.uid);
        ids[doc.uid] = id;
        await _writeNotes(SyncKind.folder, id, after, null);
        tally.added++;
      } else if (before != after) {
        await (_db.update(_db.folders)..where((t) => t.id.equals(existingId))).write(FoldersCompanion(
          parentFolderId: Value(parentId),
          name: Value(after.name),
          orderIndex: Value(after.order),
        ));
        await _writeNotes(SyncKind.folder, existingId, after, before);
        tally.updated++;
      }
    }
    return ids;
  }

  Future<void> _applyRequests(
    int collectionId,
    SyncSnapshot target,
    _Local? local,
    Map<String, int> folderIds,
    _Tally tally,
  ) async {
    final requestIds = local?.requestIds ?? const <String, int>{};
    final docs = [for (final doc in target.docs.values) if (doc.kind == SyncKind.request) doc]..sort(_bySiblingOrder);
    for (final doc in docs) {
      final before = local?.docs[doc.uid];
      final after = _parsed(doc, () => RequestDocMapper.canonical(doc, local: before));
      final folderId = after.parentUid == target.root!.uid ? null : folderIds[after.parentUid];
      final existingId = requestIds[doc.uid];
      if (existingId == null) {
        final row = RequestDocMapper.toCompanion(after, folderId: folderId).copyWith(collectionId: Value(collectionId));
        final id = await _db.into(_db.requests).insert(row);
        await _uids.adopt(SyncKind.request, id, doc.uid);
        await _writeRequestExtras(id, after, null);
        tally.added++;
      } else if (before != after) {
        await (_db.update(_db.requests)..where((t) => t.id.equals(existingId)))
            .write(RequestDocMapper.toCompanion(after, folderId: folderId));
        await _writeRequestExtras(existingId, after, before);
        tally.updated++;
        tally.changedRequestIds.add(existingId);
      }
    }
  }

  /// Removes the local entities the target no longer has: requests first (a
  /// folder delete would only detach them), then folders, deepest first.
  Future<void> _deleteAbsent(SyncSnapshot target, _Local local, _Tally tally) async {
    final requestIds = [
      for (final entry in local.requestUids.entries)
        if (!target.docs.containsKey(entry.value)) entry.key,
    ];
    final folders = [
      for (final folder in local.folders)
        if (!target.docs.containsKey(local.folderUids[folder.id])) folder,
    ]..sort((a, b) => local.depth(b).compareTo(local.depth(a)));
    final folderIds = [for (final folder in folders) folder.id];

    for (final chunk in _chunks(requestIds)) {
      await (_db.delete(_db.requests)..where((t) => t.id.isIn(chunk))).go();
    }
    for (final chunk in _chunks(folderIds)) {
      await (_db.delete(_db.folders)..where((t) => t.id.isIn(chunk))).go();
    }
    await _forget(SyncKind.request, requestIds);
    await _forget(SyncKind.folder, folderIds);
    tally.deleted += requestIds.length + folderIds.length;
    tally.deletedRequestIds.addAll(requestIds);
  }

  /// Drops what is keyed by the id of an entity that no longer exists.
  Future<void> _forget(SyncKind kind, List<int> localIds) async {
    for (final chunk in _chunks(localIds)) {
      await (_db.delete(_db.entityUids)..where((t) => t.kind.equals(kind.name) & t.localId.isIn(chunk))).go();
      await (_db.delete(_db.entityDocs)..where((t) => t.kind.equals(kind.name) & t.localId.isIn(chunk))).go();
      await (_db.delete(_db.entityTags)..where((t) => t.kind.equals(kind.name) & t.localId.isIn(chunk))).go();
    }
  }

  Future<void> _writeRequestExtras(int id, SyncDoc after, SyncDoc? before) async {
    if (_differs(before, after, 'tests')) {
      final tests = after.data['tests'] as Map?;
      if (tests == null) {
        await (_db.delete(_db.requestScripts)..where((t) => t.requestId.equals(id))).go();
      } else {
        await _db.requestScriptsDao.upsert(RequestScriptsCompanion.insert(
          requestId: Value(id),
          assertionsJson: Value(jsonEncode(tests['assertions'])),
          extractorsJson: Value(jsonEncode(tests['extractors'])),
        ));
      }
    }
    if (_differs(before, after, 'settings')) {
      final settings = after.data['settings'];
      if (settings == null) {
        await _db.requestSettingsDao.remove(id);
      } else {
        await _db.requestSettingsDao.put(id, jsonEncode(settings));
      }
    }
    await _writeNotes(SyncKind.request, id, after, before);
  }

  Future<void> _writeNotes(SyncKind kind, int id, SyncDoc after, SyncDoc? before) async {
    if (_differs(before, after, 'description')) {
      await _db.entityDocsDao.setMarkdown(kind.name, id, after.data['description'] as String? ?? '');
    }
    if (_differs(before, after, 'tags')) {
      final tags = [for (final tag in after.data['tags'] as List? ?? const []) tag as String];
      await _db.entityTagsDao.setTags(kind.name, id, tags);
    }
  }

  /// Every entity of the collection as a doc with its credentials. Entities
  /// that have no uid yet get one here, so nothing stays invisible to a sync.
  Future<_Local> _load(int collectionId) async {
    final row = await (_db.select(_db.collections)..where((t) => t.id.equals(collectionId))).getSingleOrNull();
    if (row == null) throw const GitSyncException('This collection no longer exists.');
    final folders = await (_db.select(_db.folders)
          ..where((t) => t.collectionId.equals(collectionId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    final requests = await (_db.select(_db.requests)
          ..where((t) => t.collectionId.equals(collectionId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    final variables = await (_db.select(_db.collectionVariables)
          ..where((t) => t.collectionId.equals(collectionId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    final auth = await _db.collectionAuthDao.findByCollection(collectionId);
    final scripts = {
      for (final script in await (_db.select(_db.requestScripts).join([
        innerJoin(_db.requests, _db.requests.id.equalsExp(_db.requestScripts.requestId)),
      ])
            ..where(_db.requests.collectionId.equals(collectionId)))
          .map((r) => r.readTable(_db.requestScripts))
          .get())
        script.requestId: script,
    };
    final settings = {
      for (final entry in await (_db.select(_db.requestSettingEntries).join([
        innerJoin(_db.requests, _db.requests.id.equalsExp(_db.requestSettingEntries.requestId)),
      ])
            ..where(_db.requests.collectionId.equals(collectionId)))
          .map((r) => r.readTable(_db.requestSettingEntries))
          .get())
        entry.requestId: entry.settingsJson,
    };
    final descriptions = {
      for (final kind in SyncKind.values) kind: await _db.entityDocsDao.markdownByLocalId(kind.name),
    };
    final tags = {for (final kind in SyncKind.values) kind: await _db.entityTagsDao.tagsByLocalId(kind.name)};

    final collectionUid = await _uids.uidFor(SyncKind.collection, collectionId);
    final folderUids = await _uidsOf(SyncKind.folder, [for (final f in folders) f.id]);
    final requestUids = await _uidsOf(SyncKind.request, [for (final r in requests) r.id]);
    String parentOf(int? folderId) => folderId == null ? collectionUid : folderUids[folderId] ?? collectionUid;

    final docs = <String, SyncDoc>{
      collectionUid: CollectionDocMapper.toDoc(
        row,
        uid: collectionUid,
        description: descriptions[SyncKind.collection]![collectionId] ?? '',
        tags: tags[SyncKind.collection]![collectionId] ?? const [],
        variables: variables,
        auth: auth,
      ),
    };
    for (final folder in folders) {
      final uid = folderUids[folder.id]!;
      docs[uid] = FolderDocMapper.toDoc(
        folder,
        uid: uid,
        parentUid: parentOf(folder.parentFolderId),
        description: descriptions[SyncKind.folder]![folder.id] ?? '',
        tags: tags[SyncKind.folder]![folder.id] ?? const [],
      );
    }
    for (final request in requests) {
      final uid = requestUids[request.id]!;
      docs[uid] = RequestDocMapper.toDoc(
        request,
        uid: uid,
        parentUid: parentOf(request.folderId),
        scripts: scripts[request.id],
        settingsJson: settings[request.id],
        description: descriptions[SyncKind.request]![request.id] ?? '',
        tags: tags[SyncKind.request]![request.id] ?? const [],
      );
    }
    return _Local(collectionId, collectionUid, folders, folderUids, requestUids, docs);
  }

  Future<Map<int, String>> _uidsOf(SyncKind kind, List<int> localIds) async {
    final known = await _uids.uidsFor(kind);
    return {for (final id in localIds) id: known[id] ?? await _uids.uidFor(kind, id)};
  }

  /// A doc whose fields have the wrong JSON type fails the whole apply.
  static SyncDoc _parsed(SyncDoc doc, SyncDoc Function() canonical) {
    try {
      return canonical();
    } on TypeError {
      throw GitSyncException('The ${doc.kind.name} "${doc.name}" has an unexpected format and cannot be applied.');
    }
  }

  static bool _differs(SyncDoc? before, SyncDoc after, String key) =>
      !DocFields.sameEntry(before?.data ?? const {}, after.data, key);

  /// Folders in the order they can be created: every parent before its children,
  /// siblings by their position.
  static List<SyncDoc> _foldersParentFirst(SyncSnapshot target) {
    final childrenOf = <String, List<SyncDoc>>{};
    for (final doc in target.docs.values) {
      if (doc.kind == SyncKind.folder) (childrenOf[doc.parentUid!] ??= []).add(doc);
    }
    final ordered = <SyncDoc>[];
    final queue = [target.root!.uid];
    for (var i = 0; i < queue.length; i++) {
      final children = [...?childrenOf[queue[i]]]..sort(_bySiblingOrder);
      for (final child in children) {
        ordered.add(child);
        queue.add(child.uid);
      }
    }
    return ordered;
  }

  static int _bySiblingOrder(SyncDoc a, SyncDoc b) {
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    final byName = a.name.compareTo(b.name);
    return byName != 0 ? byName : a.uid.compareTo(b.uid);
  }

  static Iterable<List<int>> _chunks(List<int> ids) sync* {
    for (var i = 0; i < ids.length; i += _idChunk) {
      yield ids.sublist(i, math.min(i + _idChunk, ids.length));
    }
  }
}

final class _Tally {
  int added = 0;
  int updated = 0;
  int deleted = 0;
  final changedRequestIds = <int>[];
  final deletedRequestIds = <int>[];
}

final class _Local {
  final int collectionId;
  final String uid;
  final List<Folder> folders;
  final Map<int, String> folderUids;
  final Map<int, String> requestUids;

  /// Every entity's doc, credentials included, by uid.
  final Map<String, SyncDoc> docs;

  _Local(this.collectionId, this.uid, this.folders, this.folderUids, this.requestUids, this.docs);

  late final Map<String, int> folderIds = {for (final e in folderUids.entries) e.value: e.key};
  late final Map<String, int> requestIds = {for (final e in requestUids.entries) e.value: e.key};
  late final Map<int, Folder> _folderById = {for (final f in folders) f.id: f};

  bool owns(SyncKind kind, int id) => switch (kind) {
        SyncKind.collection => id == collectionId,
        SyncKind.folder => folderUids.containsKey(id),
        SyncKind.request => requestUids.containsKey(id),
      };

  /// Number of folders above [folder].
  int depth(Folder folder) {
    var depth = 0;
    var parent = folder.parentFolderId;
    while (parent != null && depth <= folders.length) {
      depth++;
      parent = _folderById[parent]?.parentFolderId;
    }
    return depth;
  }
}
