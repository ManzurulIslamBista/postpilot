import 'package:postpilot/features/git_sync/domain/entities/git_link.dart';
import 'package:postpilot/features/git_sync/domain/repositories/git_link_repository.dart';

class FakeLinkRepository implements GitLinkRepository {
  final links = <int, GitLink>{};
  final bases = <int, Map<String, BaseEntry>>{};
  var _nextId = 1;

  @override
  Future<GitLink?> findByCollection(int collectionId) async =>
      links.values.where((link) => link.collectionId == collectionId).firstOrNull;

  @override
  Stream<GitLink?> watchByCollection(int collectionId) => Stream.fromFuture(findByCollection(collectionId));

  @override
  Stream<Set<int>> watchLinkedCollectionIds() => Stream.value({for (final link in links.values) link.collectionId});

  @override
  Future<GitLink> save(GitLink link) async {
    for (final other in links.values.where((l) => l.collectionId == link.collectionId && l.id != link.id).toList()) {
      links.remove(other.id);
      bases.remove(other.id);
    }
    final saved = link.id != 0
        ? link
        : GitLink(
            id: _nextId++,
            collectionId: link.collectionId,
            repo: link.repo,
            branch: link.branch,
            basePath: link.basePath,
            lastSyncedSha: link.lastSyncedSha,
            lastSyncedAt: link.lastSyncedAt,
            includeSecrets: link.includeSecrets,
          );
    links[saved.id] = saved;
    return saved;
  }

  @override
  Future<void> remove(int collectionId) async {
    final ids = links.values.where((link) => link.collectionId == collectionId).map((link) => link.id).toList();
    for (final id in ids) {
      links.remove(id);
      bases.remove(id);
    }
  }

  @override
  Future<Map<String, BaseEntry>> readBase(int linkId) async => Map.of(bases[linkId] ?? const {});

  @override
  Future<void> writeBase(int linkId, Map<String, BaseEntry> entries) async => bases[linkId] = Map.of(entries);
}
