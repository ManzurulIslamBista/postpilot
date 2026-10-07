import 'dart:typed_data';

enum DiffLineKind { context, added, removed }

final class DiffLine {
  final DiffLineKind kind;
  final String text;
  const DiffLine(this.kind, this.text);

  String get prefixed => switch (kind) {
        DiffLineKind.context => ' $text',
        DiffLineKind.added => '+$text',
        DiffLineKind.removed => '-$text',
      };
}

/// One `@@ -a,b +c,d @@` block: the changed lines with their surrounding context.
final class DiffHunk {
  /// 1-based line numbers; for an empty side the number of the line before the block, as `diff -u` writes it.
  final int beforeStart;
  final int beforeCount;
  final int afterStart;
  final int afterCount;
  final List<DiffLine> lines;

  const DiffHunk({
    required this.beforeStart,
    required this.beforeCount,
    required this.afterStart,
    required this.afterCount,
    required this.lines,
  });

  String get header => '@@ -$beforeStart,$beforeCount +$afterStart,$afterCount @@';
}

/// A line diff of two texts in the unified format, computed without any package. Line endings and trailing blank
/// lines are ignored, so a file saved with `\r\n` or a final newline is not "changed" by that alone.
final class UnifiedDiff {
  final List<DiffHunk> hunks;
  final int added;
  final int removed;

  const UnifiedDiff(this.hunks, {this.added = 0, this.removed = 0});

  bool get isEmpty => hunks.isEmpty;

  /// Past this many table cells the exact diff is not attempted: the whole middle part is shown as replaced. Generated
  /// files are a few hundred lines, so this only guards against a huge unrelated file.
  static const _maxCells = 4000000;

  static List<String> _lines(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceFirst(RegExp(r'\s+$'), '');
    return normalized.isEmpty ? const [] : normalized.split('\n');
  }

  /// [before] to [after], with [context] unchanged lines around every change.
  static UnifiedDiff compute(String before, String after, {int context = 3}) {
    final a = _lines(before);
    final b = _lines(after);
    final ops = _script(a, b);

    final changed = [for (var i = 0; i < ops.length; i++) if (ops[i].kind != DiffLineKind.context) i];
    if (changed.isEmpty) return const UnifiedDiff([]);

    // Line numbers of the old and the new text before each operation.
    final beforeAt = List<int>.filled(ops.length + 1, 0);
    final afterAt = List<int>.filled(ops.length + 1, 0);
    for (var i = 0; i < ops.length; i++) {
      beforeAt[i + 1] = beforeAt[i] + (ops[i].kind == DiffLineKind.added ? 0 : 1);
      afterAt[i + 1] = afterAt[i] + (ops[i].kind == DiffLineKind.removed ? 0 : 1);
    }

    final hunks = <DiffHunk>[];
    var groupStart = changed.first;
    var groupEnd = changed.first;
    void close() {
      final from = (groupStart - context).clamp(0, ops.length);
      final to = (groupEnd + context + 1).clamp(0, ops.length);
      final beforeCount = beforeAt[to] - beforeAt[from];
      final afterCount = afterAt[to] - afterAt[from];
      hunks.add(DiffHunk(
        beforeStart: beforeCount == 0 ? beforeAt[from] : beforeAt[from] + 1,
        beforeCount: beforeCount,
        afterStart: afterCount == 0 ? afterAt[from] : afterAt[from] + 1,
        afterCount: afterCount,
        lines: ops.sublist(from, to),
      ));
    }

    for (final index in changed.skip(1)) {
      // Two changes closer than twice the context share one hunk.
      if (index - groupEnd - 1 > 2 * context) {
        close();
        groupStart = index;
      }
      groupEnd = index;
    }
    close();

    return UnifiedDiff(
      hunks,
      added: ops.where((o) => o.kind == DiffLineKind.added).length,
      removed: ops.where((o) => o.kind == DiffLineKind.removed).length,
    );
  }

  /// Every line of both texts as context, removed or added, in order.
  static List<DiffLine> _script(List<String> a, List<String> b) {
    var prefix = 0;
    while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < a.length - prefix && suffix < b.length - prefix && a[a.length - 1 - suffix] == b[b.length - 1 - suffix]) {
      suffix++;
    }
    final midA = a.sublist(prefix, a.length - suffix);
    final midB = b.sublist(prefix, b.length - suffix);
    final ops = <DiffLine>[
      for (var i = 0; i < prefix; i++) DiffLine(DiffLineKind.context, a[i]),
    ];

    if (midA.isEmpty || midB.isEmpty || (midA.length + 1) * (midB.length + 1) > _maxCells) {
      ops
        ..addAll(midA.map((l) => DiffLine(DiffLineKind.removed, l)))
        ..addAll(midB.map((l) => DiffLine(DiffLineKind.added, l)));
    } else {
      // table[i][j]: how many lines the tails midA[i..] and midB[j..] have in common.
      final n = midA.length;
      final m = midB.length;
      final table = List.generate(n + 1, (_) => Int32List(m + 1));
      for (var i = n - 1; i >= 0; i--) {
        for (var j = m - 1; j >= 0; j--) {
          table[i][j] = midA[i] == midB[j] ? table[i + 1][j + 1] + 1 : (table[i + 1][j] >= table[i][j + 1] ? table[i + 1][j] : table[i][j + 1]);
        }
      }
      var i = 0;
      var j = 0;
      while (i < n && j < m) {
        if (midA[i] == midB[j]) {
          ops.add(DiffLine(DiffLineKind.context, midA[i]));
          i++;
          j++;
        } else if (table[i + 1][j] >= table[i][j + 1]) {
          ops.add(DiffLine(DiffLineKind.removed, midA[i++]));
        } else {
          ops.add(DiffLine(DiffLineKind.added, midB[j++]));
        }
      }
      while (i < n) {
        ops.add(DiffLine(DiffLineKind.removed, midA[i++]));
      }
      while (j < m) {
        ops.add(DiffLine(DiffLineKind.added, midB[j++]));
      }
    }

    for (var i = a.length - suffix; i < a.length; i++) {
      ops.add(DiffLine(DiffLineKind.context, a[i]));
    }
    return ops;
  }

  /// The diff as `diff -u` writes it, with [beforeLabel] and [afterLabel] on the two header lines. Empty when nothing changed.
  String format({String beforeLabel = 'a', String afterLabel = 'b'}) {
    if (hunks.isEmpty) return '';
    final b = StringBuffer()
      ..writeln('--- $beforeLabel')
      ..writeln('+++ $afterLabel');
    for (final hunk in hunks) {
      b.writeln(hunk.header);
      for (final line in hunk.lines) {
        b.writeln(line.prefixed);
      }
    }
    return b.toString().trimRight();
  }
}
