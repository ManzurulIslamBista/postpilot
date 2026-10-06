import 'dart:async';
import 'package:postpilot/features/test_suggestions/domain/entities/baseline_snapshot.dart';
import 'package:postpilot/features/test_suggestions/domain/repositories/request_baseline_repository.dart';

/// The baselines of this device, in memory, behind the interface the app uses.
final class InMemoryBaselines implements RequestBaselineRepository {
  final rows = <int, StoredBaseline>{};
  final _changes = StreamController<int>.broadcast();

  /// Makes the next [save] throw, to see how a failure is told.
  bool failNextSave = false;

  @override
  Future<StoredBaseline?> get(int requestId) async => rows[requestId];

  @override
  Stream<StoredBaseline?> watch(int requestId) async* {
    yield rows[requestId];
    await for (final id in _changes.stream) {
      if (id == requestId) yield rows[requestId];
    }
  }

  @override
  Future<void> save(int requestId, BaselineSnapshot snapshot, {String note = ''}) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('disk full');
    }
    rows[requestId] = StoredBaseline(requestId: requestId, snapshot: snapshot, note: note, recordedAt: DateTime.now());
    _changes.add(requestId);
  }

  @override
  Future<void> delete(int requestId) async {
    rows.remove(requestId);
    _changes.add(requestId);
  }

  @override
  Future<List<StoredBaseline>> all() async => rows.values.toList();
}
