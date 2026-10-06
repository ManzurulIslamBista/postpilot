// Pure Dart (no Flutter): part of the command-line build.
import '../documentation/domain/services/secret_masker.dart';
import '../run_triage/domain/services/failure_triage.dart';
import 'run_records_export.dart';
import 'workspace_runner.dart';

/// A run as Markdown, for the job summary of GitHub Actions (`$GITHUB_STEP_SUMMARY`), a pull request comment or an
/// issue: the verdict, the failures grouped by cause with a hint each, then the failing requests one by one.
/// Everything that quotes the server is masked, and the whole text is kept well under the 65,536 characters an issue
/// body or a job summary may hold.
abstract final class MarkdownReporter {
  /// Characters at most; longer output is cut at a line and says so.
  static const maxChars = 60000;

  /// Failing requests listed one by one; the rest are counted.
  static const maxListed = 40;

  /// Skipped requests listed one by one.
  static const maxSkipped = 15;

  /// [iterations] says which pass each outcome belongs to (see `IteratedRun.iterations`) when the run was repeated.
  static String summary(RunSummary s, {List<int>? iterations, String environment = '', String collection = ''}) {
    final b = StringBuffer();
    final failed = s.failed;
    final scope = [
      if (collection.isNotEmpty) 'collection `${_inline(collection)}`',
      if (environment.isNotEmpty) 'environment `${_inline(environment)}`',
    ].join(', ');

    if (s.total == 0) {
      b.writeln('## PostPilot: nothing ran');
      b.writeln();
      b.writeln('No request matched the selection.');
      return b.toString();
    }
    b.writeln('## PostPilot: ${_verdict(s)}');
    b.writeln();
    if (scope.isNotEmpty) {
      b.writeln('Run against $scope.');
      b.writeln();
    }
    b.writeln('| Requests | Passed | Failed | Skipped | Time |');
    b.writeln('| ---: | ---: | ---: | ---: | ---: |');
    b.writeln('| ${s.total} | ${s.passed} | $failed | ${s.skipped} | ${(s.duration.inMilliseconds / 1000).toStringAsFixed(2)} s |');
    b.writeln();
    if (iterations != null && iterations.isNotEmpty) {
      final passes = iterations.reduce((a, c) => a > c ? a : c);
      if (passes > 1) {
        b.writeln('The requests ran in $passes passes.');
        b.writeln();
      }
    }

    final entries = [
      for (final (i, o) in s.outcomes.indexed) CliRunRecords.entryOf(o, iterations == null ? 1 : iterations[i]),
    ];
    final report = FailureTriage.analyse(entries);
    if (report.hasFailures) {
      b.writeln('### What broke (${report.headline})');
      b.writeln();
      for (final group in report.groups.take(12)) {
        b.writeln('- **${_inline(group.fingerprint.title)}**, ${group.count} ${group.count == 1 ? 'request' : 'requests'}: ${_inline(group.hint)}');
      }
      final hidden = report.groups.length - 12;
      if (hidden > 0) b.writeln('- and $hidden more ${hidden == 1 ? 'cause' : 'causes'}');
      b.writeln();

      b.writeln('### Failed requests');
      b.writeln();
      b.writeln('| Request | Result | Why |');
      b.writeln('| --- | --- | --- |');
      var listed = 0;
      for (final (i, o) in s.outcomes.indexed) {
        if (o.passed) continue;
        if (listed == maxListed) break;
        listed++;
        final pass = iterations != null && iterations.isNotEmpty && iterations.reduce((a, c) => a > c ? a : c) > 1 ? ' (iteration ${iterations[i]})' : '';
        final why = o.failures.isEmpty ? 'failed' : o.failures.take(3).join('; ');
        b.writeln('| ${_cell('${o.method} ${_where(o)}$pass')} | ${o.status ?? 'no response'} | ${_cell(why, 220)} |');
      }
      if (failed > listed) b.writeln('\n$failed requests failed; the first $listed are listed.');
      b.writeln();
    }

    final skipped = s.outcomes.where((o) => o.skipped != null).toList();
    if (skipped.isNotEmpty) {
      b.writeln('### Skipped (${skipped.length})');
      b.writeln();
      for (final o in skipped.take(maxSkipped)) {
        b.writeln('- ${_inline('${o.method} ${_where(o)}')}: ${_inline(o.skipped!)}');
      }
      if (skipped.length > maxSkipped) b.writeln('- and ${skipped.length - maxSkipped} more');
      b.writeln();
    }
    return _cap(SecretMasker.maskMessage(b.toString().trimRight()));
  }

  static String _verdict(RunSummary s) {
    if (s.allSkipped) return 'nothing was verified, all ${s.total} requests were skipped';
    if (s.failed == 0) {
      return s.ok ? 'all ${s.total - s.skipped} ${s.total - s.skipped == 1 ? 'request' : 'requests'} passed' : '${s.skipped} skipped, so the run does not count as passing';
    }
    return '${s.failed} of ${s.total} ${s.total == 1 ? 'request' : 'requests'} failed';
  }

  static String _where(RequestOutcome o) => [o.collection, if (o.folder.isNotEmpty) o.folder, o.name].join(' / ');

  static String _inline(String text) => text.replaceAll(RegExp(r'[\r\n]+'), ' ').replaceAll('`', "'").trim();

  /// A table cell: no pipes or line breaks, cut to [max] characters.
  static String _cell(String text, [int max = 120]) {
    final flat = text.replaceAll(RegExp(r'[\r\n]+'), ' ').replaceAll('|', r'\|').replaceAll('`', "'").trim();
    return flat.length <= max ? flat : '${flat.substring(0, max - 1)}…';
  }

  static String _cap(String text) {
    if (text.length <= maxChars) return text;
    final cut = text.lastIndexOf('\n', maxChars - 80);
    return '${text.substring(0, cut > 0 ? cut : maxChars - 80)}\n\n_The summary was shortened to fit the size limit._';
  }
}
