import '../../../../core/usecases/usecase.dart';
import '../entities/git_sync_results.dart';
import '../repositories/git_host_client.dart';
import '../repositories/git_link_repository.dart';
import '../services/sync_engine.dart';

final class GitHistoryParams {
  final int collectionId;
  final int limit;
  const GitHistoryParams({required this.collectionId, this.limit = 30});
}

/// Commits on the linked branch that touched the collection's folder, newest first.
final class GitHistoryUseCase implements UseCase<List<GitCommitInfo>, GitHistoryParams> {
  final GitLinkRepository _links;
  final GitHostClient _host;
  const GitHistoryUseCase(this._links, this._host);

  @override
  Future<List<GitCommitInfo>> call(GitHistoryParams params) async {
    final link = await _links.requireLink(params.collectionId);
    return _host.listCommits(link.repo, branch: link.branch, pathPrefix: link.basePath, limit: params.limit);
  }
}
