import 'dart:convert';
import 'dart:typed_data';
import 'matrix_column.dart';

/// What one request did in one column: the answer, or why there was none.
final class MatrixCell {
  /// A response body is kept up to this many characters; the rest is cut and [bodyTruncated] says so.
  static const maxBodyChars = 512 * 1024;

  /// The HTTP status; null when nothing came back ([error]) or the request was not sent ([note]).
  final int? status;
  final int? durationMs;

  /// The response body as text; null without an answer.
  final String? body;
  final bool bodyTruncated;
  final String? contentType;

  /// The request could not be sent or got no answer (an undefined variable, a refused connection). Secret-masked.
  final String? error;

  /// Why the request was not sent at all: its "Run if" did not hold, or the production confirmation was declined.
  final String? note;

  const MatrixCell._({this.status, this.durationMs, this.body, this.bodyTruncated = false, this.contentType, this.error, this.note});

  /// An answer. [bodyBytes] is decoded as UTF-8 (a bad byte becomes U+FFFD); [truncated] is true when the app already
  /// cut the body at the response-size limit.
  factory MatrixCell.response({
    required int status,
    required Duration duration,
    Uint8List? bodyBytes,
    bool truncated = false,
    String? contentType,
  }) {
    var text = bodyBytes == null || bodyBytes.isEmpty ? '' : utf8.decode(bodyBytes, allowMalformed: true);
    var cut = truncated;
    if (text.length > maxBodyChars) {
      text = text.substring(0, maxBodyChars);
      cut = true;
    }
    return MatrixCell._(status: status, durationMs: duration.inMilliseconds, body: text, bodyTruncated: cut, contentType: contentType);
  }

  /// A response given as text (the command line has it already decoded).
  factory MatrixCell.text({required int status, required Duration duration, String? body, String? contentType}) {
    var text = body ?? '';
    var cut = false;
    if (text.length > maxBodyChars) {
      text = text.substring(0, maxBodyChars);
      cut = true;
    }
    return MatrixCell._(status: status, durationMs: duration.inMilliseconds, body: text, bodyTruncated: cut, contentType: contentType);
  }

  /// No answer: the request failed before or while it was sent.
  const MatrixCell.failed(String message, {int? durationMs}) : this._(error: message, durationMs: durationMs);

  /// The request was not sent, for [reason].
  const MatrixCell.notSent(String reason) : this._(note: reason);

  bool get hasResponse => status != null;

  /// `200`, `error` or `not sent`: how the cell reads in a sentence.
  String get outcome => status != null ? '$status' : (error != null ? 'error' : 'not sent');
}

/// One request of the run, with its cell in every column (same order as [MatrixGrid.columns]).
final class MatrixRow {
  /// Identifies the request across columns: its id in the app, `collection/folder/name/METHOD` on the command line.
  final String key;
  final String name;
  final String method;

  /// The folder path, `Orders / Archive`; empty at the top level.
  final String folder;

  /// Null while the column has not got to this request yet (or never did).
  final List<MatrixCell?> cells;

  MatrixRow({required this.key, required this.name, required this.method, this.folder = '', required int columns})
      : cells = List<MatrixCell?>.filled(columns, null, growable: false);

  /// `GET List orders`.
  String get title => '$method $name';
}

/// The result of a matrix run: requests down, columns across. Filled cell by cell while the run goes on, so a screen
/// can show it live; treat it as read-only anywhere else.
final class MatrixGrid {
  final List<MatrixColumn> columns;
  final List<MatrixRow> rows;

  MatrixGrid(this.columns, this.rows);

  factory MatrixGrid.empty(List<MatrixColumn> columns) => MatrixGrid(columns, []);

  MatrixRow? rowOf(String key) {
    for (final row in rows) {
      if (row.key == key) return row;
    }
    return null;
  }

  /// Puts [cell] where the request [rowKey] meets column [column]; false when there is no such row.
  bool setCell(String rowKey, int column, MatrixCell cell) {
    final row = rowOf(rowKey);
    if (row == null || column < 0 || column >= columns.length) return false;
    row.cells[column] = cell;
    return true;
  }
}
