import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/status_chip.dart';
import '../domain/entities/run_record_doc.dart';
import '../domain/services/failure_fingerprinter.dart';
import '../domain/services/failure_triage.dart';
import '../domain/services/issue_markdown.dart';
import '../domain/services/triage_analysis.dart';

/// The triage of one run: what actually broke (the failures grouped by cause, biggest first, each with a hint), what
/// changed since the run before, which requests are flaky or slower than usual, and the two things to do about it:
/// run the failed requests again, or copy the findings as a GitHub issue.
class TriagePane extends StatelessWidget {
  /// Null before a run has ended.
  final TriageAnalysis? analysis;

  /// A run is going on, or its triage is being made.
  final bool busy;

  /// The run was stopped before its end.
  final bool isPartial;

  /// Said at the top: that the run was stored, or why it was not.
  final String? note;
  final bool noteIsError;

  /// Runs these requests again. Null hides the button.
  final ValueChanged<List<int>>? onRerunFailed;

  const TriagePane({
    super.key,
    required this.analysis,
    this.busy = false,
    this.isPartial = false,
    this.note,
    this.noteIsError = false,
    this.onRerunFailed,
  });

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    if (a == null) {
      return busy
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [CircularProgressIndicator(), SizedBox(height: 12), Text('The triage appears when the run has finished.')],
                ),
              ),
            )
          : const EmptyHint(icon: Icons.fact_check_outlined, title: 'No run to look at yet', message: 'Run the collection: the failures are grouped by cause here.');
    }
    final report = a.report;
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
      children: [
        _Header(analysis: a, isPartial: isPartial, note: note, noteIsError: noteIsError, busy: busy, onRerunFailed: onRerunFailed),
        if (a.comparison != null && a.previous != null) _Comparison(analysis: a),
        if (!report.hasFailures)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EmptyHint(icon: Icons.check_circle_outline, title: 'Nothing failed', message: 'Every request that was sent passed its checks.'),
          )
        else
          for (final group in report.groups) _GroupCard(group: group, analysis: a),
        if (a.flaky.isNotEmpty) _FlakySection(analysis: a),
        if (a.slower.isNotEmpty) _SlowSection(analysis: a),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final TriageAnalysis analysis;
  final bool isPartial;
  final String? note;
  final bool noteIsError;
  final bool busy;
  final ValueChanged<List<int>>? onRerunFailed;
  const _Header({
    required this.analysis,
    required this.isPartial,
    required this.note,
    required this.noteIsError,
    required this.busy,
    required this.onRerunFailed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final report = analysis.report;
    final ids = analysis.failedRequestIds;
    final canRerun = report.hasFailures && ids.isNotEmpty && !busy && onRerunFailed != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(report.headline, style: context.textStyles.heading),
              StatusChip(label: '${analysis.run.passed} passed', color: colors.statusSuccess),
              if (analysis.run.failed > 0) StatusChip(label: '${analysis.run.failed} failed', color: colors.statusError),
              if (analysis.run.skipped > 0) StatusChip(label: '${analysis.run.skipped} skipped'),
            ],
          ),
          if (isPartial)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: InfoBanner(
                kind: BannerKind.warning,
                message: 'The run was stopped, so this is only what ran until then. It was not added to the run history.',
              ),
            ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InfoBanner(kind: noteIsError ? BannerKind.error : BannerKind.info, message: note!),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onRerunFailed != null)
                Tooltip(
                  message: report.hasFailures && ids.isEmpty
                      ? 'None of the failed requests could be matched with a request of this collection.'
                      : 'Run only the requests that failed, in their usual order',
                  child: FilledButton.icon(
                    onPressed: canRerun ? () => onRerunFailed!(ids) : null,
                    icon: const Icon(Icons.replay, size: 16),
                    label: Text(ids.isEmpty ? 'Re-run failed only' : 'Re-run failed only (${ids.length})'),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: report.hasFailures ? () => _copyIssue(context) : null,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy as GitHub issue'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copyIssue(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: IssueMarkdown.build(analysis)));
    messenger?.showSnackBar(const SnackBar(content: Text('Issue text copied: secrets are masked and addresses have no query string')));
  }
}

/// What changed since the run before.
class _Comparison extends StatelessWidget {
  final TriageAnalysis analysis;
  const _Comparison({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final c = analysis.comparison!;
    final previous = analysis.previous!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Since the run before (${IssueMarkdown.stamp(previous.startedAt)})', style: context.textStyles.body.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                StatusChip(label: '${c.newFailures.length} new', color: c.newFailures.isEmpty ? null : colors.statusError, icon: Icons.add_circle_outline),
                StatusChip(label: '${c.fixed.length} fixed', color: c.fixed.isEmpty ? null : colors.statusSuccess, icon: Icons.check_circle_outline),
                StatusChip(label: '${c.stillFailing.length} still failing', color: c.stillFailing.isEmpty ? null : colors.statusWarning, icon: Icons.sync_problem),
              ],
            ),
            if (c.newFailures.isNotEmpty) _Names(title: 'New failures', results: c.newFailures),
            if (c.fixed.isNotEmpty) _Names(title: 'Fixed', results: c.fixed),
            if (c.stillFailing.isNotEmpty) _Names(title: 'Still failing', results: c.stillFailing),
            if (c.notRunNow > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${c.notRunNow} request${c.notRunNow == 1 ? '' : 's'} that failed before did not run this time.',
                  style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Names extends StatelessWidget {
  final String title;
  final List<RunResultEntry> results;
  const _Names({required this.title, required this.results});

  @override
  Widget build(BuildContext context) {
    final shown = results.take(50).toList();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 6),
        dense: true,
        title: Text('$title (${results.length})', style: context.textStyles.caption.copyWith(fontWeight: FontWeight.w700)),
        children: [
          for (final r in shown)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text('${r.method}  ${r.label}', style: context.textStyles.caption, overflow: TextOverflow.ellipsis),
              ),
            ),
          if (results.length > shown.length)
            Align(alignment: Alignment.centerLeft, child: Text('and ${results.length - shown.length} more', style: context.textStyles.caption)),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final FailureGroup group;
  final TriageAnalysis analysis;
  const _GroupCard({required this.group, required this.analysis});

  static IconData _icon(FailureKind kind) => switch (kind) {
        FailureKind.auth => Icons.lock_outline,
        FailureKind.network => Icons.cloud_off_outlined,
        FailureKind.config => Icons.tune,
        FailureKind.blocked => Icons.shield_outlined,
        FailureKind.http => Icons.http,
        FailureKind.assertion => Icons.rule,
        FailureKind.extraction => Icons.output,
        FailureKind.other => Icons.error_outline,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final f = group.fingerprint;
    final first = group.first;
    final shown = group.results.take(100).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon(f.kind), size: 20, color: colors.statusError),
                const SizedBox(width: 8),
                Expanded(child: Text(f.title, style: context.textStyles.body.copyWith(fontWeight: FontWeight.w700))),
                const SizedBox(width: 8),
                StatusChip(label: '${group.count} ${group.count == 1 ? 'request' : 'requests'}', color: colors.statusError),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(group.hint, style: context.textStyles.body),
            const SizedBox(height: 8),
            Text('First: ${first.method} ${first.url.isEmpty ? first.name : first.url}', style: context.textStyles.mono, maxLines: 2, overflow: TextOverflow.ellipsis),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                dense: true,
                title: Text(
                  group.count == 1 ? 'Show the request' : 'Show all ${group.count} requests',
                  style: context.textStyles.caption.copyWith(fontWeight: FontWeight.w700),
                ),
                children: [
                  for (final r in shown) _ResultLine(result: r, analysis: analysis),
                  if (group.count > shown.length)
                    Align(alignment: Alignment.centerLeft, child: Text('and ${group.count - shown.length} more', style: context.textStyles.caption)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  final RunResultEntry result;
  final TriageAnalysis analysis;
  const _ResultLine({required this.result, required this.analysis});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final flaky = analysis.isFlaky(result);
    final slower = analysis.isSlower(result);
    final why = result.error ?? (result.failures.isEmpty ? (result.status == null ? 'failed' : 'status ${result.status}') : result.failures.first);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(result.method, style: TextStyle(color: colors.forMethod(result.method), fontWeight: FontWeight.bold, fontSize: 11)),
              Text(result.label, style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600)),
              if (result.iteration > 1) Text('(pass ${result.iteration})', style: context.textStyles.caption),
              if (flaky) const StatusChip(label: 'Flaky', icon: Icons.shuffle),
              if (slower) const StatusChip(label: 'Slower than usual', icon: Icons.hourglass_bottom),
            ],
          ),
          Text(why, style: context.textStyles.caption.copyWith(color: colors.secondaryText), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _FlakySection extends StatelessWidget {
  final TriageAnalysis analysis;
  const _FlakySection({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final labels = {for (final r in analysis.run.results) r.requestKey: r.label};
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: ToolSection(
        title: 'Flaky requests',
        hint: 'These went back and forth between passing and failing over the last runs: a test or a service that cannot be trusted yet.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in analysis.flaky.take(50))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${labels[s.requestKey] ?? s.requestKey}: ${s.flakyText}', style: context.textStyles.body),
              ),
          ],
        ),
      ),
    );
  }
}

class _SlowSection extends StatelessWidget {
  final TriageAnalysis analysis;
  const _SlowSection({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final labels = {for (final r in analysis.run.results) r.requestKey: r.label};
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: ToolSection(
        title: 'Slower than usual',
        hint: 'More than twice the median of this request over the earlier runs.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in analysis.slower.take(50))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${labels[s.requestKey] ?? s.requestKey}: ${s.slowText}', style: context.textStyles.body),
              ),
          ],
        ),
      ),
    );
  }
}
