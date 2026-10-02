/// A workplace operation failed for a reason the user can act on (bad folder,
/// duplicate name, unreadable file). [message] is written for display as-is.
class WorkplaceException implements Exception {
  final String message;
  const WorkplaceException(this.message);

  @override
  String toString() => message;
}
