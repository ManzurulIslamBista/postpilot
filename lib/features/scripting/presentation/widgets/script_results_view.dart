import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/script_run_result.dart';

/// Compact pass/fail readout shown after a send: one line per assertion and
/// per extracted variable. Renders nothing when the request has no scripts.
class ScriptResultsView extends StatelessWidget {
  final ScriptRunResult result;
  const ScriptResultsView({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    if (result.isEmpty) return const SizedBox.shrink();

    final color = result.hasFailures ? context.colors.statusError : context.colors.statusSuccess;
    final savedCount = result.extracted.where((e) => e.ok).length;
    final summary = [
      if (result.assertions.isNotEmpty) '${result.passedCount}/${result.assertions.length} tests passed',
      if (result.extracted.isNotEmpty) '$savedCount/${result.extracted.length} variables saved',
    ].join(' · ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: context.colors.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(result.hasFailures ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 16),
              const SizedBox(width: 6),
              Text(summary, style: context.textStyles.body.copyWith(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final a in result.assertions) _ResultRow(passed: a.passed, label: a.name, detail: a.actual),
                for (final e in result.extracted)
                  _ResultRow(
                    passed: e.ok,
                    label: '{{${e.key}}} → ${e.scope.label.toLowerCase()}',
                    detail: e.error ?? e.value ?? '',
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
  const _ResultRow({required this.passed, required this.label, required this.detail});

  @override
  Widget build(BuildContext context) {
    final color = passed ? context.colors.statusSuccess : context.colors.statusError;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(passed ? Icons.check : Icons.close, color: color, size: 14),
          const SizedBox(width: 6),
          Expanded(flex: 3, child: Text(label, style: context.textStyles.caption, overflow: TextOverflow.ellipsis)),
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
