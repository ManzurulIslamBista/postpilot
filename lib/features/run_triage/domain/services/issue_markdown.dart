// Pure Dart.
import '../../../documentation/domain/services/secret_masker.dart';
import '../entities/run_record_doc.dart';
import 'triage_analysis.dart';

/// A GitHub issue (or any Markdown) about a failed run: the failing causes first, with one example request each.
/// It is written from the masked record, shows addresses without their query and carries no response body, and it
/// is masked once more at the end, so it is safe to paste into a ticket.
abstract final class IssueMarkdown {
  /// Failing requests listed under each cause.
  static const examplesPerCause = 5;

  /// Causes listed; the rest are counted.
  static const maxCauses = 12;

  static String build(TriageAnalysis analysis) {
    final run = analysis.run;
    final report = analysis.report;
    final b = StringBuffer();
    final env = run.environment.isEmpty ? '' : ' (${_inline(run.environment)})';
    b.writeln('## PostPilot: ${report.failedResults} of ${run.total} ${run.total == 1 ? 'request' : 'requests'} failed in ${_inline(run.collection)}$env');
    b.writeln();
    b.writeln('- **Environment:** ${run.environment.isEmpty ? '(none)' : _inline(run.environment)}');
    b.writeln('- **Run:** ${stamp(run.startedAt)}, ${_seconds(run.durationMs)}, ${_where(run)}');
    b.writeln('- **Result:** ${run.passed} passed, ${run.failed} failed, ${run.skipped} skipped');
    if (run.stoppedOnFailure) b.writeln('- The run stopped at the first failure, so later requests did not run.');
    if (run.truncated) b.writeln('- The record is shortened; not every passing request is listed.');
    b.writeln();

    if (!report.hasFailures) {
      b.writeln('Nothing failed in this run.');
      return _finish(b);
    }

    b.writeln('### ${report.groups.length == 1 ? 'One cause' : '${report.groups.length} causes'}');
    b.writeln();
    for (final (index, group) in report.groups.take(maxCauses).indexed) {
      final f = group.fingerprint;
      b.writeln('#### ${index + 1}. ${_inline(f.title)}: ${group.count} ${group.count == 1 ? 'request' : 'requests'}');
      b.writeln();
      b.writeln(group.hint);
      b.writeln();
      for (final r in group.results.take(examplesPerCause)) {
        b.writeln('- `${_inline(r.method)} ${_inline(_address(r))}` (${_inline(r.label)}): ${_inline(_reason(r))}');
      }
      final more = group.count - examplesPerCause;
      if (more > 0) b.writeln('- and $more more');
      b.writeln();
    }
    final hidden = report.groups.length - maxCauses;
    if (hidden > 0) {
      b.writeln('$hidden more ${hidden == 1 ? 'cause' : 'causes'} not listed.');
      b.writeln();
    }

    final comparison = analysis.comparison;
    final previous = analysis.previous;
    if (comparison != null && previous != null) {
      b.writeln('### Since the earlier run (${stamp(previous.startedAt)})');
      b.writeln();
      b.writeln(comparison.summary);
      for (final r in comparison.newFailures.take(examplesPerCause)) {
        b.writeln('- new: ${_inline(r.label)}');
      }
      b.writeln();
    }

    final flaky = analysis.flaky;
    if (flaky.isNotEmpty) {
      b.writeln('### Flaky');
      b.writeln();
      for (final s in flaky.take(examplesPerCause)) {
        b.writeln('- ${_inline(_labelOf(analysis, s.requestKey))}: ${s.flakyText}');
      }
      b.writeln();
    }
    return _finish(b);
  }

  /// The issue title.
  static String title(TriageAnalysis analysis) {
    final run = analysis.run;
    final env = run.environment.isEmpty ? '' : ' on ${_inline(run.environment)}';
    return 'PostPilot: ${analysis.report.failedResults} of ${run.total} requests failed in ${_inline(run.collection)}$env';
  }

  static String _finish(StringBuffer b) => SecretMasker.maskMessage(b.toString().trimRight());

  static String _labelOf(TriageAnalysis analysis, String requestKey) {
    for (final r in analysis.run.results) {
      if (r.requestKey == requestKey) return r.label;
    }
    return requestKey;
  }

  /// The address a person recognises: the saved address of the request, which never holds a query.
  static String _address(RunResultEntry r) => r.url.isEmpty ? r.name : r.url;

  static String _reason(RunResultEntry r) {
    final error = r.error;
    if (error != null && error.trim().isNotEmpty) return _first(error);
    if (r.failures.isNotEmpty) return _first(r.failures.first);
    return r.status == null ? 'failed' : 'status ${r.status}';
  }

  static String _first(String text) {
    final line = text.trim().split(RegExp(r'[\r\n]+')).first.trim();
    return line.length <= 160 ? line : '${line.substring(0, 159)}…';
  }

  /// Text that goes into a line of Markdown: no backticks or newlines that would break it open.
  static String _inline(String text) => text.replaceAll(RegExp(r'[\r\n]+'), ' ').replaceAll('`', "'").trim();

  static String _where(RunRecordDoc run) => switch (run.trigger) {
        'monitor' => 'by the monitor',
        'cli' => 'from the command line',
        _ => run.source == 'cli' ? 'from the command line' : 'from the app',
      };

  static String _seconds(int ms) => ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s';

  /// `2026-10-06 10:42 UTC`.
  static String stamp(DateTime time) {
    final t = time.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)} UTC';
  }
}
