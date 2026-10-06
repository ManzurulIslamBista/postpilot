// Pure Dart.
import '../entities/run_record_doc.dart';

/// What the last runs say about one request.
final class RequestStats {
  final String requestKey;

  /// Runs among the last [RequestHistoryStats.window] in which the request ran (was not skipped).
  final int runs;
  final int failedRuns;

  /// The request passed and failed within those runs and went back and forth at least twice (pass, fail, pass; or fail,
  /// pass, fail). A request that passed for weeks and has just started failing changed once: that is a regression, shown
  /// as a new failure, not flakiness.
  final bool isFlaky;

  /// The answer time of this run (the median over its iterations), and the median over the earlier runs.
  final int? latestMs;
  final int? medianMs;

  /// This run was more than twice as slow as usual.
  final bool isSlower;

  const RequestStats({
    required this.requestKey,
    required this.runs,
    required this.failedRuns,
    required this.isFlaky,
    this.latestMs,
    this.medianMs,
    required this.isSlower,
  });

  int get passedRuns => runs - failedRuns;

  /// `failed 3 of the last 10 runs`.
  String get flakyText => 'passed ${passedRuns == 1 ? 'once' : '$passedRuns times'} and failed $failedRuns of the last $runs runs';

  String get slowText => 'took $latestMs ms, usually about $medianMs ms';
}

/// Flaky and slower-than-usual requests, from the results of the runs of one collection in one environment.
abstract final class RequestHistoryStats {
  /// How many runs (the one being looked at included) a request is judged by.
  static const window = 10;

  /// A request is flaky when its outcome changed at least this many times over the runs.
  static const minChanges = 2;

  /// A request needs this many earlier runs with an answer time before it can be called slower than usual.
  static const minSamples = 3;

  /// Slower means more than this many times the median.
  static const slowFactor = 2;

  /// A request must also be at least this much slower, so a 20 ms request taking 45 ms is not reported.
  static const slowFloorMs = 100;

  /// [runsNewestFirst] holds the results of each run, the run being looked at first and older runs after it. Only
  /// the first [window] runs count.
  static Map<String, RequestStats> analyse(List<List<RunResultEntry>> runsNewestFirst, {int lastRuns = window}) {
    final runs = runsNewestFirst.take(lastRuns).toList();
    // One outcome and one answer time per request per run, whatever the number of passes (data rows). `times` has
    // one slot per run (null when the request did not run in it), `outcomes` one per run it ran in.
    final keys = {for (final run in runs) for (final r in run) r.requestKey};
    final outcomes = <String, List<bool>>{for (final key in keys) key: []};
    final times = <String, List<int?>>{for (final key in keys) key: []};
    for (final run in runs) {
      final byRequest = <String, List<RunResultEntry>>{};
      for (final r in run) {
        if (!r.isSkipped) byRequest.putIfAbsent(r.requestKey, () => []).add(r);
      }
      for (final key in keys) {
        final ran = byRequest[key];
        if (ran == null) {
          times[key]!.add(null);
          continue;
        }
        outcomes[key]!.add(ran.every((r) => r.passed));
        times[key]!.add(_median([for (final r in ran) ?r.durationMs]));
      }
    }
    final stats = <String, RequestStats>{};
    for (final key in keys) {
      final passes = outcomes[key] ?? const <bool>[];
      final failed = passes.where((p) => !p).length;
      final series = times[key] ?? const <int?>[];
      final latest = runs.isEmpty || series.isEmpty ? null : series.first;
      final earlier = [for (final t in series.skip(1)) ?t];
      final median = earlier.length < minSamples ? null : _median(earlier);
      final slower = latest != null &&
          median != null &&
          latest > median * slowFactor &&
          latest - median >= slowFloorMs;
      stats[key] = RequestStats(
        requestKey: key,
        runs: passes.length,
        failedRuns: failed,
        isFlaky: failed > 0 && failed < passes.length && _changes(passes) >= minChanges,
        latestMs: latest,
        medianMs: median,
        isSlower: slower,
      );
    }
    return stats;
  }

  /// How many times the outcome changed between neighbouring runs.
  static int _changes(List<bool> outcomes) {
    var count = 0;
    for (var i = 1; i < outcomes.length; i++) {
      if (outcomes[i] != outcomes[i - 1]) count++;
    }
    return count;
  }

  /// The middle value; the mean of the two middle ones for an even count. Null for an empty list.
  static int? _median(List<int> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2).round();
  }
}
