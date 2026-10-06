// Pure Dart (no Flutter): the command-line build writes run records the app can import into triage.
import 'dart:convert';
import 'dart:io';
import '../documentation/domain/services/secret_masker.dart';
import '../run_triage/domain/entities/run_record_doc.dart';
import '../run_triage/domain/services/run_record_codec.dart';
import 'iterated_run.dart';
import 'workspace_runner.dart';

/// What a command-line run leaves for the app: one run record per collection, in the format the app's
/// "Import CLI run" reads (see [RunRecordDoc]). Texts are masked and addresses lose their query, like every record.
abstract final class CliRunRecords {
  /// One request outcome of pass [iteration], as a record keeps it.
  static RunResultEntry entryOf(RequestOutcome o, int iteration) {
    final error = o.error;
    final maskedError = error == null ? null : SecretMasker.maskMessage(error);
    return RunResultEntry(
      name: o.name,
      folder: o.folder,
      method: o.method,
      url: o.url,
      iteration: iteration,
      status: o.status,
      durationMs: o.status == null ? null : o.duration.inMilliseconds,
      passed: o.passed,
      skipped: o.skipped,
      error: maskedError,
      // The error is the first line of `failures`; the record says it once.
      failures: [
        for (final f in o.failures)
          if (f != maskedError) f,
      ],
    );
  }

  /// The records of [run]: one per collection that had a request in it.
  static List<RunRecordDoc> build(
    IteratedRun run, {
    required String environment,
    required DateTime startedAt,
    bool bail = false,
  }) {
    final outcomes = run.outcomes;
    final passes = run.iterations;
    final byCollection = <String, List<RunResultEntry>>{};
    final time = <String, int>{};
    for (final (i, o) in outcomes.indexed) {
      byCollection.putIfAbsent(o.collection, () => []).add(entryOf(o, passes[i]));
      time[o.collection] = (time[o.collection] ?? 0) + o.duration.inMilliseconds;
    }
    return [
      for (final MapEntry(key: collection, value: entries) in byCollection.entries)
        RunRecordCodec.sanitize(
          RunRecordDoc(
            source: 'cli',
            trigger: 'cli',
            collection: collection,
            environment: environment,
            startedAt: startedAt,
            durationMs: time[collection] ?? 0,
            iterations: run.passes.length,
            passed: entries.where((e) => e.passed && !e.isSkipped).length,
            failed: entries.where((e) => e.isFailed).length,
            skipped: entries.where((e) => e.isSkipped).length,
            stoppedOnFailure: bail && (run.stoppedEarly || entries.any((e) => e.isFailed)),
            results: entries,
          ),
        ),
    ];
  }

  /// `postpilot-run-20261006T104200Z-Shop.json`
  static String fileName(RunRecordDoc doc) {
    final t = doc.startedAt.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${t.year}${two(t.month)}${two(t.day)}T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
    final slug = doc.collection.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return 'postpilot-run-$stamp-${slug.isEmpty ? 'collection' : slug}.json';
  }

  /// Writes [docs] into [directory] (created when missing) and returns the paths. A name that is taken gets a number.
  static List<String> write(String directory, List<RunRecordDoc> docs) {
    final dir = Directory(directory)..createSync(recursive: true);
    final paths = <String>[];
    for (final doc in docs) {
      final base = fileName(doc);
      var file = File('${dir.path}${Platform.pathSeparator}$base');
      for (var n = 2; file.existsSync(); n++) {
        file = File('${dir.path}${Platform.pathSeparator}${base.replaceFirst(RegExp(r'\.json$'), '')}-$n.json');
      }
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(doc.toJson()));
      paths.add(file.path);
    }
    return paths;
  }
}
