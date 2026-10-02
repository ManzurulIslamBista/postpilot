import '../repositories/git_host_client.dart';

// Re-exported so callers catch every sync failure with one import.
export '../repositories/git_host_client.dart'
    show
        GitHostException,
        GitAuthException,
        GitMissingTokenException,
        GitNotFoundException,
        GitNotFastForwardException,
        GitRateLimitException;

/// Sync-level failures (as opposed to host/transport failures, which are
/// [GitHostException]s). Messages are user-readable.
class GitSyncException implements Exception {
  final String message;
  const GitSyncException(this.message);

  @override
  String toString() => message;
}

final class GitNotLinkedException extends GitSyncException {
  const GitNotLinkedException() : super('This collection is not connected to a Git repository.');
}

/// Commit with nothing changed since the last sync.
final class GitNothingToCommitException extends GitSyncException {
  const GitNothingToCommitException() : super('Nothing to commit - no local changes.');
}

/// The token has no push access to the repository.
final class GitReadOnlyException extends GitSyncException {
  const GitReadOnlyException() : super('You only have read access to this repository, so you cannot push.');
}

/// The chosen repository folder already holds a collection.
final class GitPathOccupiedException extends GitSyncException {
  const GitPathOccupiedException(String path)
      : super('The repository folder "$path" already contains a collection. Clone it instead, or pick another folder.');
}

/// Another collection on this device already syncs that folder (or one above or inside it) of the
/// same repository and branch. Two links would write and delete each other's files.
final class GitPathOverlapException extends GitSyncException {
  const GitPathOverlapException(String path, String other)
      : super('The repository folder "$path" overlaps "$other", which another collection on this device already syncs. '
            'Give each collection its own folder.');
}

/// Switching or pulling would overwrite local edits that were not pushed.
final class GitUncommittedChangesException extends GitSyncException {
  const GitUncommittedChangesException() : super('You have local changes that are not pushed yet. Push or discard them first.');
}

final class GitBranchMissingException extends GitSyncException {
  const GitBranchMissingException(String branch) : super('The branch "$branch" does not exist in this repository.');
}

/// The repository folder holds no PostPilot collection files.
final class GitNothingToCloneException extends GitSyncException {
  const GitNothingToCloneException(String path) : super('No PostPilot collection found in "$path".');
}
