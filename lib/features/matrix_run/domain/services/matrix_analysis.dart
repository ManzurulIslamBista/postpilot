import '../entities/matrix_column.dart';
import '../entities/matrix_grid.dart';
import 'matrix_body.dart';
import 'matrix_comparator.dart';

/// What a person expects a column to get for a request: the permission matrix ("admin may, user may not").
enum MatrixExpect {
  none,
  allow,
  deny;

  String get label => switch (this) {
        MatrixExpect.none => 'No expectation',
        MatrixExpect.allow => 'Expect access',
        MatrixExpect.deny => 'Expect denial',
      };
}

/// Judges a cell against an expectation. Access is a 2xx answer, denial is 401 or 403; anything else (404, 500, no
/// answer) is neither, and is reported as unexpected whichever expectation is set.
abstract final class MatrixAccess {
  static bool isAllowed(MatrixCell? cell) => cell?.status != null && cell!.status! >= 200 && cell.status! < 300;

  static bool isDenied(MatrixCell? cell) => cell?.status == 401 || cell?.status == 403;

  /// Why [cell] is not what [expect] says, or null when it is (or nothing can be said: no expectation, or a request
  /// that was not sent).
  static String? unexpected(MatrixExpect expect, MatrixCell? cell) {
    if (expect == MatrixExpect.none || cell == null || cell.note != null) return null;
    if (cell.error != null) {
      return expect == MatrixExpect.allow ? 'Unexpected: no answer, access was expected' : 'Unexpected: no answer, denial was expected';
    }
    final status = cell.status!;
    if (expect == MatrixExpect.allow) {
      if (isAllowed(cell)) return null;
      return isDenied(cell) ? 'Unexpected access: denied ($status) where access was expected' : 'Unexpected: HTTP $status, access was expected';
    }
    if (isDenied(cell)) return null;
    return isAllowed(cell) ? 'Unexpected access: allowed ($status) where denial was expected' : 'Unexpected: HTTP $status, denial was expected';
  }
}

/// One cell, judged: how it differs from the first column and whether it is what was expected.
final class MatrixCellVerdict {
  final MatrixColumn column;
  final MatrixCell? cell;

  /// Against the first column; null for the first column itself.
  final CellComparison? comparison;
  final MatrixExpect expect;

  /// Why the cell is not what [expect] says; null when it is.
  final String? unexpected;

  const MatrixCellVerdict(this.column, this.cell, this.comparison, this.expect, this.unexpected);

  bool get differs => comparison?.differs ?? false;
  bool get isUnexpected => unexpected != null;
}

/// One request, judged across its columns.
final class MatrixRowVerdict {
  final MatrixRow row;
  final List<MatrixCellVerdict> cells;

  const MatrixRowVerdict(this.row, this.cells);

  /// Some column got something other than the first column did.
  bool get differs => cells.any((c) => c.differs);
  bool get hasUnexpected => cells.any((c) => c.isUnexpected);

  /// `Prod: status 200 vs 403, body: 2 fields differ`, one entry per differing column.
  List<String> get reasons => [
        for (final c in cells)
          if (c.differs) '${c.column.label}: ${c.comparison!.reasons.join(', ')}',
      ];
}

/// A finished (or running) grid, judged: which rows differ and which cells are unexpected. Derived, so switching the
/// compare mode or setting an expectation just builds it again.
final class MatrixAnalysis {
  final MatrixGrid grid;
  final MatrixCompareMode mode;
  final List<MatrixRowVerdict> rows;

  const MatrixAnalysis(this.grid, this.mode, this.rows);

  int get differingRows => rows.where((r) => r.differs).length;
  int get unexpectedCells => rows.fold(0, (n, r) => n + r.cells.where((c) => c.isUnexpected).length);
  bool get hasDifferences => differingRows > 0;

  /// [expectations]: row key, then column key, to what is expected there.
  static MatrixAnalysis of(
    MatrixGrid grid, {
    MatrixCompareMode mode = MatrixCompareMode.full,
    Map<String, Map<String, MatrixExpect>> expectations = const {},
  }) {
    final rows = <MatrixRowVerdict>[];
    for (final row in grid.rows) {
      final base = row.cells.isEmpty ? null : row.cells.first;
      final verdicts = <MatrixCellVerdict>[];
      for (final (i, column) in grid.columns.indexed) {
        final cell = row.cells[i];
        final expect = expectations[row.key]?[column.key] ?? MatrixExpect.none;
        verdicts.add(MatrixCellVerdict(
          column,
          cell,
          // A cell the run has not got to (or never will, once stopped) is not a difference.
          i == 0 || base == null || cell == null ? null : MatrixComparator.compare(base, cell, mode: mode),
          expect,
          MatrixAccess.unexpected(expect, cell),
        ));
      }
      rows.add(MatrixRowVerdict(row, verdicts));
    }
    return MatrixAnalysis(grid, mode, rows);
  }
}
