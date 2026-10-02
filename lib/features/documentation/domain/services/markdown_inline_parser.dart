import 'dart:math' as math;
import '../entities/markdown_node.dart';

const _punctuation = '!"#\$%&\'()*+,-./:;<=>?@[\\]^_`{|}~';
final _autolink = RegExp(r'<([A-Za-z][A-Za-z0-9+.\-]{1,31}:[^\s<>]*)>');
final _bareUrl = RegExp(r'https?://[^\s<]+', caseSensitive: false);
final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _escapedPunctuation = RegExp(r'\\([!-/:-@\[-`{-~])');

/// What the emphasis searches of one text share: the searches known to fail,
/// so a run of unmatched openers is not rescanned once per opener, and a work
/// allowance that keeps input built to defeat that shortcut linear. Text
/// left after the allowance runs out stays literal.
final class _EmphasisScan {
  _EmphasisScan(int length) : budget = length * 200 + 100;

  /// Per `c` and size: an opener whose content starts at or after this index
  /// has no closer.
  final failedFrom = <String, int>{};
  int budget;
}

/// Bold, italic, inline code and links. Anything that does not form a complete
/// construct stays literal text; nesting and scan lengths are capped so hostile
/// input (docs can arrive through git) cannot make parsing slow.
abstract final class MarkdownInlineParser {
  static const _maxDepth = 8;
  static const _maxLinkScan = 2000;

  static List<MarkdownInline> parse(String text) => _run(text, 0, true);

  static List<MarkdownInline> _run(String s, int depth, bool allowLinks) {
    final out = <MarkdownInline>[];
    final buf = StringBuffer();
    final scan = _EmphasisScan(s.length);

    void flush() {
      if (buf.isEmpty) return;
      out.add(MarkdownText(buf.toString()));
      buf.clear();
    }

    var i = 0;
    while (i < s.length) {
      final c = s[i];

      if (c == '\\' && i + 1 < s.length) {
        final next = s[i + 1];
        if (next == '\n') {
          flush();
          out.add(const MarkdownLineBreak());
          i = _skipSpaces(s, i + 2);
          continue;
        }
        if (_punctuation.contains(next)) {
          buf.write(next);
          i += 2;
          continue;
        }
      }

      if (c == '\n') {
        final pending = buf.toString();
        final stripped = pending.trimRight();
        buf
          ..clear()
          ..write(stripped);
        if (pending.length - stripped.length >= 2) {
          flush();
          out.add(const MarkdownLineBreak());
        } else {
          buf.write(' ');
        }
        i = _skipSpaces(s, i + 1);
        continue;
      }

      if (c == '`') {
        var run = 1;
        while (i + run < s.length && s[i + run] == '`') {
          run++;
        }
        final end = _codeSpanEnd(s, i + run, run);
        if (end == -1) {
          buf.write('`' * run);
          i += run;
          continue;
        }
        flush();
        var code = s.substring(i + run, end).replaceAll('\n', ' ');
        if (code.length > 2 && code.startsWith(' ') && code.endsWith(' ') && code.trim().isNotEmpty) {
          code = code.substring(1, code.length - 1);
        }
        out.add(MarkdownCode(code));
        i = end + run;
        continue;
      }

      if (allowLinks && (c == '[' || (c == '!' && i + 1 < s.length && s[i + 1] == '['))) {
        final link = _link(s, c == '[' ? i : i + 1);
        if (link != null) {
          flush();
          // An image becomes a link to it: nothing is fetched while rendering docs.
          final label = link.label.trim();
          final children = label.isEmpty
              ? [MarkdownText(link.url)]
              : depth < _maxDepth
                  ? _run(label, depth + 1, false)
                  : [MarkdownText(label)];
          out.add(MarkdownLink(link.url, children));
          i = link.end;
          continue;
        }
      }

      if (allowLinks && c == '<') {
        final match = _autolink.matchAsPrefix(s, i);
        if (match != null) {
          flush();
          out.add(MarkdownLink(match[1]!, [MarkdownText(match[1]!)]));
          i = match.end;
          continue;
        }
      }

      if (allowLinks && (c == 'h' || c == 'H') && (i == 0 || !_wordChar.hasMatch(s[i - 1]))) {
        final match = _bareUrl.matchAsPrefix(s, i);
        if (match != null) {
          final url = _trimUrlEnd(match[0]!);
          if (url.length > 'https://'.length) {
            flush();
            out.add(MarkdownLink(url, [MarkdownText(url)]));
            i += url.length;
            continue;
          }
        }
      }

      if (c == '*' || c == '_') {
        var run = 1;
        while (i + run < s.length && s[i + run] == c) {
          run++;
        }
        if (run <= 3 && depth < _maxDepth && _canOpen(s, i, i + run, c)) {
          final close = _emphasisEnd(s, i + run, c, run, scan, 0);
          if (close != -1) {
            flush();
            final inner = _run(s.substring(i + run, close), depth + 1, allowLinks);
            out.add(run == 1
                ? MarkdownItalic(inner)
                : run == 2
                    ? MarkdownBold(inner)
                    : MarkdownBold([MarkdownItalic(inner)]));
            i = close + run;
            continue;
          }
        }
        buf.write(c * run);
        i += run;
        continue;
      }

      buf.write(c);
      i++;
    }
    flush();
    return out;
  }

  static int _skipSpaces(String s, int i) {
    while (i < s.length && (s[i] == ' ' || s[i] == '\t')) {
      i++;
    }
    return i;
  }

  static int _codeSpanEnd(String s, int from, int run) {
    var i = from;
    while (i < s.length) {
      if (s[i] != '`') {
        i++;
        continue;
      }
      var end = i;
      while (end < s.length && s[end] == '`') {
        end++;
      }
      if (end - i == run) return i;
      i = end;
    }
    return -1;
  }

  static bool _isSpace(String ch) => ch.trim().isEmpty;

  /// The run `s[start, end)` can open emphasis: text follows it, and for
  /// underscores it does not sit inside a word (`snake_case` stays literal).
  static bool _canOpen(String s, int start, int end, String c) {
    if (end >= s.length || _isSpace(s[end])) return false;
    return !(c == '_' && start > 0 && _wordChar.hasMatch(s[start - 1]));
  }

  static bool _canClose(String s, int start, int end, String c) {
    if (start == 0 || _isSpace(s[start - 1])) return false;
    return !(c == '_' && end < s.length && _wordChar.hasMatch(s[end]));
  }

  /// Start of the delimiter run that closes an emphasis opened with [size]
  /// characters, or -1. A longer closing run (`*a **b***`) gives [size]
  /// characters from its start and leaves the rest for the enclosing emphasis;
  /// a pair opened on the way is skipped whole.
  static int _emphasisEnd(String s, int from, String c, int size, _EmphasisScan scan, int nest) {
    final key = '$c$size';
    final failed = scan.failedFrom[key];
    if (failed != null && from >= failed) return -1;

    var i = from;
    // Where the last pair skipped on the way ended. A search that fails saw
    // nothing that could close in the text after that point, so a later search
    // starting there fails too; one starting before it may take a skipped
    // pair's closer for its own (`*.json and *this*`), so it must run.
    var resume = from;
    while (i < s.length) {
      if (--scan.budget < 0) return -1;
      final ch = s[i];
      if (ch == '\\') {
        i += 2;
        continue;
      }
      if (ch == '`') {
        var run = 1;
        while (i + run < s.length && s[i + run] == '`') {
          run++;
        }
        final end = _codeSpanEnd(s, i + run, run);
        i = end == -1 ? i + run : end + run;
        continue;
      }
      if (ch == c) {
        var end = i;
        while (end < s.length && s[end] == c) {
          end++;
        }
        final run = end - i;
        final opens = _canOpen(s, i, end, c);
        if (i > from && _canClose(s, i, end, c) && (run == size || (run > size && !opens))) return i;
        if (run <= 3 && nest < _maxDepth && opens) {
          final inner = _emphasisEnd(s, end, c, run, scan, nest + 1);
          if (inner != -1) {
            i = inner + run;
            resume = i;
            continue;
          }
        }
        i = end;
        continue;
      }
      i++;
    }
    scan.failedFrom[key] = failed == null ? resume : math.min(failed, resume);
    return -1;
  }

  static ({int end, String url, String label})? _link(String s, int open) {
    final close = _bracketEnd(s, open);
    if (close == -1 || close + 1 >= s.length || s[close + 1] != '(') return null;
    final destination = _destination(s, close + 2);
    if (destination == null) return null;
    return (end: destination.end, url: destination.url, label: s.substring(open + 1, close));
  }

  static int _bracketEnd(String s, int open) {
    var depth = 0;
    final limit = math.min(s.length, open + _maxLinkScan);
    for (var i = open; i < limit; i++) {
      final c = s[i];
      if (c == '\\') {
        i++;
      } else if (c == '[') {
        depth++;
      } else if (c == ']') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// Reads `url`, `<url>` or `url "title"` up to the closing parenthesis; the
  /// title is dropped.
  static ({String url, int end})? _destination(String s, int start) {
    final limit = math.min(s.length, start + _maxLinkScan);
    var i = _skipSpaces(s, start);
    final String url;
    if (i < limit && s[i] == '<') {
      final end = s.indexOf('>', i + 1);
      if (end == -1 || end >= limit) return null;
      url = s.substring(i + 1, end);
      i = end + 1;
    } else {
      final begin = i;
      var depth = 0;
      while (i < limit) {
        final c = s[i];
        if (c == ' ' || c == '\n' || c == '\t') break;
        if (c == '\\' && i + 1 < limit) {
          i += 2;
          continue;
        }
        if (c == '(') {
          depth++;
        } else if (c == ')') {
          if (depth == 0) break;
          depth--;
        }
        i++;
      }
      url = s.substring(begin, i).replaceAllMapped(_escapedPunctuation, (m) => m[1]!);
    }
    i = _skipSpaces(s, i);
    if (i < limit && (s[i] == '"' || s[i] == "'" || s[i] == '(')) {
      final end = s.indexOf(s[i] == '(' ? ')' : s[i], i + 1);
      if (end == -1 || end >= limit) return null;
      i = _skipSpaces(s, end + 1);
    }
    if (i >= limit || s[i] != ')') return null;
    return (url: url, end: i + 1);
  }

  /// Sentence punctuation and an unbalanced closing parenthesis are not part
  /// of a bare URL.
  static String _trimUrlEnd(String url) {
    var end = url.length;
    while (end > 0) {
      final c = url[end - 1];
      if ('.,;:!?\'"*_~'.contains(c)) {
        end--;
      } else if (c == ')' && _count(url, end, '(') < _count(url, end, ')')) {
        end--;
      } else {
        break;
      }
    }
    return url.substring(0, end);
  }

  static int _count(String s, int end, String ch) {
    var n = 0;
    for (var i = 0; i < end; i++) {
      if (s[i] == ch) n++;
    }
    return n;
  }
}
