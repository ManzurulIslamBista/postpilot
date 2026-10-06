// Pure Dart.
import '../entities/run_record_doc.dart';

/// What changed between two runs of the same collection.
final class RunComparison {
  /// Failing now, and did not fail in the earlier run (it passed, or it was not part of that run).
  final List<RunResultEntry> newFailures;

  /// Failed in the earlier run, passes now.
  final List<RunResultEntry> fixed;

  /// Failed in both.
  final List<RunResultEntry> stillFailing;

  /// Failed in the earlier run and was skipped or not run this time, so nothing is known about it now.
  final int notRunNow;

  const RunComparison({
    required this.newFailures,
    required this.fixed,
    required this.stillFailing,
    this.notRunNow = 0,
  });

  bool get isUnchanged => newFailures.isEmpty && fixed.isEmpty;

  /// `2 new failures, 1 fixed, 3 still failing`.
  String get summary {
    final parts = [
      if (newFailures.isNotEmpty) '${newFailures.length} new ${newFailures.length == 1 ? 'failure' : 'failures'}',
      if (fixed.isNotEmpty) '${fixed.length} fixed',
      if (stillFailing.isNotEmpty) '${stillFailing.length} still failing',
    ];
    return parts.isEmpty ? 'Same as the earlier run' : parts.join(', ');
  }

  /// Compares [current] with [previous], result by result: the same request in the same pass (data row).
  static RunComparison compare({required List<RunResultEntry> previous, required List<RunResultEntry> current}) {
    final before = {for (final r in previous) r.resultKey: r};
    final newFailures = <RunResultEntry>[];
    final fixed = <RunResultEntry>[];
    final stillFailing = <RunResultEntry>[];
    final seen = <String>{};
    for (final now in current) {
      seen.add(now.resultKey);
      final was = before[now.resultKey];
      if (now.isFailed) {
        (was != null && was.isFailed ? stillFailing : newFailures).add(now);
      } else if (!now.isSkipped && was != null && was.isFailed) {
        fixed.add(now);
      }
    }
    final notRun = previous.where((r) => r.isFailed && !seen.contains(r.resultKey)).length +
        current.where((r) => r.isSkipped && (before[r.resultKey]?.isFailed ?? false)).length;
    return RunComparison(newFailures: newFailures, fixed: fixed, stillFailing: stillFailing, notRunNow: notRun);
  }
}
