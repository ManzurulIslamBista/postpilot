import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/tool_dialog.dart';
import '../../response_tools/domain/services/json_diff.dart';
import '../domain/entities/matrix_grid.dart';
import '../domain/services/matrix_analysis.dart';
import '../domain/services/matrix_body.dart';
import '../domain/services/matrix_comparator.dart';

/// One cell's response beside the first column's: the status of each, the fields that differ (volatile ones left out),
/// and the two bodies side by side with the lines that differ marked.
class MatrixCellDiffDialog extends StatelessWidget {
  final MatrixRowVerdict row;
  final int column;
  final MatrixCompareMode mode;

  const MatrixCellDiffDialog({super.key, required this.row, required this.column, required this.mode});

  static Future<void> show(BuildContext context, {required MatrixRowVerdict row, required int column, required MatrixCompareMode mode}) =>
      ToolDialog.show<void>(context, (_) => MatrixCellDiffDialog(row: row, column: column, mode: mode));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reference = row.cells.first;
    final chosen = row.cells[column];
    final comparison = chosen.comparison ?? MatrixComparator.compare(reference.cell, chosen.cell, mode: mode);
    final left = _Side(reference.column.label, reference.cell, mode);
    final right = _Side(chosen.column.label, chosen.cell, mode);
    final same = column == 0;
    return ToolDialog(
      icon: Icons.compare_arrows,
      title: row.row.title,
      subtitle: same ? '${chosen.column.label} (the reference)' : '${chosen.column.label} against ${reference.column.label}',
      width: 980,
      height: 700,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (same)
              const InfoBanner(kind: BannerKind.info, message: 'This is the first column, the one the others are compared with.')
            else if (!comparison.differs)
              const InfoBanner(kind: BannerKind.success, message: 'Same status and same body (ids, dates and tokens that change on every call are ignored).')
            else
              InfoBanner(kind: BannerKind.warning, title: 'Differs', message: comparison.reasons.join('\n')),
            if (chosen.isUnexpected) ...[
              const SizedBox(height: 8),
              InfoBanner(kind: BannerKind.error, message: chosen.unexpected!),
            ],
            if (comparison.changes.isNotEmpty) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: Container(
                  decoration: BoxDecoration(color: colors.appBackground, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: comparison.changes.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: colors.borderSubtle),
                    itemBuilder: (_, i) => _ChangeRow(change: comparison.changes[i]),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final leftPane = _BodyPane(side: left, other: right, key: const ValueKey('left'));
                  final rightPane = _BodyPane(side: right, other: left, key: const ValueKey('right'));
                  // Side by side when there is room, one above the other on a phone.
                  if (box.maxWidth >= 640) {
                    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: leftPane), const SizedBox(width: 10), Expanded(child: rightPane)]);
                  }
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: leftPane), const SizedBox(height: 10), Expanded(child: rightPane)]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What one side of the comparison shows.
final class _Side {
  final String label;
  final MatrixCell? cell;
  final MatrixCompareMode mode;

  _Side(this.label, this.cell, this.mode);

  String get title {
    final c = cell;
    if (c == null) return '$label: not run';
    if (c.error != null) return '$label: error';
    if (c.note != null) return '$label: not sent';
    return '$label: ${c.status} · ${c.durationMs ?? 0} ms';
  }

  /// The text shown: the body, pretty-printed when it is JSON (only its shape in structure mode), or why there is none.
  List<String> get lines => _lines(display: true);

  /// The same lines with volatile values (or all values, in structure mode) replaced: the lines are compared by these,
  /// so an id that changes on every call is not marked.
  List<String> get comparable => _lines(display: false);

  List<String> _lines({required bool display}) {
    final c = cell;
    if (c == null) return const ['Not run.'];
    if (c.error != null) return [c.error!];
    if (c.note != null) return [c.note!];
    final body = MatrixBody.of(c);
    switch (body.kind) {
      case MatrixBodyKind.none:
        return const ['(empty body)'];
      case MatrixBodyKind.text:
        return const LineSplitter().convert(body.text);
      case MatrixBodyKind.json:
        final shape = mode == MatrixCompareMode.structure;
        final doc = display && !shape ? body.json : body.comparable(mode);
        return const LineSplitter().convert(const JsonEncoder.withIndent('  ').convert(doc));
    }
  }
}

class _BodyPane extends StatelessWidget {
  /// The most lines drawn; a response can be far larger than a screen is worth.
  static const maxLines = 4000;

  final _Side side;
  final _Side other;
  const _BodyPane({super.key, required this.side, required this.other});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lines = side.lines;
    final compare = side.comparable;
    // Lines the other side does not have, by their comparable form. Only meaningful when both are real bodies.
    final theirs = other.comparable.map((l) => l.trim()).toSet();
    final marking = side.cell?.hasResponse == true && other.cell?.hasResponse == true;
    final shown = lines.length > maxLines ? maxLines : lines.length;
    final mono = context.textStyles.mono.copyWith(fontSize: 12);
    return Container(
      decoration: BoxDecoration(color: colors.appBackground, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: colors.sidebarBackground.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(side.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textStyles.body.copyWith(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: shown + (lines.length > shown ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= shown) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('… ${lines.length - shown} more lines', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                  );
                }
                final differs = marking && i < compare.length && !theirs.contains(compare[i].trim());
                return Container(
                  color: differs ? colors.statusWarning.withValues(alpha: 0.16) : null,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SelectableText(lines[i], style: mono),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  final JsonChange change;
  const _ChangeRow({required this.change});

  String _short(Object? v) {
    final s = jsonEncode(v);
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (sign, color) = switch (change.kind) {
      JsonChangeKind.added => ('+', colors.statusSuccess),
      JsonChangeKind.removed => ('−', colors.statusError),
      JsonChangeKind.changed => ('~', colors.statusWarning),
    };
    final mono = context.textStyles.mono.copyWith(fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 18, child: Text(sign, style: mono.copyWith(color: color, fontWeight: FontWeight.w800))),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: change.path, style: mono.copyWith(color: colors.syntaxKey, fontWeight: FontWeight.w600)),
                if (change.kind != JsonChangeKind.added) TextSpan(text: '   ${_short(change.before)}', style: mono.copyWith(color: colors.statusError)),
                if (change.kind == JsonChangeKind.changed) TextSpan(text: '  →', style: mono.copyWith(color: colors.secondaryText)),
                if (change.kind != JsonChangeKind.removed) TextSpan(text: '  ${_short(change.after)}', style: mono.copyWith(color: colors.statusSuccess)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
