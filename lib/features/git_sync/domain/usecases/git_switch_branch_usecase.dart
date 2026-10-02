import '../../../../core/usecases/usecase.dart';
import '../entities/git_sync_exceptions.dart';
import '../repositories/git_host_client.dart';
import '../repositories/git_link_repository.dart';
import '../repositories/local_collection_store.dart';
import '../services/repo_layout.dart';
import '../services/sync_engine.dart';
import '../services/three_way_merger.dart';
import 'git_create_branch_usecase.dart' show GitBranchParams;

/// Switches the link to an existing branch and replaces the local collection with that branch's state. Throws GitUncommittedChangesException when there are unpushed local changes, GitBranchMissingException for an unknown branch.
final class GitSwitchBranchUseCase implements UseCase<ApplyOutcome, GitBranchParams> {
  final GitLinkRepository _links;
  final LocalCollectionStore _store;
  final GitHostClient _host;
  final SyncEngine _engine;
  const GitSwitchBranchUseCase(this._links, this._store, this._host, this._engine);

  @override
  Future<ApplyOutcome> call(GitBranchParams params) async {
    final link = await _links.requireLink(params.collectionId);
    final target = params.branch.trim();
    if (target == link.branch) return ApplyOutcome(collectionId: link.collectionId);

    final baseEntries = await _links.readBase(link.id);
    final local = await _engine.readLocal(link);
    if (_engine.diff(_engine.baseSnapshot(baseEntries), local).isNotEmpty) throw const GitUncommittedChangesException();

    final head = await _host.getBranchHead(link.repo, target);
    if (head == null) {
      await _host.getRepo(link.repo); // a repository that cannot be seen is not a missing branch
      throw GitBranchMissingException(target);
    }
    final fetched = await _engine.fetchRemoteSnapshot(link, commitSha: head, base: baseEntries);
    if (fetched.root == null) throw GitNothingToCloneException(RepoLayout.describe(link.basePath));
    final localRoot = local.root;
    final remote = localRoot == null ? fetched : ThreeWayMerger.alignRoot(fetched, localRoot.uid);

    await _engine.requireLocalUnchanged(link, local, operation: 'switching branches');
    final applied = await _store.applySnapshot(remote, collectionId: link.collectionId);
    await _links.writeBase(link.id, _engine.toBaseEntries(remote, link.basePath));
    await _links.save(link.copyWith(branch: target, lastSyncedSha: head, lastSyncedAt: DateTime.now()));
    return applied;
  }
}
