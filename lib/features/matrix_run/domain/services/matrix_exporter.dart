import 'package:csv/csv.dart';
import '../entities/matrix_grid.dart';
import 'matrix_analysis.dart';
import 'matrix_body.dart';

/// A matrix run as text: a Markdown table to paste into an issue or a pull request, a CSV for a spreadsheet, and a
/// plain listing for a terminal. They carry statuses, times and body fingerprints, never a response body, a header
/// or a variable value.
abstract final class MatrixExporter {
  /// One cell in a sentence: `200 · 45 ms · {3 keys} #4f2a9c`, `ERR connection refused`, `not sent: ...`.
  static String cellText(MatrixCell? cell, MatrixCompareMode mode, {int errorChars = 60}) {
    if (cell == null) return 'not run';
    if (cell.error != null) return 'ERR ${_short(cell.error!, errorChars)}';
    if (cell.note != null) return 'not sent: ${_short(cell.note!, errorChars)}';
    return '${cell.status} · ${cell.durationMs ?? 0} ms · ${MatrixBody.fingerprint(cell, mode)}';
  }

  static String _short(String text, int max) {
    final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return line.length > max ? '${line.substring(0, max)}…' : line;
  }

  static String _summary(MatrixAnalysis a) {
    final total = a.rows.length;
    final parts = [
      a.differingRows == 0 ? 'No request differs between the columns.' : '${a.differingRows} of $total request${total == 1 ? '' : 's'} differ.',
      if (a.unexpectedCells > 0) '${a.unexpectedCells} unexpected result${a.unexpectedCells == 1 ? '' : 's'}.',
    ];
    return parts.join(' ');
  }

  // --- Markdown --------------------------------------------------------------------------------

  static String _mdCell(String text) => text.replaceAll('|', r'\|').replaceAll(RegExp(r'[\r\n]+'), ' ');

  /// A Markdown table: a row per request, a column per matrix column, a last column that says whether the row differs
  /// from the first column; the unexpected results are listed under it.
  static String markdown(MatrixAnalysis analysis, {String title = 'Matrix run'}) {
    final grid = analysis.grid;
    final b = StringBuffer()
      ..writeln('## ${_mdCell(title)}')
      ..writeln()
      ..writeln('Compared: ${analysis.mode.label.toLowerCase()}. Columns: ${grid.columns.map((c) => _mdCell(c.label)).join(', ')}; '
          'the first column is the reference.')
      ..writeln()
      ..writeln('| Request | ${grid.columns.map((c) => _mdCell(c.label)).join(' | ')} | Result |')
      ..writeln('| --- | ${grid.columns.map((_) => '---').join(' | ')} | --- |');
    for (final verdict in analysis.rows) {
      final cells = [
        for (final c in verdict.cells)
          _mdCell('${cellText(c.cell, analysis.mode)}${c.isUnexpected ? ' (UNEXPECTED)' : ''}'),
      ];
      final result = verdict.differs ? 'DIFFERS: ${_mdCell(verdict.reasons.join('; '))}' : 'same';
      b.writeln('| ${_mdCell(_rowTitle(verdict.row))} | ${cells.join(' | ')} | $result |');
    }
    final unexpected = [
      for (final v in analysis.rows)
        for (final c in v.cells)
          if (c.isUnexpected) '- ${_mdCell(_rowTitle(v.row))} in ${_mdCell(c.column.label)}: ${c.unexpected}',
    ];
    if (unexpected.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Unexpected results:')
        ..writeln(unexpected.join('\n'));
    }
    b
      ..writeln()
      ..writeln(_summary(analysis));
    return b.toString();
  }

  static String _rowTitle(MatrixRow row) => row.folder.isEmpty ? row.title : '${row.folder} / ${row.title}';

  // --- CSV -------------------------------------------------------------------------------------

  static final _formulaStart = RegExp(r'^[=+\-@\t\r]');

  /// Names and messages come from imported collections and from servers, so a leading `=`, `+`, `-` or `@` would run as
  /// a formula when the CSV is opened in a spreadsheet.
  static String _csvCell(String text) => _formulaStart.hasMatch(text) ? "'$text" : text;

  /// One line per request: its name, method and folder, then status, time and body fingerprint for every column, and
  /// whether it differs, why, and which results were unexpected.
  static String csv(MatrixAnalysis analysis) {
    final grid = analysis.grid;
    return Csv(lineDelimiter: '\n').encode([
      [
        'request',
        'method',
        'folder',
        for (final c in grid.columns) ...['${c.label} status', '${c.label} ms', '${c.label} body'],
        'differs',
        'differences',
        'unexpected',
      ],
      for (final verdict in analysis.rows)
        [
          _csvCell(verdict.row.name),
          verdict.row.method,
          _csvCell(verdict.row.folder),
          for (final c in verdict.cells) ..._csvCells(c.cell, analysis.mode),
          verdict.differs ? 'yes' : 'no',
          _csvCell(verdict.reasons.join('; ')),
          _csvCell([for (final c in verdict.cells) if (c.isUnexpected) '${c.column.label}: ${c.unexpected}'].join('; ')),
        ],
    ]);
  }

  static List<Object> _csvCells(MatrixCell? cell, MatrixCompareMode mode) {
    if (cell == null) return const ['', '', 'not run'];
    if (cell.error != null) return ['', cell.durationMs ?? '', _csvCell('ERR ${_short(cell.error!, 200)}')];
    if (cell.note != null) return ['', '', _csvCell('not sent: ${_short(cell.note!, 200)}')];
    return [cell.status!, cell.durationMs ?? '', MatrixBody.fingerprint(cell, mode)];
  }

  // --- Terminal --------------------------------------------------------------------------------

  /// A plain listing for a terminal: each request, then a line per column, with `<- differs` on the columns that differ
  /// from the first one.
  static String text(MatrixAnalysis analysis, {String title = 'Matrix run'}) {
    final width = analysis.grid.columns.fold<int>(0, (w, c) => c.label.length > w ? c.label.length : w);
    final b = StringBuffer()
      ..writeln('$title (${analysis.mode.label.toLowerCase()}; the first column is the reference)')
      ..writeln();
    for (final verdict in analysis.rows) {
      b.writeln(_rowTitle(verdict.row).replaceAll(RegExp(r'[\r\n]+'), ' '));
      for (final c in verdict.cells) {
        final flags = [
          if (c.differs) 'differs: ${c.comparison!.reasons.join(', ')}',
          if (c.isUnexpected) c.unexpected!,
        ];
        b.writeln('  ${c.column.label.padRight(width)}  ${cellText(c.cell, analysis.mode)}${flags.isEmpty ? '' : '   <- ${flags.join('; ')}'}');
      }
    }
    b
      ..writeln()
      ..writeln(_summary(analysis));
    return b.toString();
  }
}
