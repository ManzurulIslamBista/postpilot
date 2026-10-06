// Pure Dart.
import '../entities/run_record_doc.dart';
import 'failure_triage.dart';
import 'request_history_stats.dart';
import 'run_comparison.dart';

/// Everything triage says about one run: its failures by cause, what changed since the run before it in the same
/// environment, and which requests are flaky or slower than usual.
final class TriageAnalysis {
  final RunRecordDoc run;
  final TriageReport report;

  /// The run before this one in the same environment; null when there is none to compare with.
  final RunRecordDoc? previous;
  final RunComparison? comparison;
  final Map<String, RequestStats> stats;

  const TriageAnalysis({
    required this.run,
    required this.report,
    required this.previous,
    required this.comparison,
    required this.stats,
  });

  RequestStats? statsOf(RunResultEntry result) => stats[result.requestKey];

  bool isFlaky(RunResultEntry result) => statsOf(result)?.isFlaky ?? false;
  bool isSlower(RunResultEntry result) => statsOf(result)?.isSlower ?? false;

  /// Requests of this run that are flaky.
  List<RequestStats> get flaky => [
        for (final s in stats.values)
          if (s.isFlaky && run.results.any((r) => r.requestKey == s.requestKey)) s,
      ];

  /// Requests of this run that are slower than usual.
  List<RequestStats> get slower => [
        for (final s in stats.values)
          if (s.isSlower && run.results.any((r) => r.requestKey == s.requestKey)) s,
      ];

  /// The ids of the requests that failed in this run and are known to the app, for "Re-run failed only".
  List<int> get failedRequestIds => [
        for (final id in {for (final r in run.results) if (r.isFailed && r.requestId != null) r.requestId!}) id,
      ];

  /// [earlierNewestFirst] are the runs of the same collection before [run]; only those in the same environment
  /// count, because a run against another environment says nothing about this one.
  static TriageAnalysis of(RunRecordDoc run, List<RunRecordDoc> earlierNewestFirst) {
    final sameEnvironment = [
      for (final r in earlierNewestFirst)
        if (r.environment == run.environment) r,
    ];
    final previous = sameEnvironment.firstOrNull;
    return TriageAnalysis(
      run: run,
      report: FailureTriage.analyse(run.results),
      previous: previous,
      comparison: previous == null ? null : RunComparison.compare(previous: previous.results, current: run.results),
      stats: RequestHistoryStats.analyse([run.results, for (final r in sameEnvironment) r.results]),
    );
  }
}
