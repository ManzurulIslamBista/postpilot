/// Which requests of a collection a run sends. Whatever is chosen, they run in the collection's canonical order
/// (the sidebar's), never in the order they were picked: a request that logs in has to run before the ones that
/// use its token.
sealed class RunSelection {
  const RunSelection();

  /// Every request of the collection: what a run sends unless told otherwise.
  static const RunSelection all = RunAllRequests();

  /// The requests in [folderId] and in every folder under it.
  const factory RunSelection.folder(int folderId) = RunFolder;

  /// Exactly these requests (ids that no longer exist are ignored).
  factory RunSelection.requests(Iterable<int> requestIds) = RunRequests;
}

final class RunAllRequests extends RunSelection {
  const RunAllRequests();

  @override
  bool operator ==(Object other) => other is RunAllRequests;

  @override
  int get hashCode => (RunAllRequests).hashCode;
}

final class RunFolder extends RunSelection {
  final int folderId;
  const RunFolder(this.folderId);

  @override
  bool operator ==(Object other) => other is RunFolder && other.folderId == folderId;

  @override
  int get hashCode => Object.hash(RunFolder, folderId);
}

final class RunRequests extends RunSelection {
  final Set<int> requestIds;
  RunRequests(Iterable<int> requestIds) : requestIds = Set.unmodifiable(requestIds);

  @override
  bool operator ==(Object other) =>
      other is RunRequests && other.requestIds.length == requestIds.length && other.requestIds.containsAll(requestIds);

  @override
  int get hashCode => Object.hash(RunRequests, Object.hashAllUnordered(requestIds));
}
