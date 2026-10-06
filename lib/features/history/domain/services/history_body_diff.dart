import 'dart:convert';
import 'dart:typed_data';
import '../../../response_tools/domain/services/json_diff.dart';

enum DiffLineKind { same, added, removed, skipped }

final class DiffLine {
  final DiffLineKind kind;

  /// The line; for [DiffLineKind.skipped] a note saying how many unchanged lines are left out.
  final String text;
  const DiffLine(this.kind, this.text);
}

/// How two response bodies differ.
sealed class HistoryBodyDiff {
  const HistoryBodyDiff();
}

/// Character for character the same.
final class BodiesIdentical extends HistoryBodyDiff {
  const BodiesIdentical();
}

/// One of the bodies is not there to compare (binary, empty, or History kept none).
final class BodiesUnavailable extends HistoryBodyDiff {
  final String reason;
  const BodiesUnavailable(this.reason);
}

/// Both are JSON: compared by structure, which ignores key order and indentation.
final class JsonBodiesDiff extends HistoryBodyDiff {
  final JsonDiffResult result;
  const JsonBodiesDiff(this.result);
}

/// Text that is not JSON on both sides: compared line by line.
final class LineBodiesDiff extends HistoryBodyDiff {
  final List<DiffLine> lines;
  final int added;
  final int removed;

  /// More lines than are compared; the first [HistoryBodyCompare.maxLines] of each were.
  final bool cut;
  const LineBodiesDiff(this.lines, {required this.added, required this.removed, required this.cut});
}

abstract final class HistoryBodyCompare {
  /// The most lines of either body that are compared: the table behind a line diff grows with their product.
  static const maxLines = 2000;

  /// Unchanged lines kept on each side of a change; longer stretches are summarised.
  static const context = 2;

  static HistoryBodyDiff compare(String? before, String? after, {Set<String> ignoreKeys = const {}}) {
    if (before == null || after == null || before.isEmpty || after.isEmpty) {
      return const BodiesUnavailable('At least one of the two entries has no response body stored, so there is nothing to compare.');
    }
    if (before == after) return const BodiesIdentical();
    final left = _json(before);
    final right = _json(after);
    if (left != null && right != null) return JsonBodiesDiff(JsonDiff.compare(left.value, right.value, ignoreKeys: ignoreKeys));
    return _lines(before, after);
  }

  /// Wrapped so that a JSON `null` document is told from "not JSON".
  static ({Object? value})? _json(String text) {
    final head = text.trimLeft();
    if (!head.startsWith('{') && !head.startsWith('[')) return null;
    try {
      return (value: jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  static HistoryBodyDiff _lines(String before, String after) {
    var a = _split(before);
    var b = _split(after);
    final cut = a.length > maxLines || b.length > maxLines;
    if (a.length > maxLines) a = a.sublist(0, maxLines);
    if (b.length > maxLines) b = b.sublist(0, maxLines);

    // What the two share at both ends needs no table.
    var start = 0;
    while (start < a.length && start < b.length && a[start] == b[start]) {
      start++;
    }
    var endA = a.length;
    var endB = b.length;
    while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
      endA--;
      endB--;
    }

    final middle = _diffMiddle(a.sublist(start, endA), b.sublist(start, endB));
    final all = <DiffLine>[
      for (var i = 0; i < start; i++) DiffLine(DiffLineKind.same, a[i]),
      ...middle,
      for (var i = endA; i < a.length; i++) DiffLine(DiffLineKind.same, a[i]),
    ];
    final added = all.where((l) => l.kind == DiffLineKind.added).length;
    final removed = all.where((l) => l.kind == DiffLineKind.removed).length;
    // Equal as far as it was compared is not "identical" when more was left unread.
    if (added == 0 && removed == 0 && !cut) return const BodiesIdentical();
    return LineBodiesDiff(_collapse(all), added: added, removed: removed, cut: cut);
  }

  static List<String> _split(String text) => text.replaceAll('\r\n', '\n').split('\n');

  /// Longest-common-subsequence diff of two short line lists.
  static List<DiffLine> _diffMiddle(List<String> a, List<String> b) {
    final n = a.length;
    final m = b.length;
    if (n == 0) return [for (final line in b) DiffLine(DiffLineKind.added, line)];
    if (m == 0) return [for (final line in a) DiffLine(DiffLineKind.removed, line)];

    final width = m + 1;
    final table = Uint32List((n + 1) * width);
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        table[i * width + j] = a[i] == b[j]
            ? table[(i + 1) * width + j + 1] + 1
            : (table[(i + 1) * width + j] >= table[i * width + j + 1]
                ? table[(i + 1) * width + j]
                : table[i * width + j + 1]);
      }
    }
    final out = <DiffLine>[];
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (a[i] == b[j]) {
        out.add(DiffLine(DiffLineKind.same, a[i]));
        i++;
        j++;
      } else if (table[(i + 1) * width + j] >= table[i * width + j + 1]) {
        out.add(DiffLine(DiffLineKind.removed, a[i++]));
      } else {
        out.add(DiffLine(DiffLineKind.added, b[j++]));
      }
    }
    while (i < n) {
      out.add(DiffLine(DiffLineKind.removed, a[i++]));
    }
    while (j < m) {
      out.add(DiffLine(DiffLineKind.added, b[j++]));
    }
    return out;
  }

  /// Keeps [context] unchanged lines around each change and summarises the rest.
  static List<DiffLine> _collapse(List<DiffLine> lines) {
    final keep = List<bool>.filled(lines.length, false);
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].kind == DiffLineKind.same) continue;
      for (var k = i - context; k <= i + context; k++) {
        if (k >= 0 && k < lines.length) keep[k] = true;
      }
    }
    final out = <DiffLine>[];
    var skipped = 0;
    for (var i = 0; i < lines.length; i++) {
      if (keep[i]) {
        if (skipped > 0) out.add(DiffLine(DiffLineKind.skipped, '$skipped unchanged line${skipped == 1 ? '' : 's'}'));
        skipped = 0;
        out.add(lines[i]);
      } else {
        skipped++;
      }
    }
    if (skipped > 0) out.add(DiffLine(DiffLineKind.skipped, '$skipped unchanged line${skipped == 1 ? '' : 's'}'));
    return out;
  }
}
