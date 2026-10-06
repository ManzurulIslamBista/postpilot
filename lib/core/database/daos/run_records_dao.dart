import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/run_records_table.dart';

part 'run_records_dao.g.dart';

@DriftAccessor(tables: [RunRecords])
class RunRecordsDao extends DatabaseAccessor<AppDatabase> with _$RunRecordsDaoMixin {
  RunRecordsDao(super.db);

  Future<int> insertRecord(RunRecordsCompanion row) => into(runRecords).insert(row);

  Future<RunRecord?> findById(int id) => (select(runRecords)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Newest first.
  Stream<List<RunRecord>> watchForCollection(int collectionId, {int limit = 50}) =>
      (select(runRecords)
            ..where((t) => t.collectionId.equals(collectionId))
            ..orderBy([(t) => OrderingTerm.desc(t.startedAt), (t) => OrderingTerm.desc(t.id)])
            ..limit(limit))
          .watch();

  Future<List<RunRecord>> recentForCollection(int collectionId, {int limit = 50}) =>
      (select(runRecords)
            ..where((t) => t.collectionId.equals(collectionId))
            ..orderBy([(t) => OrderingTerm.desc(t.startedAt), (t) => OrderingTerm.desc(t.id)])
            ..limit(limit))
          .get();

  /// Keeps the newest [keep] records of [collectionId].
  Future<void> pruneCollection(int collectionId, {required int keep}) async {
    final rows = await (select(runRecords)
          ..where((t) => t.collectionId.equals(collectionId))
          ..orderBy([(t) => OrderingTerm.desc(t.startedAt), (t) => OrderingTerm.desc(t.id)]))
        .get();
    if (rows.length <= keep) return;
    final stale = [for (final row in rows.skip(keep)) row.id];
    await (delete(runRecords)..where((t) => t.id.isIn(stale))).go();
  }

  Future<void> deleteForCollection(int collectionId) =>
      (delete(runRecords)..where((t) => t.collectionId.equals(collectionId))).go();
}
