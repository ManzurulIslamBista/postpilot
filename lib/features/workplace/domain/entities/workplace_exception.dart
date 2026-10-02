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
}
