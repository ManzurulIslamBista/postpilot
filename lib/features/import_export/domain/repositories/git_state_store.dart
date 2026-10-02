import '../services/backup_codec.dart';

/// The Git side of one collection, keyed by local database ids: its link to a
/// repository, and the uids that identify the collection, its folders and its
/// requests in that repository.
final class BackupGitState {
  final BackupGit git;
  final String? collectionUid;

  /// Uid by local folder id.
  final Map<int, String> folderUids;

  /// Uid by local request id.
  final Map<int, String> requestUids;

  const BackupGitState({
    required this.git,
    this.collectionUid,
    this.folderUids = const {},
    this.requestUids = const {},
  });
}

/// Reads and re-creates what ties a collection to its Git repository, so that a
/// workspace file can carry it. Without this, rebuilding the database from a
/// file (switching workplaces, restoring after a restart) would unlink every
/// collection and orphan its unpushed changes.
abstract interface class GitStateStore {
  /// The state of [collectionId], or null when it is not linked to a repository.
  Future<BackupGitState?> read(
    int collectionId, {
    required Iterable<int> folderIds,
    required Iterable<int> requestIds,
  });

  /// Links the freshly restored [collectionId] again. Does nothing (the
  /// collection stays unlinked) when one of the uids already belongs to another
  /// local entity: two collections must never claim the same repository files.
  Future<void> restore(int collectionId, BackupGitState state);
}
