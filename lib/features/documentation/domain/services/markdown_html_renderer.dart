import 'dart:math' as math;
import '../entities/markdown_node.dart';
import 'markdown_parser.dart';
import 'safe_link.dart';

/// Turns parsed Markdown into HTML. Every piece of text is escaped and only
/// links accepted by [SafeLink] become anchors, so the output is safe to embed
/// whatever the source says.
abstract final class MarkdownHtmlRenderer {
  static final _unsafeLanguage = RegExp(r'[^A-Za-z0-9_+#.\-]');
  static final _htmlSpecials = RegExp('[&<>"\']');

  /// Safe in element content and in a quoted attribute.
  static String escape(String text) => text.replaceAllMapped(
        _htmlSpecials,
        (m) => switch (m[0]) {
          '&' => '&amp;',
          '<' => '&lt;',
          '>' => '&gt;',
          '"' => '&quot;',
          _ => '&#39;',
        },
      );

  /// [shiftHeadings] moves every heading down that many levels (never past h6).
  static String render(String markdown, {int shiftHeadings = 0}) {
    final out = StringBuffer();
    for (final block in MarkdownParser.parse(markdown)) {
      _block(out, block, shiftHeadings);
    }
    return out.toString();
  }

  static void _block(StringBuffer out, MarkdownBlock block, int shift) {
    switch (block) {
      case MarkdownHeading():
        final level = math.min(6, block.level + shift);
        out.writeln('<h$level>${_inlines(block.content)}</h$level>');
      case MarkdownParagraph():
        out.writeln('<p>${_inlines(block.content)}</p>');
      case MarkdownCodeBlock():
        final language = block.language.replaceAll(_unsafeLanguage, '');
        final attribute = language.isEmpty ? '' : ' class="language-$language"';
        out.writeln('<pre><code$attribute>${escape(block.code)}</code></pre>');
      case MarkdownQuote():
        out.writeln('<blockquote>');
        for (final child in block.children) {
          _block(out, child, shift);
        }
        out.writeln('</blockquote>');
      case MarkdownList():
        _list(out, block, shift);
      case MarkdownRule():
        out.writeln('<hr>');
      case MarkdownTable():
        _table(out, block);
    }
  }

  static void _list(StringBuffer out, MarkdownList list, int shift) {
    final tag = list.ordered ? 'ol' : 'ul';
    out.writeln(list.ordered && list.start != 1 ? '<ol start="${list.start}">' : '<$tag>');
    for (final item in list.items) {
      out.write('<li>');
      for (var i = 0; i < item.length; i++) {
        final block = item[i];
        if (i == 0 && block is MarkdownParagraph) {
          out.write(_inlines(block.content));
        } else {
          _block(out, block, shift);
        }
      }
      out.writeln('</li>');
    }
    out.writeln('</$tag>');
  }

  static void _table(StringBuffer out, MarkdownTable table) {
    String cell(String tag, int column, List<MarkdownInline> content) {
      final align = switch (table.alignments[column]) {
        MarkdownColumnAlign.none => '',
        final other => ' style="text-align:${other.name}"',
      };
      return '<$tag$align>${_inlines(content)}</$tag>';
    }

    out.writeln('<table>');
    out.writeln('<thead><tr>${[for (var c = 0; c < table.header.length; c++) cell('th', c, table.header[c])].join()}</tr></thead>');
    out.writeln('<tbody>');
    for (final row in table.rows) {
      out.writeln('<tr>${[for (var c = 0; c < row.length; c++) cell('td', c, row[c])].join()}</tr>');
    }
    out.writeln('</tbody>');
    out.writeln('</table>');
  }

  static String _inlines(List<MarkdownInline> nodes) => nodes.map(_inline).join();

  static String _inline(MarkdownInline node) => switch (node) {
        MarkdownText() => escape(node.text),
        MarkdownBold() => '<strong>${_inlines(node.children)}</strong>',
        MarkdownItalic() => '<em>${_inlines(node.children)}</em>',
        MarkdownCode() => '<code>${escape(node.code)}</code>',
        MarkdownLink() => SafeLink.isAllowed(node.url)
            ? '<a href="${escape(node.url)}" rel="noopener noreferrer" target="_blank">${_inlines(node.children)}</a>'
            : _inlines(node.children),
        MarkdownLineBreak() => '<br>',
      };
}
