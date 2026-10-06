import '../entities/run_record_doc.dart';

/// A run record as stored: its id, the collection it belongs to and what it says.
final class StoredRun {
  final int id;
  final int collectionId;
  final RunRecordDoc doc;

  const StoredRun({required this.id, required this.collectionId, required this.doc});

  DateTime get startedAt => doc.startedAt;
}

/// The runs of each collection, kept on this device only (never in `workspace.json`, Git or a backup): the newest
/// [keepPerCollection] of each, masked and size-capped.
abstract interface class RunRecordRepository {
  static const keepPerCollection = 50;

  /// Stores [doc] for [collectionId], masked and capped, and drops the records beyond the newest
  /// [keepPerCollection] of that collection. Returns the new record's id.
  Future<int> save(int collectionId, RunRecordDoc doc);

  /// The newest records of [collectionId], newest first.
  Future<List<StoredRun>> recent(int collectionId, {int limit = keepPerCollection});

  /// The same list again whenever a record is added or removed.
  Stream<List<StoredRun>> watch(int collectionId, {int limit = keepPerCollection});

  Future<StoredRun?> byId(int id);

  /// Forgets every record of [collectionId].
  Future<void> clear(int collectionId);
}
