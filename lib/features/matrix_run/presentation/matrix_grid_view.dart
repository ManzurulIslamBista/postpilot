import 'package:flutter/material.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/method_badge.dart';
import '../domain/services/matrix_analysis.dart';
import '../domain/services/matrix_body.dart';

/// The result grid: a row per request, a column per matrix column. A cell shows the status, the time and a short
/// fingerprint of the body; a row where some column differs from the first is tinted, and a cell that is not what was
/// expected says so. Tapping a cell opens its response against the first column's.
///
/// The grid scrolls sideways when the columns do not fit, so it never overflows a narrow window.
class MatrixGridView extends StatefulWidget {
  static const requestWidth = 210.0;
  static const cellWidth = 190.0;

  final MatrixAnalysis analysis;

  /// The column the run is busy with; its empty cells show a spinner. Null when the run is over.
  final int? runningColumn;
  final void Function(MatrixRowVerdict row, int column) onOpenCell;
  final void Function(String rowKey, String columnKey, MatrixExpect expect) onExpect;
  final void Function(String columnKey, MatrixExpect expect) onExpectColumn;

  const MatrixGridView({
    super.key,
    required this.analysis,
    required this.runningColumn,
    required this.onOpenCell,
    required this.onExpect,
    required this.onExpectColumn,
  });

  @override
  State<MatrixGridView> createState() => _MatrixGridViewState();
}

class _MatrixGridViewState extends State<MatrixGridView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analysis = widget.analysis;
    final width = MatrixGridView.requestWidth + MatrixGridView.cellWidth * analysis.grid.columns.length;
    return LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width < constraints.maxWidth ? constraints.maxWidth : width,
            height: constraints.maxHeight,
            child: Column(
              children: [
                _HeaderRow(analysis: analysis, onExpectColumn: widget.onExpectColumn),
                Divider(height: 1, color: context.colors.border),
                Expanded(
                  child: ListView.builder(
                    itemCount: analysis.rows.length,
                    itemBuilder: (context, i) => _GridRow(
                      verdict: analysis.rows[i],
                      mode: analysis.mode,
                      runningColumn: widget.runningColumn,
                      onOpenCell: widget.onOpenCell,
                      onExpect: widget.onExpect,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final MatrixAnalysis analysis;
  final void Function(String columnKey, MatrixExpect expect) onExpectColumn;
  const _HeaderRow({required this.analysis, required this.onExpectColumn});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      color: colors.sidebarBackground.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: MatrixGridView.requestWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('REQUEST', style: context.textStyles.caption.copyWith(color: colors.secondaryText, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            ),
          ),
          for (final (i, column) in analysis.grid.columns.indexed)
            SizedBox(
              width: MatrixGridView.cellWidth,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: i == 0 ? '${column.label} (the reference the other columns are compared with)' : column.label,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: column.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                              if (i == 0) TextSpan(text: '  reference', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.body,
                        ),
                      ),
                    ),
                    PopupMenuButton<MatrixExpect>(
                      tooltip: 'What is expected of ${column.label}',
                      padding: EdgeInsets.zero,
                      onSelected: (e) => onExpectColumn(column.key, e),
                      child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.rule, size: 18, color: colors.secondaryText)),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: MatrixExpect.allow, child: Text('Expect access on every request')),
                        PopupMenuItem(value: MatrixExpect.deny, child: Text('Expect denial on every request')),
                        PopupMenuItem(value: MatrixExpect.none, child: Text('Clear the expectations')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GridRow extends StatelessWidget {
  final MatrixRowVerdict verdict;
  final MatrixCompareMode mode;
  final int? runningColumn;
  final void Function(MatrixRowVerdict row, int column) onOpenCell;
  final void Function(String rowKey, String columnKey, MatrixExpect expect) onExpect;

  const _GridRow({required this.verdict, required this.mode, required this.runningColumn, required this.onOpenCell, required this.onExpect});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final row = verdict.row;
    final differs = verdict.differs;
    return Container(
      decoration: BoxDecoration(
        color: differs ? colors.statusWarning.withValues(alpha: 0.09) : null,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: MatrixGridView.requestWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        MethodBadge(method: row.method),
                        const SizedBox(width: 8),
                        Expanded(child: Text(row.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.textStyles.body.copyWith(fontWeight: FontWeight.w600))),
                      ],
                    ),
                    if (row.folder.isNotEmpty)
                      Text(row.folder, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                    if (differs)
                      Tooltip(
                        message: verdict.reasons.join('\n'),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('DIFFERS', style: TextStyle(color: colors.statusWarning, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.6)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            for (final (i, cell) in verdict.cells.indexed)
              SizedBox(
                width: MatrixGridView.cellWidth,
                child: _CellTile(
                  verdict: cell,
                  isReference: i == 0,
                  mode: mode,
                  running: runningColumn == i && cell.cell == null,
                  onOpen: () => onOpenCell(verdict, i),
                  onExpect: (e) => onExpect(row.key, cell.column.key, e),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CellTile extends StatelessWidget {
  final MatrixCellVerdict verdict;
  final bool isReference;
  final MatrixCompareMode mode;
  final bool running;
  final VoidCallback onOpen;
  final void Function(MatrixExpect expect) onExpect;

  const _CellTile({required this.verdict, required this.isReference, required this.mode, required this.running, required this.onOpen, required this.onExpect});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cell = verdict.cell;
    final differs = verdict.differs;
    final unexpected = verdict.isUnexpected;
    final mono = context.textStyles.mono.copyWith(fontSize: 11, color: colors.secondaryText);

    final Widget body;
    if (cell == null) {
      body = running
          ? const Align(alignment: Alignment.centerLeft, child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
          : Text('not run', style: context.textStyles.caption.copyWith(color: colors.secondaryText));
    } else if (cell.error != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ERR', style: TextStyle(color: colors.statusError, fontWeight: FontWeight.w800, fontSize: 13)),
          Text(cell.error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: mono),
        ],
      );
    } else if (cell.note != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('not sent', style: TextStyle(color: colors.statusWarning, fontWeight: FontWeight.w700, fontSize: 13)),
          Text(cell.note!, maxLines: 2, overflow: TextOverflow.ellipsis, style: mono),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${cell.status}', style: TextStyle(color: colors.forStatus(cell.status!), fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(width: 8),
              Flexible(child: Text('${cell.durationMs ?? 0} ms', overflow: TextOverflow.ellipsis, style: context.textStyles.caption.copyWith(color: colors.secondaryText))),
            ],
          ),
          Text(MatrixBody.fingerprint(cell, mode), maxLines: 1, overflow: TextOverflow.ellipsis, style: mono),
        ],
      );
    }

    final expectIcon = switch (verdict.expect) {
      MatrixExpect.allow => Icons.lock_open_outlined,
      MatrixExpect.deny => Icons.block,
      MatrixExpect.none => null,
    };

    return Container(
      decoration: BoxDecoration(
        color: unexpected ? colors.statusError.withValues(alpha: 0.10) : null,
        border: Border(left: BorderSide(color: unexpected ? colors.statusError : (differs ? colors.statusWarning : Colors.transparent), width: 3)),
      ),
      child: InkWell(
        onTap: cell == null ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 8, 2, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    body,
                    if (unexpected)
                      Tooltip(
                        message: verdict.unexpected!,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            verdict.unexpected!.startsWith('Unexpected access') ? 'Unexpected access' : 'Unexpected',
                            style: TextStyle(color: colors.statusError, fontWeight: FontWeight.w800, fontSize: 11),
                          ),
                        ),
                      )
                    else if (differs)
                      Tooltip(
                        message: verdict.comparison!.reasons.join('\n'),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(verdict.comparison!.reasons.first, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.statusWarning, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<MatrixExpect>(
                tooltip: 'What is expected here',
                padding: EdgeInsets.zero,
                onSelected: onExpect,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(expectIcon ?? Icons.more_vert, size: 16, color: expectIcon == null ? colors.secondaryText.withValues(alpha: 0.6) : colors.mainAccent),
                ),
                itemBuilder: (_) => [
                  for (final e in MatrixExpect.values)
                    CheckedPopupMenuItem(value: e, checked: verdict.expect == e, child: Text(e.label)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
