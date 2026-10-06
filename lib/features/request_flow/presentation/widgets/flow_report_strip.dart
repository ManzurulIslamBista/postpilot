import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../domain/entities/flow_report.dart';

/// What the flow around the last send did, as one slim line above the response: `3 attempts`, `polled 5 times`,
/// `5 pages, 482 items`. It is only shown when something beyond a plain send happened, and is folded to that line
/// unless something failed; a click opens the list of every try. The response itself stays clean.
class FlowReportStrip extends StatefulWidget {
  final FlowReport report;
  const FlowReportStrip({super.key, required this.report});

  @override
  State<FlowReportStrip> createState() => _FlowReportStripState();
}

class _FlowReportStripState extends State<FlowReportStrip> {
  late bool _expanded = widget.report.failure != null;

  @override
  void didUpdateWidget(covariant FlowReportStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new send brings a new story: open on failure, fold away otherwise.
    if (!identical(widget.report, oldWidget.report)) _expanded = widget.report.failure != null;
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    if (!report.isNoteworthy) return const SizedBox.shrink();
    final colors = context.colors;
    final pages = report.pages;
    final failed = report.failure != null;
    final warn = !failed && (report.notes.isNotEmpty || (pages != null && !pages.complete));
    final color = failed ? colors.statusError : (warn ? colors.statusWarning : colors.statusSuccess);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.borderSubtle))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const ValueKey('flow-strip-toggle'),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    failed ? Icons.error_outline : (warn ? Icons.warning_amber_rounded : Icons.autorenew),
                    color: color,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (report.retries > 0) StatusChip(label: '${report.retries + 1} attempts', color: color),
                        if (report.polls > 1) StatusChip(label: 'polled ${report.polls} times', color: color),
                        if (pages != null)
                          StatusChip(
                            key: const ValueKey('flow-pages-badge'),
                            label: pages.badge,
                            icon: Icons.layers_outlined,
                            color: pages.complete ? colors.statusSuccess : colors.statusWarning,
                          ),
                        if (failed) StatusChip(label: 'failed', color: colors.statusError),
                      ],
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: colors.secondaryText),
                ],
              ),
            ),
          ),
          if (_expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 170),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: [
                  if (report.failure != null) _Line(report.failure!, colors.statusError),
                  for (final note in report.notes) _Line(note, colors.statusWarning),
                  if (pages != null)
                    _Line(
                      '${pages.strategy}: ${pages.badge}, ${pages.stop.text}${pages.detail == null ? '' : ' (${pages.detail})'}',
                      colors.secondaryText,
                    ),
                  if (report.attempts.length > 1)
                    for (final attempt in report.attempts) _Line(attempt.text, colors.secondaryText, mono: true),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String text;
  final Color color;
  final bool mono;
  const _Line(this.text, this.color, {this.mono = false});

  @override
  Widget build(BuildContext context) {
    final base = mono ? context.textStyles.mono.copyWith(fontSize: 12) : context.textStyles.caption;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText(text, style: base.copyWith(color: color)),
    );
  }
}
