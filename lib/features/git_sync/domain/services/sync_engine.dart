import 'dart:math' as math;

import '../entities/git_link.dart';
import '../entities/git_sync_exceptions.dart';
import '../entities/git_sync_results.dart';
import '../entities/sync_doc.dart';
import '../repositories/git_host_client.dart';
import '../repositories/git_link_repository.dart';
import '../repositories/local_collection_store.dart';
import 'doc_fields.dart';
import 'git_hash.dart';
import 'repo_layout.dart';
import 'secret_fields.dart';

/// Building blocks shared by the sync use cases.
final class SyncEngine {
  static const _downloadConcurrency = 8;

  final GitHostClient _host;
  final LocalCollectionStore _store;

  const SyncEngine(this._host, this._store);

  /// The local collection as [link] syncs it: without credentials unless the
  /// link includes secrets.
  Future<SyncSnapshot> readLocal(GitLink link) async => SecretFields.applyPolicy(
        await _store.readSnapshot(link.collectionId, includeSecrets: link.includeSecrets),
        includeSecrets: link.includeSecrets,
      );

  /// Throws unless [link]'s local collection still is [used], the snapshot a
  /// pull or branch switch built its result from. Those read the collection,
  /// wait on the network, then make the collection equal to what they
  /// computed, so anything created, edited or deleted while they waited would
  /// be undone. Call it right before applying: it throws before anything is
  /// touched, and [operation] ("pulling") names what was going on.
  Future<void> requireLocalUnchanged(GitLink link, SyncSnapshot used, {required String operation}) async {
    final now = await readLocal(link);
    final unchanged = now.docs.length == used.docs.length && used.docs.entries.every((e) => now.docs[e.key] == e.value);
    if (!unchanged) {
      throw GitSyncException('Your collection changed while $operation. Nothing was applied — try again.');
    }
  }

  /// The collection at [commitSha] as [link] syncs it. Only files whose blob
  /// sha differs from the [base] entry at the same path are downloaded. A
  /// changed file that is no longer valid JSON (a merge-conflict marker, say)
  /// counts as unchanged, so it never looks like a deletion.
  Future<SyncSnapshot> fetchRemoteSnapshot(
    GitLink link, {
    required String commitSha,
    required Map<String, BaseEntry> base,
  }) async {
    final tree = await _host.getTree(link.repo, commitSha, pathPrefix: link.basePath);
    final baseByPath = {for (final entry in base.values) entry.path: entry};
    final files = <String, String>{};
    final toDownload = <String, String>{};
    for (final path in RepoLayout.relevantPaths(tree.blobShaByPath.keys, basePath: link.basePath)) {
      final sha = tree.blobShaByPath[path]!;
      final known = baseByPath[path];
      if (known != null && known.blobSha == sha) {
        files[path] = known.doc.canonicalText;
      } else {
        toDownload[path] = sha;
      }
    }

    files.addAll(await downloadTexts(link.repo, toDownload));
    for (final path in toDownload.keys) {
      final known = baseByPath[path];
      if (known != null && RepoLayout.tryParseDoc(files[path]!) == null) files[path] = known.doc.canonicalText;
    }

    final parsed = RepoLayout.fromFiles(files, basePath: link.basePath);
    return SecretFields.applyPolicy(parsed.snapshot, includeSecrets: link.includeSecrets);
  }

  /// Whether the files of [link]'s collection at [commitSha] are exactly the ones
  /// [base] describes: the branch may have moved, but only elsewhere (another
  /// collection of the same repository, a README), so this collection has nothing
  /// to pull and nothing that stops it from pushing on top.
  Future<bool> remoteUnchanged(
    GitLink link, {
    required String commitSha,
    required Map<String, BaseEntry> base,
  }) async {
    if (base.isEmpty) return false; // nothing shared yet: compare nothing, assume it moved
    final tree = await _host.getTree(link.repo, commitSha, pathPrefix: link.basePath);
    final relevant = RepoLayout.relevantPaths(tree.blobShaByPath.keys, basePath: link.basePath);
    final baseShaByPath = {for (final entry in base.values) entry.path: entry.blobSha};
    return relevant.length == baseShaByPath.length && relevant.every((path) => baseShaByPath[path] == tree.blobShaByPath[path]);
  }

  /// Blob texts by repository path, with at most 8 downloads in flight.
  Future<Map<String, String>> downloadTexts(RepoRef repo, Map<String, String> blobShaByPath) async {
    final queue = blobShaByPath.entries.toList();
    final texts = <String, String>{};
    var next = 0;
    var failed = false;
    Future<void> worker() async {
      while (!failed && next < queue.length) {
        final entry = queue[next++];
        try {
          texts[entry.key] = await _host.getBlobText(repo, entry.value);
        } catch (_) {
          failed = true;
          rethrow;
        }
      }
    }

    await Future.wait([for (var i = 0; i < math.min(_downloadConcurrency, queue.length); i++) worker()]);
    return texts;
  }

  /// Entities of [local] that differ from [base]: collection first, then
  /// folders, then requests, alphabetical inside each.
  List<DocChange> diff(SyncSnapshot base, SyncSnapshot local) {
    final changes = <DocChange>[];
    for (final doc in local.docs.values) {
      final before = base.docs[doc.uid];
      if (before == null) {
        changes.add(_change(doc, DocChangeType.added));
      } else if (before != doc) {
        changes.add(_change(doc, DocChangeType.modified, changedFields: _changedFields(before, doc)));
      }
    }
    for (final doc in base.docs.values) {
      if (!local.docs.containsKey(doc.uid)) changes.add(_change(doc, DocChangeType.deleted));
    }
    return changes..sort((a, b) => DocFields.compareEntries(a.kind, a.name, a.uid, b.kind, b.name, b.uid));
  }

  /// Base entries for [snapshot] exactly as a push writes them: the path the
  /// layout gives each doc and the blob sha of its canonical text.
  Map<String, BaseEntry> toBaseEntries(SyncSnapshot snapshot, String basePath) {
    final tree = RepoLayout.repairParents(snapshot);
    final paths = RepoLayout.pathsByUid(tree, basePath: basePath);
    return {
      for (final doc in tree.docs.values)
        if (paths.containsKey(doc.uid))
          doc.uid: BaseEntry(doc: doc, path: paths[doc.uid]!, blobSha: GitHash.blobSha(doc.canonicalText)),
    };
  }

  SyncSnapshot baseSnapshot(Map<String, BaseEntry> base) =>
      SyncSnapshot({for (final entry in base.entries) entry.key: entry.value.doc});

  /// Repository writes (path -> new text, null = delete) that turn the files
  /// the [base] describes into [local]. Compared per file, so a renamed folder
  /// also moves the files of its unchanged children.
  Map<String, String?> pushChanges(SyncSnapshot local, Map<String, BaseEntry> base, String basePath) {
    final files = RepoLayout.toFiles(local, basePath: basePath);
    final baseShaByPath = {for (final entry in base.values) entry.path: entry.blobSha};
    return {
      for (final file in files.entries)
        if (baseShaByPath[file.key] != GitHash.blobSha(file.value)) file.key: file.value,
      for (final path in baseShaByPath.keys)
        if (!files.containsKey(path)) path: null,
    };
  }

  static DocChange _change(SyncDoc doc, DocChangeType type, {List<String> changedFields = const []}) => DocChange(
        uid: doc.uid,
        kind: doc.kind,
        name: doc.name,
        type: type,
        changedFields: changedFields,
      );

  static List<String> _changedFields(SyncDoc before, SyncDoc after) {
    final beforeFields = before.fields;
    final afterFields = after.fields;
    return DocFields.ordered([
      for (final key in {...beforeFields.keys, ...afterFields.keys})
        if (!DocFields.sameEntry(beforeFields, afterFields, key)) key,
      if (before.kind != after.kind) 'kind',
    ]);
  }
}

extension RequireLink on GitLinkRepository {
  Future<GitLink> requireLink(int collectionId) async =>
      await findByCollection(collectionId) ?? (throw const GitNotLinkedException());
}
