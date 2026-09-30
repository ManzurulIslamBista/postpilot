import 'dart:convert';

import '../entities/git_sync_exceptions.dart';
import '../entities/sync_doc.dart';

/// What was found under a collection folder of a repository.
final class ParsedRepo {
  final SyncSnapshot snapshot;

  /// Full repository paths of collection files that could not be used
  /// (not valid doc JSON, wrong kind for the file name, duplicate uid).
  final List<String> skippedPaths;

  const ParsedRepo({required this.snapshot, this.skippedPaths = const []});
}

/// Maps a collection's docs to repository files and back.
///
/// `<base>/collection.json`, `<base>/<folder>/.../_folder.json` and
/// `<base>/<folder>/.../<request>.request.json`, where every name is a slug of
/// the entity's current name. A rename or move therefore changes a doc's path,
/// while merging keys on uid only.
abstract final class RepoLayout {
  static const collectionFile = 'collection.json';
  static const folderFile = '_folder.json';
  static const requestSuffix = '.request.json';

  /// Trims spaces and slashes, unifies separators and rejects `..` segments.
  /// '' means the repository root.
  static String normalizeBasePath(String input) {
    final parts = [
      for (final part in input.replaceAll('\\', '/').split('/'))
        if (part.trim().isNotEmpty && part.trim() != '.') part.trim(),
    ];
    if (parts.contains('..')) throw const GitSyncException('The repository folder must not contain "..".');
    return parts.join('/');
  }

  /// How a normalized base path reads in messages.
  static String describe(String basePath) => basePath.isEmpty ? '/' : basePath;

  static String join(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

  static String slug(String name) {
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'untitled' : slug;
  }

  /// Repository path of every doc, by uid.
  static Map<String, String> pathsByUid(SyncSnapshot snapshot, {required String basePath}) {
    final base = normalizeBasePath(basePath);
    final tree = repairParents(snapshot);
    final rootUid = tree.root?.uid;
    final childrenOf = <String?, List<SyncDoc>>{};
    for (final doc in tree.docs.values) {
      if (doc.kind == SyncKind.collection) continue;
      final parent = doc.parentUid;
      final key = parent != null && tree.docs.containsKey(parent) ? parent : rootUid;
      (childrenOf[key] ??= []).add(doc);
    }

    final paths = <String, String>{};
    if (rootUid != null) paths[rootUid] = join(base, collectionFile);

    void place(String? parentUid, String dir) {
      final children = childrenOf[parentUid];
      if (children == null) return;
      children.sort(_bySiblingOrder);
      final foldersTaken = <String>{};
      final requestsTaken = <String>{};
      for (final child in children) {
        if (child.kind == SyncKind.folder) {
          final folderDir = join(dir, _uniqueSlug(child, foldersTaken));
          paths[child.uid] = join(folderDir, folderFile);
          place(child.uid, folderDir);
        } else {
          paths[child.uid] = join(dir, '${_uniqueSlug(child, requestsTaken)}$requestSuffix');
        }
      }
    }

    place(rootUid, base);
    return paths;
  }

  /// Repository path -> file text for every doc; byte-stable for equal input.
  static Map<String, String> toFiles(SyncSnapshot snapshot, {required String basePath}) {
    final tree = repairParents(snapshot);
    final paths = pathsByUid(tree, basePath: basePath);
    return {
      for (final entry in paths.entries) entry.value: tree.docs[entry.key]!.canonicalText,
    };
  }

  /// The subset of [repoPaths] that are collection files of the collection at
  /// [basePath], sorted. Folders holding their own `collection.json` belong to
  /// another collection and are left out.
  static List<String> relevantPaths(Iterable<String> repoPaths, {required String basePath}) {
    final base = normalizeBasePath(basePath);
    final prefix = base.isEmpty ? '' : '$base/';
    final relative = <String, String>{
      for (final path in repoPaths)
        if (path.startsWith(prefix)) path.substring(prefix.length): path,
    };
    final otherRoots = [
      for (final rel in relative.keys)
        if (rel.endsWith('/$collectionFile')) rel.substring(0, rel.length - collectionFile.length),
    ];
    return [
      for (final entry in relative.entries)
        if (_isDocFile(entry.key) && !otherRoots.any((root) => entry.key.startsWith(root))) entry.value,
    ]..sort();
  }

  /// The doc a file holds, or null when it is not valid doc JSON.
  static SyncDoc? tryParseDoc(String text) {
    try {
      final json = jsonDecode(text.startsWith('﻿') ? text.substring(1) : text);
      if (json is! Map<String, dynamic>) return null;
      final doc = SyncDoc.fromJson(json);
      return doc.uid.isEmpty ? null : doc;
    } catch (_) {
      return null;
    }
  }

  /// Reads [files] (full repository path -> text) into a snapshot. Files
  /// outside [basePath] and non-collection files are ignored; no
  /// `collection.json` gives an empty snapshot.
  static ParsedRepo fromFiles(Map<String, String> files, {required String basePath}) {
    final base = normalizeBasePath(basePath);
    final cut = base.isEmpty ? 0 : base.length + 1;
    final skipped = <String>[];
    final parsed = <({String rel, SyncDoc doc})>[];
    final seenUids = <String>{};
    for (final path in relevantPaths(files.keys, basePath: base)) {
      final rel = path.substring(cut);
      final doc = tryParseDoc(files[path]!);
      if (doc == null || doc.kind != _kindOf(rel) || !seenUids.add(doc.uid)) {
        skipped.add(path);
        continue;
      }
      parsed.add((rel: rel, doc: doc));
    }

    final root = parsed.where((p) => p.doc.kind == SyncKind.collection).firstOrNull?.doc;
    if (root == null) return ParsedRepo(snapshot: SyncSnapshot.empty, skippedPaths: skipped);

    final folderUidByDir = {
      for (final p in parsed)
        if (p.doc.kind == SyncKind.folder) _dirOf(p.rel): p.doc.uid,
    };
    final containerUids = {
      for (final p in parsed)
        if (p.doc.kind != SyncKind.request) p.doc.uid,
    };
    String nearestFolder(String dir) {
      for (var d = dir; d.isNotEmpty; d = _dirOf(d)) {
        final uid = folderUidByDir[d];
        if (uid != null) return uid;
      }
      return root.uid;
    }

    final docs = <String, SyncDoc>{};
    for (final p in parsed) {
      final doc = p.doc;
      if (doc.kind == SyncKind.collection) {
        docs[doc.uid] = _withParent(doc, null);
        continue;
      }
      final declared = doc.parentUid;
      final declaredUsable = declared != null && declared != doc.uid && containerUids.contains(declared);
      final home = doc.kind == SyncKind.folder ? _dirOf(_dirOf(p.rel)) : _dirOf(p.rel);
      final parent = declaredUsable ? declared : nearestFolder(home);
      docs[doc.uid] = parent == doc.parentUid ? doc : _withParent(doc, parent);
    }
    return ParsedRepo(snapshot: repairParents(SyncSnapshot(docs)), skippedPaths: skipped);
  }

  /// Re-parents every doc whose parent is missing, is not a folder or the
  /// collection, or whose parent chain never reaches the collection (a cycle)
  /// to the collection root, so no doc is ever dangling or dropped.
  static SyncSnapshot repairParents(SyncSnapshot snapshot) {
    final rootUid = snapshot.root?.uid;
    if (rootUid == null) return snapshot;
    final docs = {...snapshot.docs};

    bool reachesRoot(SyncDoc start) {
      final seen = <String>{};
      var current = start;
      while (current.uid != rootUid) {
        if (!seen.add(current.uid)) return false;
        final parent = current.parentUid == null ? null : docs[current.parentUid!];
        if (parent == null || parent.kind == SyncKind.request) return false;
        current = parent;
      }
      return true;
    }

    for (final uid in docs.keys.toList()..sort()) {
      final doc = docs[uid]!;
      if (uid != rootUid && !reachesRoot(doc)) docs[uid] = _withParent(doc, rootUid);
    }
    return SyncSnapshot(docs);
  }

  static bool _isDocFile(String rel) =>
      rel == collectionFile || rel.endsWith('/$folderFile') || rel.endsWith(requestSuffix);

  static SyncKind _kindOf(String rel) => rel == collectionFile
      ? SyncKind.collection
      : rel.endsWith('/$folderFile')
          ? SyncKind.folder
          : SyncKind.request;

  static String _dirOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  static SyncDoc _withParent(SyncDoc doc, String? parentUid) => SyncDoc(
        uid: doc.uid,
        kind: doc.kind,
        parentUid: parentUid,
        name: doc.name,
        order: doc.order,
        data: doc.data,
      );

  static int _bySiblingOrder(SyncDoc a, SyncDoc b) {
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    final byName = a.name.compareTo(b.name);
    return byName != 0 ? byName : a.uid.compareTo(b.uid);
  }

  static String _uniqueSlug(SyncDoc doc, Set<String> taken) {
    var slug = RepoLayout.slug(doc.name);
    if (taken.contains(slug)) {
      final tagged = '$slug-${_uidTag(doc.uid)}';
      slug = tagged;
      for (var n = 2; taken.contains(slug); n++) {
        slug = '$tagged-$n';
      }
    }
    taken.add(slug);
    return slug;
  }

  static String _uidTag(String uid) {
    final head = uid.length > 8 ? uid.substring(0, 8) : uid;
    return head.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '-');
  }
}
