import '../../../collections/domain/entities/collection_entity.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../entities/run_record_doc.dart';
import '../repositories/run_record_repository.dart';
import 'app_run_mapper.dart';
import 'run_record_codec.dart';

/// What importing a command-line run did.
final class CliImportResult {
  /// The record's id; null when [duplicateOf] is set.
  final int? id;
  final RunRecordDoc doc;

  /// How many results were matched with a request of the collection (so "Re-run failed only" can use them).
  final int matched;

  /// The record this one is a copy of, when the same run was imported before.
  final int? duplicateOf;

  const CliImportResult({required this.id, required this.doc, required this.matched, this.duplicateOf});

  /// The run was recorded for another collection name than the one it was imported into.
  bool differsFrom(String collectionName) => doc.collection.isNotEmpty && doc.collection != collectionName;
}

/// Imports a run record the command line wrote (`--records-dir`) as a run of a collection: results are matched with
/// the collection's requests by folder, method and name, so a failure found in CI can be re-run from the app.
abstract final class CliRunImporter {
  /// [text] is the file. Throws a [FormatException] saying what is wrong with it.
  static Future<CliImportResult> import({
    required String text,
    required int collectionId,
    required List<RequestSummaryEntity> requests,
    required List<FolderEntity> folders,
    required RunRecordRepository records,
  }) async {
    final parsed = RunRecordCodec.parseFile(text);
    final matched = match(parsed.results, requests, folders);
    final doc = parsed.copyWith(results: matched.results, source: 'cli');

    // The same file imported twice is one run.
    for (final existing in await records.recent(collectionId)) {
      final e = existing.doc;
      if (e.source == 'cli' &&
          e.startedAt.toUtc().millisecondsSinceEpoch ~/ 1000 == doc.startedAt.toUtc().millisecondsSinceEpoch ~/ 1000 &&
          (e.passed, e.failed, e.skipped) == (doc.passed, doc.failed, doc.skipped) &&
          e.environment == doc.environment) {
        return CliImportResult(id: null, doc: doc, matched: matched.count, duplicateOf: existing.id);
      }
    }
    final id = await records.save(collectionId, doc);
    return CliImportResult(id: id, doc: doc, matched: matched.count);
  }

  /// [results] with the id of the request each belongs to, where the collection has exactly one request of that
  /// folder, method and name.
  static ({List<RunResultEntry> results, int count}) match(
    List<RunResultEntry> results,
    List<RequestSummaryEntity> requests,
    List<FolderEntity> folders,
  ) {
    final byKey = <String, List<int>>{};
    for (final r in requests) {
      final key = '${AppRunMapper.folderPath(folders, r.folderId)}\u0001${r.method.label}\u0001${r.name}';
      byKey.putIfAbsent(key, () => []).add(r.id);
    }
    var count = 0;
    final mapped = [
      for (final r in results)
        () {
          final ids = byKey[r.requestKey];
          if (ids == null || ids.length != 1) return r.copyWith(clearRequestId: true);
          count++;
          return r.copyWith(requestId: ids.single);
        }(),
    ];
    return (results: mapped, count: count);
  }
}
