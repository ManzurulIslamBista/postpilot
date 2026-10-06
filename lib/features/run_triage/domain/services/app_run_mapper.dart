import '../../../collections/domain/entities/collection_entity.dart';
import '../../../request_builder/domain/services/collection_runner_service.dart';
import '../entities/run_record_doc.dart';

/// Turns what the app's collection runner produced into a run record.
abstract final class AppRunMapper {
  /// One result as a record keeps it. [folder] is the folder path of the request (`Auth/Admin`) and [url] its
  /// address as written (`{{baseUrl}}/orders`), both looked up by the caller; the record masks and trims them.
  static RunResultEntry entryOf(CollectionRunResult result, {required String folder, String url = ''}) {
    final response = result.response;
    return RunResultEntry(
      requestId: result.request.id,
      name: result.request.name,
      folder: folder,
      method: result.request.method.label,
      url: url,
      iteration: result.iteration,
      status: response?.statusCode,
      durationMs: response?.duration.inMilliseconds,
      passed: result.passed,
      skipped: result.skipped,
      error: result.error,
      failures: result.failures,
    );
  }

  /// The names of the folders above [folderId], outermost first, joined with `/`; empty at the top level.
  static String folderPath(Iterable<FolderEntity> folders, int? folderId) {
    final byId = {for (final f in folders) f.id: f};
    final names = <String>[];
    var current = folderId;
    for (var guard = 0; current != null && guard < 64; guard++) {
      final folder = byId[current];
      if (folder == null) break;
      names.insert(0, folder.name);
      current = folder.parentFolderId;
    }
    return names.join('/');
  }

  /// A record of a run with [results], counted the way the runner counts: a skipped request is neither passed nor
  /// failed.
  static RunRecordDoc docOf({
    required String collection,
    required String environment,
    required DateTime startedAt,
    required Duration duration,
    required List<RunResultEntry> results,
    String trigger = 'manual',
    int iterations = 1,
    bool stoppedOnFailure = false,
  }) =>
      RunRecordDoc(
        source: 'app',
        trigger: trigger,
        collection: collection,
        environment: environment,
        startedAt: startedAt,
        durationMs: duration.inMilliseconds,
        iterations: iterations,
        passed: results.where((r) => r.passed && !r.isSkipped).length,
        failed: results.where((r) => r.isFailed).length,
        skipped: results.where((r) => r.isSkipped).length,
        stoppedOnFailure: stoppedOnFailure,
        results: results,
      );
}
