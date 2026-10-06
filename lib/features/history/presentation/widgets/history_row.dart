import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/method_badge.dart';
import '../../domain/entities/history_entry_entity.dart';
import 'highlighted_text.dart';
import 'history_format.dart';

/// "Today · 12" above the entries of one day.
class HistoryDayHeaderRow extends StatelessWidget {
  final String label;
  final int count;
  const HistoryDayHeaderRow({super.key, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: context.textStyles.caption.copyWith(
              color: colors.secondaryText,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(width: 8),
          Text('$count', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
          const SizedBox(width: 10),
          Expanded(child: Divider(height: 1, color: colors.borderSubtle)),
        ],
      ),
    );
  }
}

/// One entry of the list: method, URL (with the search marked), status, time, duration and size.
class HistoryEntryRow extends StatelessWidget {
  final HistoryEntryEntity entry;

  /// The lower-cased search text to mark; empty marks nothing.
  final String needle;
  final bool selected;

  /// "Select" mode: a checkbox in front.
  final bool selecting;
  final bool checked;
  final VoidCallback onTap;

  const HistoryEntryRow({
    super.key,
    required this.entry,
    required this.needle,
    required this.selected,
    required this.selecting,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);
    final meta = entry.meta;
    final size = entrySize(entry);
    final name = meta?.requestName;
    final where = [?meta?.collectionName, ?name].join(' › ');
    return Material(
      color: selected ? colors.mainAccent.withValues(alpha: 0.10) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: checked,
                      visualDensity: VisualDensity.compact,
                      onChanged: (_) => onTap(),
                    ),
                  ),
                ),
              Padding(padding: const EdgeInsets.only(top: 1), child: MethodBadge(method: entry.method, width: 44)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HighlightedText(text: entry.url, query: needle, style: context.textStyles.body),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        HistoryStatusChip(entry: entry),
                        Text(formatClock(entry.sentAt), style: caption),
                        if (entry.durationMs != null) Text(formatDuration(entry.durationMs!), style: caption),
                        if (size != null) Text(size, style: caption),
                      ],
                    ),
                    if (where.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      HighlightedText(text: where, query: needle, style: caption),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
