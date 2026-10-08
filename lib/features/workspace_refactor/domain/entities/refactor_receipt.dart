import 'request_unit.dart';
import 'unit_field.dart';

/// A refactor that cannot go ahead or did not finish; [message] says why and is safe to show as is.
final class RefactorException implements Exception {
  final String message;
  const RefactorException(this.message);

  @override
  String toString() => message;
}

/// One unit as it was and as it was written, with the groups that were written.
final class UnitChange {
  final RefactorUnit before;
  final RefactorUnit after;
  final Set<String> groups;
  const UnitChange(this.before, this.after, this.groups);
}

/// What an apply did, and everything needed to undo it. It lives in memory only: a copy of every unit that was
/// changed, as it was before. Nothing about it is saved anywhere, so it is gone when the app closes.
final class RefactorReceipt {
  final String title;
  final DateTime at;
  final List<UnitChange> changes;

  /// Variables that were deleted whole (a row of its own), as they were.
  final List<RefactorUnit> deleted;

  /// Occurrences replaced and definitions deleted.
  final int editsApplied;
  final int deletionsApplied;

  /// Planned changes that were left out: the text had changed since the preview, or the result would have been a name
  /// with nothing in it.
  final int stale;

  const RefactorReceipt({
    required this.title,
    required this.at,
    required this.changes,
    required this.deleted,
    required this.editsApplied,
    required this.deletionsApplied,
    required this.stale,
  });

  bool get isEmpty => changes.isEmpty && deleted.isEmpty;

  /// How many requests, folders, collections and variables were touched.
  int get unitCount => changes.length + deleted.length;

  /// The requests that were changed, so open tabs can be reloaded.
  Set<int> get requestIds => {
    for (final change in changes)
      if (change.after is RequestUnit) change.after.id,
  };
}

/// What an undo did.
final class UndoOutcome {
  final int restored;

  /// Units that were not put back, each with the reason (it changed since, it is gone).
  final List<String> skipped;

  /// The requests that were put back.
  final Set<int> requestIds;

  const UndoOutcome({required this.restored, required this.skipped, this.requestIds = const {}});
}

/// The last refactor of this session, kept so the dialog can offer "Undo last replace" after it was closed and opened
/// again. Memory only.
final class RefactorUndoStore {
  RefactorReceipt? last;
}
