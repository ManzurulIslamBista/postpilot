import 'dart:math' as math;
import 'markdown_lines.dart';

final _atxHeading = RegExp(r'^( {0,3})(#{1,6})(?=[ \t]|$)');

/// Makes a user-written description safe to paste into a larger Markdown
/// document.
abstract final class MarkdownEmbedder {
  /// Moves headings down by [shiftHeadings] levels (never past level 6) so
  /// they nest under the heading the text sits below, and closes a code fence
  /// left open so it cannot swallow the rest of the document.
  static String prepare(String markdown, {required int shiftHeadings}) {
    final out = <String>[];
    ({String char, int length, String info})? open;
    for (final line in markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
      final fence = open;
      if (fence != null) {
        if (MarkdownLines.isFenceClose(line, fence.char, fence.length)) open = null;
        out.add(line);
        continue;
      }
      open = MarkdownLines.fenceOpen(line);
      out.add(
        open != null
            ? line
            : line.replaceFirstMapped(
                _atxHeading,
                (m) => '${m[1]}${'#' * math.min(6, m[2]!.length + shiftHeadings)}',
              ),
      );
    }
    final unclosed = open;
    if (unclosed != null) out.add(unclosed.char * unclosed.length);
    return out.join('\n').trim();
  }
}
