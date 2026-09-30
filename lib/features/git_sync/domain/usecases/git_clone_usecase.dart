import '../../../../core/usecases/usecase.dart';
import '../entities/git_link.dart';
import '../entities/git_sync_exceptions.dart';
import '../repositories/git_host_client.dart';
import '../repositories/git_link_repository.dart';
import '../repositories/local_collection_store.dart';
import '../services/repo_layout.dart';
import '../services/sync_engine.dart';

final class GitCloneParams {
  final RepoRef repo;
  final String branch;
  final String basePath;
  final bool includeSecrets;

  const GitCloneParams({
    required this.repo,
    required this.branch,
    this.basePath = '',
    this.includeSecrets = false,
  });
}

/// Creates a NEW local collection from the files under basePath and links it (base = what was cloned, lastSyncedSha = branch head). Throws GitNothingToCloneException when there is no collection there.
final class GitCloneUseCase implements UseCase<GitLink, GitCloneParams> {
  final GitHostClient _host;
  final LocalCollectionStore _store;
  final GitLinkRepository _links;
  final SyncEngine _engine;
  const GitCloneUseCase(this._host, this._store, this._links, this._engine);

  @override
  Future<GitLink> call(GitCloneParams params) async {
    final basePath = RepoLayout.normalizeBasePath(params.basePath);
    await _host.getRepo(params.repo);
    final head = await _host.getBranchHead(params.repo, params.branch);
    if (head == null) throw GitBranchMissingException(params.branch);

    final draft = GitLink(
      id: 0,
      collectionId: 0,
      repo: params.repo,
      branch: params.branch,
      basePath: basePath,
      includeSecrets: params.includeSecrets,
    );
    final remote = await _engine.fetchRemoteSnapshot(draft, commitSha: head, base: const {});
    if (remote.root == null) throw GitNothingToCloneException(RepoLayout.describe(basePath));

    final applied = await _store.applySnapshot(remote);
    final link = await _links.save(GitLink(
      id: 0,
      collectionId: applied.collectionId,
      repo: params.repo,
      branch: params.branch,
      basePath: basePath,
      lastSyncedSha: head,
      lastSyncedAt: DateTime.now(),
      includeSecrets: params.includeSecrets,
    ));
    await _links.writeBase(link.id, _engine.toBaseEntries(remote, basePath));
    return link;
  }
}
