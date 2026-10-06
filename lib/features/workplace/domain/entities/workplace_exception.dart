/// A workplace operation failed for a reason the user can act on (bad folder,
/// duplicate name, unreadable file). [message] is written for display as-is.
class WorkplaceException implements Exception {
  final String message;
  const WorkplaceException(this.message);

  @override
  String toString() => message;
}

/// The repository's `workspace.json` changed since this workplace last synced
/// (someone else, or another device, pushed). Pushing would overwrite that work.
class RemoteChangedException extends WorkplaceException {
  const RemoteChangedException()
      : super(
          'The repository has changes you have not pulled yet (someone else, or another device, pushed since your last sync). '
          'Pull first to get them, or choose to overwrite them.',
        );

  /// The repository already has a `workspace.json` that differs from this workplace's, and
  /// this workplace never synced with it (it was created over an existing folder, or the
  /// repository was connected later), so there is no record of what was in the repository.
  const RemoteChangedException.neverSynced()
      : super(
          'The repository already has a workspace.json that is different from this workplace, and this workplace has '
          'never synced with it, so there is no way to tell whose work is newer. Pull first to start from the copy in '
          'the repository, or choose to overwrite it.',
        );
}
