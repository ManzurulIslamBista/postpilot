import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../domain/services/model_schema_diff.dart';

/// What changed in the generated classes since the version Dart Studio remembers: per class, every field added, removed,
/// renamed (suspected), retyped or made (non-)nullable, each marked breaking or not, with the migration notes to copy.
class ModelDiffPanel extends StatelessWidget {
  final SchemaDiff diff;

  /// Called by "Remember this version"; the button is left out without it.
  final VoidCallback? onRemember;
  final double maxHeight;

  const ModelDiffPanel({super.key, required this.diff, this.onRemember, this.maxHeight = 260});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final styles = context.textStyles;
    final breaking = diff.breaking.length;
    final headline = diff.isEmpty
        ? 'The classes are the same as in the remembered version.'
        : '${diff.changes.length} change${diff.changes.length == 1 ? '' : 's'} since the remembered version: '
            '$breaking breaking, ${diff.changes.length - breaking} non-breaking';
    final color = diff.isEmpty ? colors.statusSuccess : (diff.hasBreaking ? colors.statusError : colors.statusWarning);
    return Container(
      key: const ValueKey('model-diff-panel'),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(diff.isEmpty ? Icons.check_circle_outline : Icons.compare_arrows, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(headline, style: styles.body.copyWith(fontWeight: FontWeight.w700, color: color))),
            ],
          ),
          // Below the headline and wrapping, so two buttons fit a phone as well as a desktop dialog.
          if (!diff.isEmpty || onRemember != null)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (!diff.isEmpty)
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(text: diff.migrationNotes())),
                    icon: const Icon(Icons.copy_all_outlined, size: 16),
                    label: const Text('Copy migration notes'),
                  ),
                if (onRemember != null)
                  TextButton.icon(
                    onPressed: onRemember,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                    label: const Text('Remember this version'),
                  ),
              ],
            ),
          if (!diff.isEmpty) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: ListView(
                primary: false,
                shrinkWrap: true,
                children: [
                  for (final entry in diff.byClass.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 2),
                      child: Text(entry.key, style: styles.mono.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    for (final change in entry.value)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            StatusChip(
                              label: change.breaking ? 'Breaking' : 'Safe',
                              color: change.breaking ? colors.statusError : colors.statusSuccess,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${change.kind.label}: ${change.summary}', style: styles.body),
                                  Text(change.advice, style: styles.caption.copyWith(color: colors.secondaryText)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
