import 'dart:convert';
import 'markup_scanner.dart';

// Indentation stops growing past this depth so a pathologically nested body
// cannot make the output quadratically larger than the input.
const _maxIndentDepth = 64;

/// Re-indents a JSON object or array by walking the original text, so numbers,
/// string escapes and duplicate keys come out exactly as they were sent.
/// Returns [source] unchanged when it is not a valid JSON object or array.
String prettyPrintJson(String source) {
  final head = source.trimLeft();
  if (!head.startsWith('{') && !head.startsWith('[')) return source;
  try {
    jsonDecode(source);
  } on FormatException {
    return source;
  }
  return _indentJson(source);
}

String _indentJson(String source) {
  final out = StringBuffer();
  final indents = <String>[''];
  var depth = 0;

  void newline() {
    final level = depth < _maxIndentDepth ? depth : _maxIndentDepth;
    while (indents.length <= level) {
      indents.add('  ' * indents.length);
    }
    out
      ..write('\n')
      ..write(indents[level]);
  }

  var i = 0;
  while (i < source.length) {
    final c = source.codeUnitAt(i);
    switch (c) {
      case 0x22: // "
        var end = i + 1;
        while (end < source.length && source.codeUnitAt(end) != 0x22) {
          end += source.codeUnitAt(end) == 0x5C ? 2 : 1;
        }
        final stop = end < source.length ? end + 1 : source.length;
        out.write(source.substring(i, stop));
        i = stop;
      case 0x7B || 0x5B: // { [
        var next = i + 1;
        while (next < source.length && _isJsonSpace(source.codeUnitAt(next))) {
          next++;
        }
        final closer = c == 0x7B ? 0x7D : 0x5D;
        if (next < source.length && source.codeUnitAt(next) == closer) {
          out
            ..writeCharCode(c)
            ..writeCharCode(closer);
          i = next + 1;
        } else {
          out.writeCharCode(c);
          depth++;
          newline();
          i++;
        }
      case 0x7D || 0x5D: // } ]
        if (depth > 0) depth--;
        newline();
        out.writeCharCode(c);
        i++;
      case 0x2C: // ,
        out.writeCharCode(c);
        newline();
        i++;
      case 0x3A: // :
        out.write(': ');
        i++;
      default:
        if (!_isJsonSpace(c)) out.writeCharCode(c);
        i++;
    }
  }
  return out.toString();
}

bool _isJsonSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

/// Puts each tag of an XML or HTML document on its own indented line. An
/// element holding only text stays on one line. Text is trimmed and
/// whitespace-only text between tags dropped; `<script>`, `<style>`, `<pre>`
/// and `<textarea>` are left verbatim in HTML.
String prettyPrintMarkup(String source, {required bool html}) {
  final tokens = <MarkupToken>[];
  for (final token in scanMarkup(source, html: html)) {
    if (token.kind != MarkupTokenKind.text) {
      tokens.add(token);
      continue;
    }
    final trimmed = token.raw.trim();
    if (trimmed.isNotEmpty) tokens.add(MarkupToken(MarkupTokenKind.text, trimmed));
  }
  if (tokens.every((token) => token.kind == MarkupTokenKind.text)) return source;

  final out = StringBuffer();
  final openNames = <String>[];

  void line(String text) {
    if (out.isNotEmpty) out.write('\n');
    final level = openNames.length < _maxIndentDepth ? openNames.length : _maxIndentDepth;
    out
      ..write('  ' * level)
      ..write(text);
  }

  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    switch (token.kind) {
      case MarkupTokenKind.close:
        final index = openNames.lastIndexOf(token.name);
        if (index != -1) openNames.removeRange(index, openNames.length);
        line(token.raw);
      case MarkupTokenKind.open:
        final next = i + 1 < tokens.length ? tokens[i + 1] : null;
        final afterNext = i + 2 < tokens.length ? tokens[i + 2] : null;
        if (next != null && next.kind == MarkupTokenKind.close && next.name == token.name) {
          line('${token.raw}${next.raw}');
          i += 1;
        } else if (next != null &&
            next.kind == MarkupTokenKind.text &&
            afterNext != null &&
            afterNext.kind == MarkupTokenKind.close &&
            afterNext.name == token.name &&
            !next.raw.contains('\n')) {
          line('${token.raw}${next.raw}${afterNext.raw}');
          i += 2;
        } else {
          line(token.raw);
          openNames.add(token.name);
        }
      case MarkupTokenKind.selfClosing ||
            MarkupTokenKind.rawElement ||
            MarkupTokenKind.other ||
            MarkupTokenKind.text:
        line(token.raw);
    }
  }
  return out.toString();
}
