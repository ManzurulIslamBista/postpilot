import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../scripting/domain/entities/assertion_result.dart';
import '../entities/baseline_snapshot.dart';
import '../entities/drift_report.dart';
import 'drift_detector.dart';

/// The result row a run adds for a request that enforces its baseline: `Baseline: 2 breaking changes`, failing
/// when the response drifted in a way that can break a client and passing otherwise.
///
/// One function for the collection runner and the command line, so a request is judged identically in both.
abstract final class BaselineCheck {
  static const _shown = 3;

  /// Judges [response] against [baseline]. A missing [baseline] fails: enforcement was asked for and cannot be
  /// done, which a passing row would hide. [missingHint] says how to fix it where the check runs.
  static AssertionResult evaluate(
    BaselineSnapshot? baseline,
    ApiResponseEntity response, {
    String missingHint = 'Record one in Response tools > Suggest tests, or turn off "Enforce baseline in runs".',
  }) {
    if (baseline == null) {
      return AssertionResult(name: 'Baseline: none recorded', passed: false, actual: missingHint);
    }
    // Only the first part of the body arrived, so "the body is no longer JSON" would be the size limit talking.
    if (response.truncated) {
      return const AssertionResult(
        name: 'Baseline: not checked',
        passed: false,
        actual: 'The response was cut off at the size limit, so it cannot be compared. Raise the limit in Settings.',
      );
    }
    return fromReport(DriftDetector.compare(baseline, response));
  }

  /// The row for an already computed [report].
  static AssertionResult fromReport(DriftReport report) {
    final breaking = report.ofSeverity(DriftSeverity.breaking);
    final name = 'Baseline: ${breaking.length} breaking ${breaking.length == 1 ? 'change' : 'changes'}';
    if (breaking.isEmpty) {
      final others = report.nonBreaking + report.info;
      return AssertionResult(
        name: name,
        passed: true,
        actual: others == 0 ? 'Matches the baseline' : '${report.nonBreaking} non-breaking, ${report.info} info',
      );
    }
    final lines = breaking.take(_shown).map((c) => c.message).join(' ');
    final more = breaking.length > _shown ? ' (and ${breaking.length - _shown} more)' : '';
    return AssertionResult(name: name, passed: false, actual: '$lines$more');
  }
}
