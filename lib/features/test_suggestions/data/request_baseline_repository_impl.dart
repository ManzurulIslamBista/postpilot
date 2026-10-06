import 'package:drift/drift.dart' show Value;
import '../../../core/database/app_database.dart';
import '../../../core/database/daos/request_baselines_dao.dart';
import '../domain/entities/baseline_snapshot.dart';
import '../domain/repositories/request_baseline_repository.dart';

final class RequestBaselineRepositoryImpl implements RequestBaselineRepository {
  final RequestBaselinesDao _dao;
  const RequestBaselineRepositoryImpl(this._dao);

  @override
  Future<StoredBaseline?> get(int requestId) async => _stored(await _dao.findByRequest(requestId));

  @override
  Stream<StoredBaseline?> watch(int requestId) => _dao.watchByRequest(requestId).map(_stored);

  @override
  Future<void> save(int requestId, BaselineSnapshot snapshot, {String note = ''}) => _dao.upsert(
        RequestBaselinesCompanion(
          requestId: Value(requestId),
          snapshotJson: Value(snapshot.encode()),
          note: Value(note),
          recordedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> delete(int requestId) => _dao.deleteForRequest(requestId);

  @override
  Future<List<StoredBaseline>> all() async => [
        for (final row in await _dao.all()) ?_stored(row),
      ];

  /// A row whose JSON cannot be read is treated as no baseline: it must not break sending a request.
  StoredBaseline? _stored(RequestBaseline? row) {
    if (row == null) return null;
    final snapshot = BaselineSnapshot.decode(row.snapshotJson);
    if (snapshot == null) return null;
    return StoredBaseline(requestId: row.requestId, snapshot: snapshot, note: row.note, recordedAt: row.recordedAt);
  }
}
