import '../../../../core/usecases/usecase.dart';
import '../entities/git_sync_exceptions.dart';
import '../entities/git_sync_results.dart';
import '../repositories/git_host_client.dart';
import '../repositories/git_link_repository.dart';
import '../services/sync_engine.dart';

final class GitCommitPushParams {
  final int collectionId;
  final String message;
  const GitCommitPushParams({required this.collectionId, required this.message});
}

/// Writes every local change as ONE commit on the linked branch and advances the base. Throws GitNothingToCommitException, GitReadOnlyException, or GitNotFastForwardException when the remote moved (the caller must pull first).
final class GitCommitPushUseCase implements UseCase<PushResult, GitCommitPushParams> {
  final GitLinkRepository _links;
  final GitHostClient _host;
  final SyncEngine _engine;
  const GitCommitPushUseCase(this._links, this._host, this._engine);

  @override
  Future<PushResult> call(GitCommitPushParams params) async {
    final link = await _links.requireLink(params.collectionId);
    final info = await _host.getRepo(link.repo);
    if (!info.canPush) throw const GitReadOnlyException();

    final base = await _links.readBase(link.id);
    final local = await _engine.readLocal(link);
    final changes = _engine.diff(_engine.baseSnapshot(base), local);
    final writes = _engine.pushChanges(local, base, link.basePath);
    if (changes.isEmpty || writes.isEmpty) throw const GitNothingToCommitException();

    final head = await _host.getBranchHead(link.repo, link.branch);
    if (head != link.lastSyncedSha) throw const GitNotFastForwardException('The remote branch changed - pull first');

    final message = params.message.trim();
    final sha = await _host.commit(
      link.repo,
      branch: link.branch,
      parentSha: head ?? '',
      message: message.isEmpty ? 'Update ${changes.length} item(s) from PostPilot' : message,
      changes: writes,
    );

    await _links.writeBase(link.id, _engine.toBaseEntries(local, link.basePath));
    await _links.save(link.copyWith(lastSyncedSha: sha, lastSyncedAt: DateTime.now()));
    return PushResult(commitSha: sha, commitUrl: link.repo.commitUrl(sha), changedFiles: changes.length);
  }
}
