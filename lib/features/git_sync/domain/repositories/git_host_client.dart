import '../entities/git_link.dart';
import '../entities/git_sync_results.dart';

/// Talks to one Git host (GitHub today) through its HTTP API — no local `git`
/// binary and no file system, so it works on web and mobile as well as
/// desktop. The access token comes from `GitCredentialsStore`; implementations
/// throw [GitAuthException] when it is missing or rejected.
abstract interface class GitHostClient {
  /// Login name of the account the saved token belongs to. Throws
  /// [GitAuthException] without a valid token.
  Future<String> getAuthenticatedLogin();

  /// Throws [GitNotFoundException] if the repository does not exist or the
  /// token cannot see it. Public repositories can be read without a token.
  Future<GitRepoInfo> getRepo(RepoRef repo);

  /// Creates a repository initialised with a README so it has a first commit.
  Future<RepoRef> createRepo({required GitProvider provider, required String name, required bool private, String? description});

  Future<List<String>> listBranches(RepoRef repo);

  /// Head commit sha of [branch]; null when the branch does not exist.
  Future<String?> getBranchHead(RepoRef repo, String branch);

  Future<void> createBranch(RepoRef repo, String branch, {required String fromSha});

  /// Files (not directories) at [commitSha] whose path starts with
  /// [pathPrefix]. An empty prefix lists the whole repository.
  Future<RemoteTree> getTree(RepoRef repo, String commitSha, {String pathPrefix = ''});

  /// UTF-8 text of a blob.
  Future<String> getBlobText(RepoRef repo, String blobSha);

  /// Creates one commit on top of [parentSha] that writes every entry of
  /// [changes] (path -> new text; null = delete the file) and moves [branch]
  /// to it, without forcing. Returns the new commit sha.
  ///
  /// Throws [GitNotFastForwardException] if [branch] no longer points at
  /// [parentSha]. An empty [parentSha] means the repository has no commits
  /// yet: the implementation must create the initial commit and the branch.
  Future<String> commit(
    RepoRef repo, {
    required String branch,
    required String parentSha,
    required String message,
    required Map<String, String?> changes,
  });

  /// Newest first. [pathPrefix] limits to commits touching that folder.
  Future<List<GitCommitInfo>> listCommits(RepoRef repo, {required String branch, String pathPrefix = '', int limit = 30});

  Future<List<GitContributor>> listContributors(RepoRef repo);
}

class GitHostException implements Exception {
  final String message;
  const GitHostException(this.message);

  @override
  String toString() => message;
}

/// No token saved, or the host rejected it (revoked, expired, wrong scopes).
final class GitAuthException extends GitHostException {
  const GitAuthException(super.message);
}

/// No token is saved at all, as opposed to one the host rejected: the fix is to save one, not to replace it.
final class GitMissingTokenException extends GitAuthException {
  const GitMissingTokenException() : super('No GitHub token saved');
}

final class GitNotFoundException extends GitHostException {
  const GitNotFoundException(super.message);
}

/// The branch moved since the caller last looked; pull, then push again.
final class GitNotFastForwardException extends GitHostException {
  const GitNotFastForwardException(super.message);
}

final class GitRateLimitException extends GitHostException {
  const GitRateLimitException(super.message);
}
