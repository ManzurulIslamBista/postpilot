import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/cleanup_entry.dart';

/// One created record (or the records of one create) in a list: what made it, what will undo it, where it stands and,
/// when something went wrong, why. [leading] is a checkbox in the runner's preview; [actions] are the buttons of the
/// ledger dialog, wrapped under the text so a narrow window never squeezes the words into a sliver.
class CleanupEntryTile extends StatelessWidget {
  final CleanupEntry entry;
  final bool working;
  final Widget? leading;
  final List<Widget> actions;

  const CleanupEntryTile({super.key, required this.entry, this.working = false, this.leading, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (icon, color) = switch (entry.state) {
      CleanupState.pending => (Icons.radio_button_unchecked, colors.secondaryText),
      CleanupState.deleted => (Icons.check_circle_outline, colors.statusSuccess),
      CleanupState.failed => (Icons.error_outline, colors.statusError),
      CleanupState.skipped => (Icons.remove_circle_outline, colors.statusWarning),
    };
    final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);
    final reason = entry.reason;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: entry.state == CleanupState.failed ? colors.statusError.withValues(alpha: 0.5) : colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ?leading,
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: working
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: colors.mainAccent))
                    : Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.ids.isEmpty ? entry.requestName : '${entry.requestName}  ${entry.idsText}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(entry.plan.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.textStyles.mono.copyWith(fontSize: 11.5)),
                    Text(
                      [
                        entry.environment ?? 'No environment',
                        formatClock(entry.createdAt),
                        working ? 'Deleting…' : entry.state.label,
                      ].join(' · '),
                      style: caption,
                    ),
                    if (reason != null && reason.isNotEmpty)
                      Text(
                        reason,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: caption.copyWith(color: entry.state == CleanupState.failed ? colors.statusError : colors.statusWarning),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
              ),
            ),
        ],
      ),
    );
  }
}

/// `09:05`, the local time of day.
String formatClock(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
