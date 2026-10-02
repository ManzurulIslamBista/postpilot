import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/git_links_table.dart';

part 'git_links_dao.g.dart';

@DriftAccessor(tables: [GitLinks, GitBaseEntries])
class GitLinksDao extends DatabaseAccessor<AppDatabase> with _$GitLinksDaoMixin {
  GitLinksDao(super.db);

  Future<GitLinkRow?> findById(int id) => (select(gitLinks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<GitLinkRow?> findByCollection(int collectionId) =>
      (select(gitLinks)..where((t) => t.collectionId.equals(collectionId))).getSingleOrNull();

  Stream<GitLinkRow?> watchByCollection(int collectionId) =>
      (select(gitLinks)..where((t) => t.collectionId.equals(collectionId))).watchSingleOrNull();

  Stream<List<GitLinkRow>> watchAll() => select(gitLinks).watch();

  Future<List<GitLinkRow>> findAll() => select(gitLinks).get();

  Future<int> insertLink(GitLinksCompanion link) => into(gitLinks).insert(link);

  /// Returns the number of rows changed (0 when [id] no longer exists).
  Future<int> updateLink(int id, GitLinksCompanion link) =>
      (update(gitLinks)..where((t) => t.id.equals(id))).write(link);

  Future<void> deleteByCollection(int collectionId) =>
      (delete(gitLinks)..where((t) => t.collectionId.equals(collectionId))).go();

  Future<List<GitBaseEntry>> baseEntries(int linkId) =>
      (select(gitBaseEntries)..where((t) => t.linkId.equals(linkId))).get();

  Future<void> replaceBase(int linkId, List<GitBaseEntriesCompanion> rows) => transaction(() async {
        await (delete(gitBaseEntries)..where((t) => t.linkId.equals(linkId))).go();
        if (rows.isEmpty) return;
        await batch((b) => b.insertAll(gitBaseEntries, [for (final r in rows) r.copyWith(linkId: Value(linkId))]));
      });
}
