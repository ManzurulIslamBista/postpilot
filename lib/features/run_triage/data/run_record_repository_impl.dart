import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/daos/run_records_dao.dart';
import '../domain/entities/run_record_doc.dart';
import '../domain/repositories/run_record_repository.dart';
import '../domain/services/run_record_codec.dart';

final class RunRecordRepositoryImpl implements RunRecordRepository {
  final RunRecordsDao _dao;

  RunRecordRepositoryImpl(this._dao);

  @override
  Future<int> save(int collectionId, RunRecordDoc doc) async {
    final prepared = RunRecordCodec.prepare(doc);
    final id = await _dao.insertRecord(
      RunRecordsCompanion.insert(
        collectionId: collectionId,
        environmentName: Value(prepared.environmentName),
        source: Value(prepared.source),
        passed: Value(prepared.passed),
        failed: Value(prepared.failed),
        skipped: Value(prepared.skipped),
        durationMs: Value(prepared.durationMs),
        summaryJson: Value(prepared.summaryJson),
        resultsJson: Value(prepared.resultsJson),
        startedAt: Value(prepared.startedAt),
      ),
    );
    await _dao.pruneCollection(collectionId, keep: RunRecordRepository.keepPerCollection);
    return id;
  }

  @override
  Future<List<StoredRun>> recent(int collectionId, {int limit = RunRecordRepository.keepPerCollection}) async =>
      [for (final row in await _dao.recentForCollection(collectionId, limit: limit)) _stored(row)];

  @override
  Stream<List<StoredRun>> watch(int collectionId, {int limit = RunRecordRepository.keepPerCollection}) =>
      _dao.watchForCollection(collectionId, limit: limit).map((rows) => [for (final row in rows) _stored(row)]);

  @override
  Future<StoredRun?> byId(int id) async {
    final row = await _dao.findById(id);
    return row == null ? null : _stored(row);
  }

  @override
  Future<void> clear(int collectionId) => _dao.deleteForCollection(collectionId);

  StoredRun _stored(RunRecord row) => StoredRun(
        id: row.id,
        collectionId: row.collectionId,
        doc: RunRecordCodec.fromColumns(
          collectionName: '',
          environmentName: row.environmentName,
          source: row.source,
          passed: row.passed,
          failed: row.failed,
          skipped: row.skipped,
          durationMs: row.durationMs,
          summaryJson: row.summaryJson,
          resultsJson: row.resultsJson,
          startedAt: row.startedAt,
        ),
      );
}
