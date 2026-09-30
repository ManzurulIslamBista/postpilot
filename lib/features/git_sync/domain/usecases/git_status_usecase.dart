import '../../../../core/usecases/usecase.dart';
import '../entities/git_sync_results.dart';
import '../repositories/git_host_client.dart';
import '../repositories/git_link_repository.dart';
import '../services/sync_engine.dart';

final class GitStatusParams {
  final int collectionId;

  /// Also ask the host for the branch head and the repository permissions
  /// (a network call); false compares local state to the stored base only.
  final bool checkRemote;

  const GitStatusParams({required this.collectionId, this.checkRemote = false});
}

/// Local changes since the last sync (entity-level, with changed field names) and, with checkRemote, whether the remote branch moved. Throws GitNotLinkedException.
final class GitStatusUseCase implements UseCase<GitStatus, GitStatusParams> {
  final GitLinkRepository _links;
  final GitHostClient _host;
  final SyncEngine _engine;
  const GitStatusUseCase(this._links, this._host, this._engine);

  @override
  Future<GitStatus> call(GitStatusParams params) async {
    final link = await _links.requireLink(params.collectionId);
    final base = await _links.readBase(link.id);
    final local = await _engine.readLocal(link);
    final changes = _engine.diff(_engine.baseSnapshot(base), local);
    if (!params.checkRemote) return GitStatus(link: link, localChanges: changes);

    final info = await _host.getRepo(link.repo);
    final head = await _host.getBranchHead(link.repo, link.branch);
    return GitStatus(
      link: link,
      localChanges: changes,
      repoInfo: info,
      remoteHeadSha: head,
      behind: head != link.lastSyncedSha,
    );
  }
}
