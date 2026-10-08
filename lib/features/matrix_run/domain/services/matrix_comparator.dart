import '../../../response_tools/domain/services/json_diff.dart';
import '../entities/matrix_grid.dart';
import 'matrix_body.dart';

/// How one cell differs from the cell it is compared with.
final class CellComparison {
  /// Both answered, with another status code.
  final bool statusDiffers;

  /// Both answered and the bodies differ (after ignoring volatile fields, see [MatrixBody.neutralise]).
  final bool bodyDiffers;

  /// One answered and the other did not, or they ended in different ways (an error against a skipped request).
  final bool outcomeDiffers;

  /// The field-level differences when both bodies are JSON; empty otherwise.
  final List<JsonChange> changes;

  /// Short words for a grid or a report: `status 200 vs 403`, `body: 3 fields differ`, `error vs 200`.
  final List<String> reasons;

  const CellComparison({
    this.statusDiffers = false,
    this.bodyDiffers = false,
    this.outcomeDiffers = false,
    this.changes = const [],
    this.reasons = const [],
  });

  static const same = CellComparison();

  bool get differs => statusDiffers || bodyDiffers || outcomeDiffers;
}

/// Compares what two columns got for the same request. Pure Dart, shared by the app and the command line.
abstract final class MatrixComparator {
  /// [other] against [base] (the first column). A cell that is `null` was not run.
  static CellComparison compare(MatrixCell? base, MatrixCell? other, {MatrixCompareMode mode = MatrixCompareMode.full}) {
    final baseAnswered = base?.hasResponse ?? false;
    final otherAnswered = other?.hasResponse ?? false;
    if (!baseAnswered || !otherAnswered) {
      // Two failures are the same outcome (their messages quote different hosts); a failure and anything else is not.
      final a = _outcome(base);
      final b = _outcome(other);
      if (a == b) return CellComparison.same;
      return CellComparison(outcomeDiffers: true, reasons: ['$a vs $b']);
    }
    final reasons = <String>[];
    final statusDiffers = base!.status != other!.status;
    if (statusDiffers) reasons.add('status ${base.status} vs ${other.status}');
    final body = _compareBodies(MatrixBody.of(base), MatrixBody.of(other), mode);
    if (body.reason != null) reasons.add(body.reason!);
    return CellComparison(
      statusDiffers: statusDiffers,
      bodyDiffers: body.reason != null,
      changes: body.changes,
      reasons: reasons,
    );
  }

  static String _outcome(MatrixCell? cell) => cell == null ? 'not run' : cell.outcome;

  static ({String? reason, List<JsonChange> changes}) _compareBodies(MatrixBody a, MatrixBody b, MatrixCompareMode mode) {
    if (a.kind == MatrixBodyKind.none && b.kind == MatrixBodyKind.none) return (reason: null, changes: const []);
    if (a.kind != b.kind) return (reason: 'body: ${_kind(a.kind)} vs ${_kind(b.kind)}', changes: const []);
    if (a.kind == MatrixBodyKind.text) {
      return a.text == b.text ? (reason: null, changes: const []) : (reason: 'body differs', changes: const []);
    }
    var changes = JsonDiff.compare(a.comparable(mode), b.comparable(mode)).changes;
    if (mode == MatrixCompareMode.structure) {
      // A list that is empty in one column has no items to describe: nothing is known to differ.
      changes = [
        for (final c in changes)
          if (!(c.kind != JsonChangeKind.changed && c.path.endsWith('[0]'))) c,
      ];
    }
    if (changes.isEmpty) return (reason: null, changes: const []);
    return (reason: 'body: ${changes.length} ${changes.length == 1 ? 'field differs' : 'fields differ'}', changes: changes);
  }

  static String _kind(MatrixBodyKind kind) => switch (kind) {
        MatrixBodyKind.none => 'empty',
        MatrixBodyKind.json => 'JSON',
        MatrixBodyKind.text => 'text',
      };
}
