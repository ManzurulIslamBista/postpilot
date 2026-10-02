import '../../../../core/usecases/usecase.dart';
import '../entities/git_link.dart';
import '../entities/git_sync_exceptions.dart';
import '../repositories/git_host_client.dart';
import '../repositories/git_link_repository.dart';
import '../services/sync_engine.dart';

final class GitBranchParams {
  final int collectionId;
  final String branch;
  const GitBranchParams({required this.collectionId, required this.branch});
}

/// Creates the branch from the current synced commit and switches the link to it. Local changes stay local (they are then ahead of the new branch).
final class GitCreateBranchUseCase implements UseCase<GitLink, GitBranchParams> {
  final GitLinkRepository _links;
  final GitHostClient _host;
  const GitCreateBranchUseCase(this._links, this._host);

  @override
  Future<GitLink> call(GitBranchParams params) async {
    final link = await _links.requireLink(params.collectionId);
    final name = params.branch.trim();
    if (!_isValidBranchName(name)) throw GitSyncException('"$name" is not a valid branch name.');
    if (await _host.getBranchHead(link.repo, name) != null) throw GitSyncException('The branch "$name" already exists.');

    // The branch starts from what this collection last shared. Starting from the live head of a
    // collection that never synced would pair the remote's files with an empty base, and the next
    // push would overwrite them.
    final fromSha = link.lastSyncedSha;
    if (fromSha == null) {
      if (await _host.getBranchHead(link.repo, link.branch) == null) throw GitBranchMissingException(link.branch);
      throw const GitSyncException(
          'Nothing has been pulled or pushed for this collection yet - pull first, then create the branch.');
    }
    await _host.createBranch(link.repo, name, fromSha: fromSha);
    return _links.save(link.copyWith(branch: name, lastSyncedSha: fromSha));
  }
}

bool _isValidBranchName(String name) =>
    RegExp(r'^[A-Za-z0-9._/-]+$').hasMatch(name) &&
    !name.contains('..') &&
    !name.contains('//') &&
    !name.contains('/.') &&
    !name.startsWith('/') &&
    !name.startsWith('-') &&
    !name.startsWith('.') &&
    !name.endsWith('/') &&
    !name.endsWith('.') &&
    !name.endsWith('.lock');
