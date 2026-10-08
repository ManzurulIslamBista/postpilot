import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/preview_rows.dart';

/// One line of the preview list. [onTick] is null where the occurrences cannot be unticked one by one (a rename takes
/// them all or none); then no checkboxes are drawn.
class PreviewTile extends StatelessWidget {
  final PreviewRow row;
  final bool Function(String editId) isTicked;
  final void Function(Iterable<String> editIds, bool ticked)? onTick;

  const PreviewTile({super.key, required this.row, required this.isTicked, this.onTick});

  /// A key that follows the occurrence, not its position, so a tile keeps its state when the list above it changes.
  static Key keyFor(PreviewRow row, int index) => switch (row) {
    final EditRow edit => ValueKey(edit.edit.id),
    GroupRow() || DeletionRow() => ValueKey('row:$index'),
  };

  @override
  Widget build(BuildContext context) => switch (row) {
    final GroupRow group => _GroupTile(row: group, isTicked: isTicked, onTick: onTick),
    final EditRow edit => _EditTile(row: edit, isTicked: isTicked, onTick: onTick),
    final DeletionRow deletion => _DeletionTile(row: deletion),
  };
}

const _indent = 16.0;

class _TickBox extends StatelessWidget {
  final bool? value;
  final bool tristate;
  final ValueChanged<bool?> onChanged;
  const _TickBox({required this.value, required this.onChanged, this.tristate = false});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 32,
    height: 32,
    child: Checkbox(
      value: value,
      tristate: tristate,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onChanged: onChanged,
    ),
  );
}

class _GroupTile extends StatelessWidget {
  final GroupRow row;
  final bool Function(String) isTicked;
  final void Function(Iterable<String>, bool)? onTick;
  const _GroupTile({required this.row, required this.isTicked, required this.onTick});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ids = row.editIds;
    final ticked = ids.where(isTicked).length;
    final icon = row.isRequest
        ? Icons.http
        : row.depth == 0
        ? Icons.inventory_2_outlined
        : row.isLeaf
        ? Icons.tune
        : Icons.folder_outlined;
    return Container(
      margin: EdgeInsets.only(top: row.depth == 0 ? 8 : 0),
      padding: EdgeInsets.fromLTRB(8 + row.depth * _indent, 4, 8, 4),
      decoration: BoxDecoration(
        color: colors.sidebarBackground.withValues(alpha: row.depth == 0 ? 0.9 : 0.45),
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          if (onTick != null && ids.isNotEmpty)
            _TickBox(
              tristate: true,
              value: ticked == ids.length ? true : (ticked == 0 ? false : null),
              onChanged: (_) => onTick!(ids, ticked != ids.length),
            )
          else
            const SizedBox(width: 8),
          Icon(icon, size: 16, color: colors.secondaryText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              row.title,
              style: context.textStyles.body.copyWith(fontWeight: row.isLeaf ? FontWeight.w600 : FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (ids.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text('${ids.length}', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
          ],
        ],
      ),
    );
  }
}

class _EditTile extends StatelessWidget {
  final EditRow row;
  final bool Function(String) isTicked;
  final void Function(Iterable<String>, bool)? onTick;
  const _EditTile({required this.row, required this.isTicked, required this.onTick});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final edit = row.edit;
    final ticked = isTicked(edit.id);
    final secret = row.change.secret;
    final mono = context.textStyles.mono.copyWith(fontSize: 12, color: ticked || onTick == null ? null : colors.secondaryText);
    return InkWell(
      onTap: onTick == null ? null : () => onTick!([edit.id], !ticked),
      child: Padding(
        padding: EdgeInsets.fromLTRB(8 + (row.depth - 1) * _indent + 8, 4, 8, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onTick != null) _TickBox(value: ticked, onChanged: (v) => onTick!([edit.id], v ?? false)) else const SizedBox(width: 8),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (row.first)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 2),
                      child: Row(
                        children: [
                          if (secret) ...[Icon(Icons.lock_outline, size: 12, color: colors.statusWarning), const SizedBox(width: 4)],
                          Expanded(
                            child: Text(
                              secret ? '${row.change.label} (secret, hidden)' : row.change.label,
                              style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text.rich(
                    TextSpan(
                      style: mono,
                      children: [
                        TextSpan(text: edit.lead),
                        TextSpan(
                          text: edit.shownBefore,
                          style: TextStyle(
                            backgroundColor: colors.statusError.withValues(alpha: 0.16),
                            color: colors.statusError,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        TextSpan(
                          text: edit.shownAfter,
                          style: TextStyle(backgroundColor: colors.statusSuccess.withValues(alpha: 0.16), color: colors.statusSuccess),
                        ),
                        TextSpan(text: edit.tail),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeletionTile extends StatelessWidget {
  final DeletionRow row;
  const _DeletionTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final d = row.deletion;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.delete_outline, size: 16, color: colors.statusError),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: context.textStyles.body,
                children: [
                  TextSpan(text: d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' in ${d.where}', style: TextStyle(color: colors.secondaryText)),
                  TextSpan(text: '   value: ${d.shownValue}', style: context.textStyles.mono.copyWith(fontSize: 12)),
                ],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
