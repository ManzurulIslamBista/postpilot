import 'package:flutter/painting.dart';

enum SyntaxKind { key, string, number, keyword, punctuation }

/// A half-open [start, end) character range of one highlighted token.
class SyntaxRange {
  final int start;
  final int end;
  final SyntaxKind kind;
  const SyntaxRange(this.start, this.end, this.kind);
}

/// Bodies larger than this are shown unhighlighted: tokenising and laying out
/// tens of thousands of coloured spans costs more than it helps.
const maxHighlightedChars = 200 * 1024;

/// Splits JSON text into highlightable tokens. Lenient: it never throws and
/// never needs valid JSON (a truncated or half-pretty body still highlights
/// what it can), and whitespace is simply left uncovered.
List<SyntaxRange> tokenizeJson(String text) {
  final out = <SyntaxRange>[];
  final n = text.length;
  var i = 0;
  while (i < n) {
    final c = text.codeUnitAt(i);
    if (c == 0x22) {
      // String: runs to the next unescaped quote (or the end, if cut off).
      var j = i + 1;
      while (j < n) {
        final d = text.codeUnitAt(j);
        if (d == 0x5C) {
          j += 2;
          continue;
        }
        if (d == 0x22) break;
        j++;
      }
      final end = j < n ? j + 1 : n;
      var k = end;
      while (k < n && _isSpace(text.codeUnitAt(k))) {
        k++;
      }
      final isKey = k < n && text.codeUnitAt(k) == 0x3A;
      out.add(SyntaxRange(i, end, isKey ? SyntaxKind.key : SyntaxKind.string));
      i = end;
    } else if (c == 0x2D || (c >= 0x30 && c <= 0x39)) {
      var j = i + 1;
      while (j < n && _isNumberChar(text.codeUnitAt(j))) {
        j++;
      }
      out.add(SyntaxRange(i, j, SyntaxKind.number));
      i = j;
    } else if (_isLetter(c)) {
      var j = i + 1;
      while (j < n && _isLetter(text.codeUnitAt(j))) {
        j++;
      }
      final word = text.substring(i, j);
      if (word == 'true' || word == 'false' || word == 'null') {
        out.add(SyntaxRange(i, j, SyntaxKind.keyword));
      }
      i = j;
    } else if (c == 0x7B || c == 0x7D || c == 0x5B || c == 0x5D || c == 0x2C || c == 0x3A) {
      out.add(SyntaxRange(i, i + 1, SyntaxKind.punctuation));
      i++;
    } else {
      i++;
    }
  }
  return out;
}

bool _isSpace(int c) => c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09;
bool _isLetter(int c) => (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A);
bool _isNumberChar(int c) => (c >= 0x30 && c <= 0x39) || c == 0x2E || c == 0x65 || c == 0x45 || c == 0x2B || c == 0x2D;

/// Lays [text] out as spans with syntax colours from [syntax] and search-match
/// emphasis from [matches] (start offsets, each [queryLength] long, the
/// [currentMatch]-th one drawn stronger). Both inputs may be empty. The spans
/// always concatenate back to exactly [text].
List<InlineSpan> buildBodySpans({
  required String text,
  required List<SyntaxRange> syntax,
  required TextStyle Function(SyntaxKind) syntaxStyle,
  required List<int> matches,
  required int queryLength,
  required int currentMatch,
  required TextStyle highlight,
  required TextStyle current,
}) {
  if (syntax.isEmpty && matches.isEmpty) return [TextSpan(text: text)];

  // Every offset where the style can change, in order.
  final cuts = <int>{0, text.length};
  for (final s in syntax) {
    cuts
      ..add(s.start)
      ..add(s.end);
  }
  for (final m in matches) {
    cuts
      ..add(m)
      ..add(m + queryLength);
  }
  final points = cuts.where((p) => p >= 0 && p <= text.length).toList()..sort();

  final spans = <InlineSpan>[];
  var si = 0;
  var mi = 0;
  for (var p = 0; p + 1 < points.length; p++) {
    final a = points[p];
    final b = points[p + 1];
    if (a == b) continue;
    while (si < syntax.length && syntax[si].end <= a) {
      si++;
    }
    while (mi < matches.length && matches[mi] + queryLength <= a) {
      mi++;
    }
    TextStyle? style;
    if (si < syntax.length && syntax[si].start <= a) style = syntaxStyle(syntax[si].kind);
    if (mi < matches.length && matches[mi] <= a) {
      final emphasis = mi == currentMatch ? current : highlight;
      style = style == null ? emphasis : style.merge(emphasis);
    }
    spans.add(TextSpan(text: text.substring(a, b), style: style));
  }
  return spans;
}
