import '../entities/markdown_node.dart';
import 'markdown_inline_parser.dart';
import 'markdown_lines.dart';

final _heading = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+(.*))?$');
final _rule = RegExp(r'^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$');
final _quote = RegExp(r'^ {0,3}> ?(.*)$');
final _marker = RegExp(r'^( *)([-+*]|\d{1,9}[.)])( +)(\S.*)$');
final _delimiterRow = RegExp(r'^\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?$');

typedef _Parsed = (MarkdownBlock, int);

final class _Marker {
  final int indent;
  final bool ordered;
  final int number;
  final int contentIndent;
  final String content;

  const _Marker(this.indent, this.ordered, this.number, this.contentIndent, this.content);
}

/// A small Markdown reader: headings, paragraphs, fenced code, block quotes,
/// nested lists, rules and tables, plus the inline forms of
/// [MarkdownInlineParser]. Indented code, setext headings, raw HTML and
/// reference links are not supported and stay plain text.
abstract final class MarkdownParser {
  static const _maxNesting = 12;

  static List<MarkdownBlock> parse(String source) {
    final lines = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n').map(_expandTabs).toList();
    return _blocks(lines, 0);
  }

  static List<MarkdownBlock> _blocks(List<String> lines, int depth) {
    final blocks = <MarkdownBlock>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      final fence = MarkdownLines.fenceOpen(line);
      final heading = _heading.firstMatch(line);
      final _Parsed parsed;
      if (fence != null) {
        parsed = _fenced(lines, i, fence);
      } else if (heading != null) {
        parsed = (_headingBlock(heading), i + 1);
      } else if (_rule.hasMatch(line)) {
        parsed = (const MarkdownRule(), i + 1);
      } else if (depth < _maxNesting && _quote.hasMatch(line)) {
        parsed = _quoteBlock(lines, i, depth);
      } else if (depth < _maxNesting && _listMarker(line) != null) {
        parsed = _listBlock(lines, i, depth);
      } else if (_startsTable(lines, i)) {
        parsed = _tableBlock(lines, i);
      } else {
        parsed = _paragraph(lines, i);
      }
      blocks.add(parsed.$1);
      i = parsed.$2;
    }
    return blocks;
  }

  static String _expandTabs(String line) {
    var end = 0;
    while (end < line.length && (line[end] == ' ' || line[end] == '\t')) {
      end++;
    }
    final indent = line.substring(0, end);
    return indent.contains('\t') ? indent.replaceAll('\t', '    ') + line.substring(end) : line;
  }

  static int _indentOf(String line) {
    var n = 0;
    while (n < line.length && line[n] == ' ') {
      n++;
    }
    return n;
  }

  static String _dedent(String line, int columns) {
    final remove = _indentOf(line) < columns ? _indentOf(line) : columns;
    return line.substring(remove);
  }

  static MarkdownHeading _headingBlock(RegExpMatch match) {
    final text = _withoutClosingHashes((match[2] ?? '').trim());
    return MarkdownHeading(match[1]!.length, MarkdownInlineParser.parse(text));
  }

  /// "Title ##" loses its closing hashes; "C#" keeps its own.
  static String _withoutClosingHashes(String text) {
    var hashes = text.length;
    while (hashes > 0 && text[hashes - 1] == '#') {
      hashes--;
    }
    if (hashes == text.length) return text;
    if (hashes == 0) return '';
    return text[hashes - 1] == ' ' || text[hashes - 1] == '\t' ? text.substring(0, hashes).trimRight() : text;
  }

  static _Parsed _fenced(List<String> lines, int start, ({String char, int length, String info}) fence) {
    final indent = _indentOf(lines[start]);
    final code = <String>[];
    var i = start + 1;
    while (i < lines.length && !MarkdownLines.isFenceClose(lines[i], fence.char, fence.length)) {
      code.add(_dedent(lines[i], indent));
      i++;
    }
    if (i < lines.length) i++;
    final language = fence.info.split(RegExp(r'\s+')).first;
    return (MarkdownCodeBlock(code.join('\n'), language: language), i);
  }

  static bool _interruptsParagraph(String line) {
    if (MarkdownLines.fenceOpen(line) != null ||
        _heading.hasMatch(line) ||
        _rule.hasMatch(line) ||
        _quote.hasMatch(line)) {
      return true;
    }
    final marker = _listMarker(line);
    return marker != null && (!marker.ordered || marker.number == 1);
  }

  static _Parsed _paragraph(List<String> lines, int start) {
    final text = <String>[lines[start].trimLeft()];
    var i = start + 1;
    while (i < lines.length && lines[i].trim().isNotEmpty && !_interruptsParagraph(lines[i])) {
      text.add(lines[i].trimLeft());
      i++;
    }
    return (MarkdownParagraph(MarkdownInlineParser.parse(text.join('\n').trimRight())), i);
  }

  static _Parsed _quoteBlock(List<String> lines, int start, int depth) {
    final inner = <String>[];
    var i = start;
    while (i < lines.length) {
      final match = _quote.firstMatch(lines[i]);
      if (match != null) {
        inner.add(match[1]!);
      } else if (lines[i].trim().isNotEmpty && inner.last.trim().isNotEmpty && !_interruptsParagraph(lines[i])) {
        inner.add(lines[i]);
      } else {
        break;
      }
      i++;
    }
    return (MarkdownQuote(_blocks(inner, depth + 1)), i);
  }

  static _Marker? _listMarker(String line) {
    final match = _marker.firstMatch(line);
    if (match == null) return null;
    final token = match[2]!;
    final ordered = token.length > 1;
    final spaces = match[3]!.length;
    final indent = match[1]!.length;
    return _Marker(
      indent,
      ordered,
      ordered ? int.parse(token.substring(0, token.length - 1)) : 0,
      indent + token.length + (spaces > 4 ? 1 : spaces),
      match[4]!,
    );
  }

  static _Parsed _listBlock(List<String> lines, int start, int depth) {
    final first = _listMarker(lines[start])!;
    final items = <List<MarkdownBlock>>[];
    var i = start;
    while (true) {
      final marker = _listMarker(lines[i])!;
      final itemLines = <String>[marker.content];
      i++;
      while (i < lines.length) {
        final line = lines[i];
        if (line.trim().isEmpty) {
          var next = i + 1;
          while (next < lines.length && lines[next].trim().isEmpty) {
            next++;
          }
          if (next < lines.length && _indentOf(lines[next]) >= marker.contentIndent) {
            itemLines.addAll(lines.getRange(i, next));
            i = next;
            continue;
          }
          break;
        }
        if (_indentOf(line) >= marker.contentIndent) {
          itemLines.add(_dedent(line, marker.contentIndent));
        } else if (_listMarker(line) != null || _interruptsParagraph(line)) {
          break;
        } else {
          itemLines.add(line.trimLeft());
        }
        i++;
      }
      items.add(_blocks(itemLines, depth + 1));

      var next = i;
      while (next < lines.length && lines[next].trim().isEmpty) {
        next++;
      }
      final sibling = next < lines.length ? _listMarker(lines[next]) : null;
      if (sibling == null || sibling.ordered != first.ordered) break;
      i = next;
    }
    return (MarkdownList(ordered: first.ordered, start: first.number, items: items), i);
  }

  static List<String> _splitRow(String row) {
    var text = row.trim();
    if (text.startsWith('|')) text = text.substring(1);
    if (text.endsWith('|') && !text.endsWith(r'\|')) text = text.substring(0, text.length - 1);
    final cells = <String>[];
    final cell = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (text[i] == '\\' && i + 1 < text.length && text[i + 1] == '|') {
        cell.write('|');
        i++;
      } else if (text[i] == '|') {
        cells.add(cell.toString().trim());
        cell.clear();
      } else {
        cell.write(text[i]);
      }
    }
    cells.add(cell.toString().trim());
    return cells;
  }

  static bool _startsTable(List<String> lines, int i) {
    if (i + 1 >= lines.length || !lines[i].contains('|') || !_delimiterRow.hasMatch(lines[i + 1].trim())) {
      return false;
    }
    return _splitRow(lines[i]).length == _splitRow(lines[i + 1]).length;
  }

  static _Parsed _tableBlock(List<String> lines, int start) {
    final header = _splitRow(lines[start]);
    final alignments = [
      for (final cell in _splitRow(lines[start + 1]))
        switch ((cell.startsWith(':'), cell.endsWith(':'))) {
          (true, true) => MarkdownColumnAlign.center,
          (true, false) => MarkdownColumnAlign.left,
          (false, true) => MarkdownColumnAlign.right,
          _ => MarkdownColumnAlign.none,
        },
    ];
    final rows = <List<List<MarkdownInline>>>[];
    var i = start + 2;
    while (i < lines.length && lines[i].trim().isNotEmpty && lines[i].contains('|')) {
      final cells = _splitRow(lines[i]);
      rows.add([
        for (var c = 0; c < header.length; c++)
          MarkdownInlineParser.parse(c < cells.length ? cells[c] : ''),
      ]);
      i++;
    }
    return (
      MarkdownTable(
        alignments: alignments,
        header: [for (final cell in header) MarkdownInlineParser.parse(cell)],
        rows: rows,
      ),
      i,
    );
  }
}
