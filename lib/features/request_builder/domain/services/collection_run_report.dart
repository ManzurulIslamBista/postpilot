import 'dart:convert';
import 'package:csv/csv.dart';
import 'collection_runner_service.dart';

/// One pass over the collection: the data row that drove it and what it
/// produced. [results] fills in as the run streams.
final class RunIteration {
  final int number;
  final Map<String, String> data;
  final List<CollectionRunResult> results = [];

  RunIteration(this.number, this.data);

  /// Requests that were sent and passed: a skipped one is neither passed nor failed.
  int get passedCount => results.where((r) => r.passed && !r.isSkipped).length;
  int get skippedCount => results.where((r) => r.isSkipped).length;
  bool get allPassed => results.every((r) => r.passed);
}

/// Totals over a run's results. Times are response times, so a request that
/// never got a response adds no time and doesn't count toward the average.
final class CollectionRunSummary {
  final int iterations;
  final int requests;
  final int passed;
  final int assertions;
  final int passedAssertions;
  final Duration totalTime;
  final Duration averageTime;

  /// Requests that were not sent because their Run if conditions did not hold: not passed, and not failed either.
  final int skipped;

  const CollectionRunSummary({
    required this.iterations,
    required this.requests,
    required this.passed,
    required this.assertions,
    required this.passedAssertions,
    required this.totalTime,
    required this.averageTime,
    this.skipped = 0,
  });

  int get failed => requests - passed - skipped;

  factory CollectionRunSummary.of(Iterable<CollectionRunResult> results) {
    var total = Duration.zero;
    var timed = 0;
    for (final result in results) {
      final response = result.response;
      if (response == null) continue;
      total += response.duration;
      timed++;
    }
    return CollectionRunSummary(
      iterations: {for (final r in results) r.iteration}.length,
      requests: results.length,
      passed: results.where((r) => r.passed && !r.isSkipped).length,
      skipped: results.where((r) => r.isSkipped).length,
      assertions: results.fold(0, (n, r) => n + r.assertionCount),
      passedAssertions: results.fold(0, (n, r) => n + r.passedAssertionCount),
      totalTime: total,
      averageTime: timed == 0 ? Duration.zero : total ~/ timed,
    );
  }
}

enum RunExportFormat {
  json('JSON', 'collection-run-results.json', 'application/json'),
  csv('CSV', 'collection-run-results.csv', 'text/csv');

  final String label;
  final String fileName;
  final String mimeType;

  const RunExportFormat(this.label, this.fileName, this.mimeType);
}

/// Serializes a run's results for the clipboard or a file.
final class CollectionRunExporter {
  const CollectionRunExporter();

  String export(RunExportFormat format, List<RunIteration> iterations) => switch (format) {
        RunExportFormat.json => toJson(iterations),
        RunExportFormat.csv => toCsv(iterations),
      };

  String toJson(List<RunIteration> iterations) {
    final summary = CollectionRunSummary.of([for (final iteration in iterations) ...iteration.results]);
    return const JsonEncoder.withIndent('  ').convert({
      'summary': {
        'iterations': summary.iterations,
        'requests': summary.requests,
        'passed': summary.passed,
        'failed': summary.failed,
        if (summary.skipped > 0) 'skipped': summary.skipped,
        'assertions': summary.assertions,
        'assertionsPassed': summary.passedAssertions,
        'totalTimeMs': summary.totalTime.inMilliseconds,
        'averageTimeMs': summary.averageTime.inMilliseconds,
      },
      'iterations': [
        for (final iteration in iterations)
          {
            'iteration': iteration.number,
            if (iteration.data.isNotEmpty) 'data': iteration.data,
            'results': [
              for (final r in iteration.results)
                {
                  'request': r.request.name,
                  'method': r.request.method.label,
                  'passed': r.passed,
                  'status': r.response?.statusCode,
                  'timeMs': r.response?.duration.inMilliseconds,
                  'assertionsPassed': r.passedAssertionCount,
                  'assertionsTotal': r.assertionCount,
                  'failures': r.failures,
                  'error': r.error,
                  if (r.isSkipped) 'skipped': r.skipped,
                  'flow': ?r.flowJson,
                  if (r.authNotes.isNotEmpty) 'authNotes': r.authNotes,
                },
            ],
          },
      ],
    });
  }

  String toCsv(List<RunIteration> iterations) {
    // A `flow` column (why a request was skipped, how many attempts, polls and pages it took) is only there when some
    // result has something to say about it, so a run without flow controls exports the columns it always did.
    final withFlow = iterations.any((i) => i.results.any((r) => r.flowText != null));
    return Csv(lineDelimiter: '\n').encode([
      [
        'iteration',
        'request',
        'method',
        'status',
        'timeMs',
        'passed',
        'assertionsPassed',
        'assertionsTotal',
        'failures',
        'error',
        if (withFlow) 'flow',
      ],
      for (final iteration in iterations)
        for (final r in iteration.results)
          [
            iteration.number,
            _cell(r.request.name),
            r.request.method.label,
            r.response?.statusCode ?? '',
            r.response?.duration.inMilliseconds ?? '',
            r.passed,
            r.passedAssertionCount,
            r.assertionCount,
            _cell(r.failures.join('; ')),
            _cell(r.error ?? ''),
            if (withFlow) _cell(r.flowText ?? ''),
          ],
    ]);
  }

  static final _formulaStart = RegExp(r'^[=+\-@\t\r]');

  /// Request names come from imported collections, so a leading `=`, `+`, `-`
  /// or `@` would run as a formula when the CSV is opened in a spreadsheet.
  String _cell(String text) => _formulaStart.hasMatch(text) ? "'$text" : text;
}
