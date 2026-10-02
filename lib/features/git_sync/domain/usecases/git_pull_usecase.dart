import '../../../../core/usecases/usecase.dart';
import '../entities/git_sync_exceptions.dart';
import '../entities/git_sync_results.dart';
import '../repositories/git_host_client.dart';
import '../repositories/git_link_repository.dart';
import '../repositories/local_collection_store.dart';
import '../services/repo_layout.dart';
import '../services/sync_engine.dart';
import '../services/three_way_merger.dart';

final class GitPullParams {
  final int collectionId;

  /// Decisions for conflicts found by an earlier call; null on the first call.
  final ConflictResolutions? resolutions;

  const GitPullParams({required this.collectionId, this.resolutions});
}

/// Fetches the remote branch, three-way merges it into the local collection (base = last synced state) and applies the result. Returns PullUpToDate, PullApplied, or PullConflicts when some entities need a decision - call again with resolutions (uid -> choice) to finish. Nothing is applied while conflicts are unresolved.
final class GitPullUseCase implements UseCase<PullResult, GitPullParams> {
  final GitLinkRepository _links;
  final LocalCollectionStore _store;
  final GitHostClient _host;
  final SyncEngine _engine;
  const GitPullUseCase(this._links, this._store, this._host, this._engine);

  @override
  Future<PullResult> call(GitPullParams params) async {
    final link = await _links.requireLink(params.collectionId);
    final head = await _host.getBranchHead(link.repo, link.branch);
    if (head == null) {
      // A repository the token cannot see answers like a missing branch; ask for the reason.
      await _host.getRepo(link.repo);
      throw GitBranchMissingException(link.branch);
    }
    if (head == link.lastSyncedSha) return const PullUpToDate();

    final baseEntries = await _links.readBase(link.id);
    // Read before any further network call, so an edit made while waiting is caught by requireLocalUnchanged.
    final local = await _engine.readLocal(link);
    if (await _engine.remoteUnchanged(link, commitSha: head, base: baseEntries)) {
      // The branch moved, but not in this collection's folder (an unrelated commit, a sibling
      // collection): nothing to merge, nothing to download. Only the link moves forward.
      await _engine.requireLocalUnchanged(link, local, operation: 'pulling');
      await _links.save(link.copyWith(lastSyncedSha: head, lastSyncedAt: DateTime.now()));
      return const PullApplied(added: 0, updated: 0, deleted: 0, changedRequestIds: [], deletedRequestIds: []);
    }
    final fetched = await _engine.fetchRemoteSnapshot(link, commitSha: head, base: baseEntries);
    // A remote without the collection would merge as "everything was deleted".
    if (fetched.root == null && baseEntries.isNotEmpty) {
      throw GitNothingToCloneException(RepoLayout.describe(link.basePath));
    }
    final localRoot = local.root;
    final remote = localRoot == null ? fetched : ThreeWayMerger.alignRoot(fetched, localRoot.uid);

    final outcome = ThreeWayMerger.merge(
      base: _engine.baseSnapshot(baseEntries),
      local: local,
      remote: remote,
      resolutions: params.resolutions,
    );
    if (outcome.conflicts.isNotEmpty) return PullConflicts(outcome.conflicts);

    await _engine.requireLocalUnchanged(link, local, operation: 'pulling');
    final applied = await _store.applySnapshot(outcome.merged, collectionId: link.collectionId);
    await _links.writeBase(link.id, _engine.toBaseEntries(remote, link.basePath));
    await _links.save(link.copyWith(lastSyncedSha: head, lastSyncedAt: DateTime.now()));
    return PullApplied(
      added: applied.added,
      updated: applied.updated,
      deleted: applied.deleted,
      changedRequestIds: applied.changedRequestIds,
      deletedRequestIds: applied.deletedRequestIds,
    );
  }
}
