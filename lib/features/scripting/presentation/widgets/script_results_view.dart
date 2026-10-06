import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/script_run_result.dart';

/// Pass/fail readout shown after a send. Collapsed to its one-line summary
/// while everything passed, so the response body keeps the room; a failure
/// opens it up, since that is the part worth reading. Click the summary to
/// toggle. Renders nothing when the request has no scripts.
class ScriptResultsView extends StatefulWidget {
  final ScriptRunResult result;
  const ScriptResultsView({super.key, required this.result});

  @override
  State<ScriptResultsView> createState() => _ScriptResultsViewState();
}

class _ScriptResultsViewState extends State<ScriptResultsView> {
  late bool _expanded = widget.result.hasFailures;

  @override
  void didUpdateWidget(covariant ScriptResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new send brings a new verdict: open on failure, fold away on success.
    if (!identical(widget.result, oldWidget.result)) _expanded = widget.result.hasFailures;
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    if (result.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    final color = result.hasFailures ? colors.statusError : colors.statusSuccess;
    final savedCount = result.extracted.where((e) => e.ok).length;
    final summary = [
      if (result.assertions.isNotEmpty) '${result.passedCount}/${result.assertions.length} tests passed',
      if (result.extracted.isNotEmpty) '$savedCount/${result.extracted.length} variables saved',
    ].join(' · ');

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(result.hasFailures ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      summary,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.body.copyWith(color: color, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Spacer(),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: colors.secondaryText),
                ],
              ),
            ),
          ),
          if (_expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: [
                  for (final a in result.assertions)
                    _ResultRow(passed: a.passed, label: a.name, detail: a.actual, origin: a.origin),
                  for (final e in result.extracted)
                    _ResultRow(
                      passed: e.ok,
                      label: '{{${e.key}}} → ${e.scope.label.toLowerCase()}',
                      detail: e.error ?? e.value ?? '',
                      origin: e.origin,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final bool passed;
  final String label;
  final String detail;

  /// Where an inherited test was set (`folder "Auth"`); null for the request's own.
  final String? origin;
  const _ResultRow({required this.passed, required this.label, required this.detail, this.origin});

  @override
  Widget build(BuildContext context) {
    final color = passed ? context.colors.statusSuccess : context.colors.statusError;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(passed ? Icons.check : Icons.close, color: color, size: 14),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: Text(
              origin == null ? label : '$label · from $origin',
              style: context.textStyles.caption,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              detail,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.mono.copyWith(fontSize: 12, color: context.colors.secondaryText),
            ),
          ),
        ],
      ),
    );
  }
}
