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

  int get passedCount => results.where((r) => r.passed).length;
  bool get allPassed => passedCount == results.length;
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

  const CollectionRunSummary({
    required this.iterations,
    required this.requests,
    required this.passed,
    required this.assertions,
    required this.passedAssertions,
    required this.totalTime,
    required this.averageTime,
  });

  int get failed => requests - passed;

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
      passed: results.where((r) => r.passed).length,
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
                },
            ],
          },
      ],
    });
  }

  String toCsv(List<RunIteration> iterations) => Csv(lineDelimiter: '\n').encode([
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
            ],
      ]);

  static final _formulaStart = RegExp(r'^[=+\-@\t\r]');

  /// Request names come from imported collections, so a leading `=`, `+`, `-`
  /// or `@` would run as a formula when the CSV is opened in a spreadsheet.
  String _cell(String text) => _formulaStart.hasMatch(text) ? "'$text" : text;
}
