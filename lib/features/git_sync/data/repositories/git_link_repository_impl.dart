import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/git_links_dao.dart';
import '../../domain/entities/git_link.dart';
import '../../domain/entities/sync_doc.dart';
import '../../domain/repositories/git_link_repository.dart';

final class GitLinkRepositoryImpl implements GitLinkRepository {
  final GitLinksDao _dao;
  const GitLinkRepositoryImpl(this._dao);

  @override
  Future<GitLink?> findByCollection(int collectionId) async {
    final row = await _dao.findByCollection(collectionId);
    return row == null ? null : _toLink(row);
  }

  @override
  Stream<GitLink?> watchByCollection(int collectionId) =>
      _dao.watchByCollection(collectionId).map((row) => row == null ? null : _toLink(row));

  @override
  Stream<Set<int>> watchLinkedCollectionIds() => _dao
      .watchAll()
      .map((rows) => {for (final r in rows) r.collectionId})
      .distinct((a, b) => a.length == b.length && a.containsAll(b));

  @override
  Future<GitLink> save(GitLink link) async {
    final companion = _toCompanion(link);
    final int id;
    if (link.id == 0) {
      id = await _dao.insertLink(companion);
    } else {
      id = link.id;
      if (await _dao.updateLink(id, companion) == 0) throw StateError('Git link $id no longer exists');
    }
    return _toLink((await _dao.findById(id))!);
  }

  @override
  Future<void> remove(int collectionId) => _dao.deleteByCollection(collectionId);

  @override
  Future<Map<String, BaseEntry>> readBase(int linkId) async {
    final rows = await _dao.baseEntries(linkId);
    return {
      for (final r in rows)
        r.uid: BaseEntry(
          doc: SyncDoc.fromJson(jsonDecode(r.docJson) as Map<String, dynamic>),
          path: r.path,
          blobSha: r.blobSha,
        ),
    };
  }

  @override
  Future<void> writeBase(int linkId, Map<String, BaseEntry> entries) => _dao.replaceBase(linkId, [
        for (final e in entries.entries)
          GitBaseEntriesCompanion.insert(
            linkId: linkId,
            uid: e.key,
            path: e.value.path,
            blobSha: e.value.blobSha,
            docJson: jsonEncode(e.value.doc.toJson()),
          ),
      ]);

  static GitLink _toLink(GitLinkRow row) => GitLink(
        id: row.id,
        collectionId: row.collectionId,
        repo: RepoRef(provider: GitProvider.values.byName(row.provider), owner: row.owner, repo: row.repo),
        branch: row.branch,
        basePath: row.basePath,
        lastSyncedSha: row.lastSyncedSha,
        lastSyncedAt: row.lastSyncedAt,
        includeSecrets: row.includeSecrets,
      );

  static GitLinksCompanion _toCompanion(GitLink link) => GitLinksCompanion(
        collectionId: Value(link.collectionId),
        provider: Value(link.repo.provider.name),
        owner: Value(link.repo.owner),
        repo: Value(link.repo.repo),
        branch: Value(link.branch),
        basePath: Value(link.basePath),
        lastSyncedSha: Value(link.lastSyncedSha),
        lastSyncedAt: Value(link.lastSyncedAt),
        includeSecrets: Value(link.includeSecrets),
      );
}
