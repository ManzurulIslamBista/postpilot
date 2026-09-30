import '../../../../core/usecases/usecase.dart';
import '../entities/git_link.dart';
import '../entities/git_sync_exceptions.dart';
import '../repositories/git_host_client.dart';
import '../repositories/git_link_repository.dart';
import '../services/repo_layout.dart';

final class GitConnectParams {
  final int collectionId;
  final RepoRef repo;
  final String branch;
  final String basePath;
  final bool includeSecrets;

  const GitConnectParams({
    required this.collectionId,
    required this.repo,
    required this.branch,
    this.basePath = '',
    this.includeSecrets = false,
  });
}

/// Links an existing local collection to repo/branch/basePath. Verifies access, records the branch head as lastSyncedSha with an EMPTY base (every local doc then shows as added, ready for the first push). Throws GitPathOccupiedException when the remote folder already holds a collection and GitBranchMissingException when the branch is missing in a non-empty repository. An empty repository is allowed (lastSyncedSha stays null).
final class GitConnectUseCase implements UseCase<GitLink, GitConnectParams> {
  final GitLinkRepository _links;
  final GitHostClient _host;
  const GitConnectUseCase(this._links, this._host);

  @override
  Future<GitLink> call(GitConnectParams params) async {
    final basePath = RepoLayout.normalizeBasePath(params.basePath);
    final info = await _host.getRepo(params.repo);
    final branch = params.branch.trim().isEmpty ? info.defaultBranch : params.branch.trim();

    final head = await _host.getBranchHead(params.repo, branch);
    if (head == null) {
      if (!info.isEmpty) throw GitBranchMissingException(branch);
    } else {
      final tree = await _host.getTree(params.repo, head, pathPrefix: basePath);
      if (tree.blobShaByPath.containsKey(RepoLayout.join(basePath, RepoLayout.collectionFile))) {
        throw GitPathOccupiedException(RepoLayout.describe(basePath));
      }
    }

    final existing = await _links.findByCollection(params.collectionId);
    final link = await _links.save(GitLink(
      id: existing?.id ?? 0,
      collectionId: params.collectionId,
      repo: params.repo,
      branch: branch,
      basePath: basePath,
      lastSyncedSha: head,
      includeSecrets: params.includeSecrets,
    ));
    await _links.writeBase(link.id, const {});
    return link;
  }
}
