import '../../../../core/usecases/usecase.dart';
import '../entities/git_link.dart';
import '../entities/git_sync_exceptions.dart';
import '../repositories/git_host_client.dart';
import '../repositories/git_link_repository.dart';
import '../repositories/local_collection_store.dart';
import '../services/link_overlap_guard.dart';
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

/// Links an existing local collection to repo/branch/basePath. Verifies access, records the branch head as lastSyncedSha with an EMPTY base (every local doc then shows as added, ready for the first push). Throws GitPathOverlapException when another local collection already syncs an overlapping folder, GitPathOccupiedException when the remote folder holds a DIFFERENT collection and GitBranchMissingException when the branch is missing in a non-empty repository. An empty repository is allowed (lastSyncedSha stays null).
///
/// When the remote folder holds THIS collection (same root uid: it was linked before and then disconnected, or pushed from another device) it is adopted instead: lastSyncedSha stays null, so the first move is a pull that merges the two sides, and a push cannot overwrite the remote blindly.
final class GitConnectUseCase implements UseCase<GitLink, GitConnectParams> {
  final GitLinkRepository _links;
  final GitHostClient _host;

  /// Needed to recognise this collection's own files in the repository; without it an occupied folder is always refused.
  final LocalCollectionStore? _store;
  const GitConnectUseCase(this._links, this._host, [this._store]);

  @override
  Future<GitLink> call(GitConnectParams params) async {
    final basePath = RepoLayout.normalizeBasePath(params.basePath);
    final info = await _host.getRepo(params.repo);
    final branch = params.branch.trim().isEmpty ? info.defaultBranch : params.branch.trim();
    await LinkOverlapGuard.requireFree(
      _links,
      repo: params.repo,
      branch: branch,
      basePath: basePath,
      exceptCollectionId: params.collectionId,
    );

    var adopt = false;
    final head = await _host.getBranchHead(params.repo, branch);
    if (head == null) {
      if (!info.isEmpty) throw GitBranchMissingException(branch);
    } else {
      final tree = await _host.getTree(params.repo, head, pathPrefix: basePath);
      final remoteRoot = tree.blobShaByPath[RepoLayout.join(basePath, RepoLayout.collectionFile)];
      if (remoteRoot != null) {
        if (!await _isThisCollection(params, remoteRoot)) throw GitPathOccupiedException(RepoLayout.describe(basePath));
        adopt = true;
      }
    }

    final existing = await _links.findByCollection(params.collectionId);
    final link = await _links.save(GitLink(
      id: existing?.id ?? 0,
      collectionId: params.collectionId,
      repo: params.repo,
      branch: branch,
      basePath: basePath,
      // Adopting an existing remote copy: nothing is shared yet, so pull before any push.
      lastSyncedSha: adopt ? null : head,
      includeSecrets: params.includeSecrets,
    ));
    await _links.writeBase(link.id, const {});
    return link;
  }

  /// Whether the collection file at [remoteBlobSha] is the local collection's own (same root uid).
  Future<bool> _isThisCollection(GitConnectParams params, String remoteBlobSha) async {
    final store = _store;
    if (store == null) return false;
    final localRoot = (await store.readSnapshot(params.collectionId, includeSecrets: false)).root;
    if (localRoot == null) return false;
    final remoteRoot = RepoLayout.tryParseDoc(await _host.getBlobText(params.repo, remoteBlobSha));
    return remoteRoot != null && remoteRoot.uid == localRoot.uid;
  }
}
