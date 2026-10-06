import '../entities/baseline_snapshot.dart';

/// A request's recorded baseline with when it was recorded.
final class StoredBaseline {
  final int requestId;
  final BaselineSnapshot snapshot;
  final String note;
  final DateTime recordedAt;

  const StoredBaseline({required this.requestId, required this.snapshot, required this.recordedAt, this.note = ''});
}

/// The baselines of this device: one per request, never part of the workspace file or Git.
abstract interface class RequestBaselineRepository {
  /// The baseline of [requestId]; null when none is recorded or what is stored cannot be read.
  Future<StoredBaseline?> get(int requestId);

  /// [get] again each time the baseline is recorded, changed or removed.
  Stream<StoredBaseline?> watch(int requestId);

  /// Records [snapshot] as the baseline of [requestId], replacing the one it had.
  Future<void> save(int requestId, BaselineSnapshot snapshot, {String note = ''});

  /// Removes the baseline of [requestId].
  Future<void> delete(int requestId);

  /// Every baseline that can be read.
  Future<List<StoredBaseline>> all();
}
