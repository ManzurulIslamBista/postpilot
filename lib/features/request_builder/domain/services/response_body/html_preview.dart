import 'markup_scanner.dart';

// Digit counts are capped so that the parsed value can never overflow.
final _entity = RegExp(r'&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[A-Za-z][A-Za-z0-9]{1,31});');

const _blockElements = <String>{
  'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'tr', 'section', 'article', 'header', 'footer', 'blockquote',
  'pre', 'title'
};

const _namedEntities = <String, String>{
  'nbsp': ' ',
  'lt': '<',
  'gt': '>',
  'amp': '&',
  'quot': '"',
  'apos': "'",
  'copy': '\u00A9',
  'reg': '\u00AE',
  'trade': '\u2122',
  'mdash': '\u2014',
  'ndash': '\u2013',
  'hellip': '\u2026',
  'laquo': '\u00AB',
  'raquo': '\u00BB',
  'lsquo': '\u2018',
  'rsquo': '\u2019',
  'ldquo': '\u201C',
  'rdquo': '\u201D',
  'bull': '\u2022',
  'middot': '\u00B7',
  'euro': '\u20AC',
  'pound': '\u00A3',
  'yen': '\u00A5',
  'cent': '\u00A2',
  'sect': '\u00A7',
  'para': '\u00B6',
  'deg': '\u00B0',
  'plusmn': '\u00B1',
  'times': '\u00D7',
  'divide': '\u00F7',
  'larr': '\u2190',
  'rarr': '\u2192',
  'uarr': '\u2191',
  'darr': '\u2193',
};

/// Plain-text rendering of [html]: markup, scripts, styles and comments are
/// dropped, block elements become line breaks and entities are decoded.
String htmlToPlainText(String html) {
  final out = StringBuffer();
  for (final token in scanMarkup(html, html: true)) {
    switch (token.kind) {
      case MarkupTokenKind.text:
        out.write(_decodeEntities(token.raw));
      case MarkupTokenKind.close:
        if (_blockElements.contains(token.name)) out.write('\n');
      case MarkupTokenKind.open || MarkupTokenKind.selfClosing:
        if (token.name == 'br') out.write('\n');
      case MarkupTokenKind.rawElement:
        // Scripts and styles are not text; the other raw elements are.
        if (token.name == 'pre' || token.name == 'textarea') {
          out.write(_decodeEntities(_innerText(token.raw)));
          if (token.name == 'pre') out.write('\n');
        }
      case MarkupTokenKind.other:
        break;
    }
  }
  return _tidy(out.toString());
}

String _decodeEntities(String text) => text.replaceAllMapped(_entity, (match) {
      final body = match[1]!;
      if (!body.startsWith('#')) return _namedEntities[body] ?? match[0]!;
      final isHex = body[1] == 'x' || body[1] == 'X';
      final code = int.parse(body.substring(isHex ? 2 : 1), radix: isHex ? 16 : 10);
      // A NUL, an out-of-range value or a lone surrogate is not text; a
      // surrogate would also make Flutter's text engine throw.
      final valid = code > 0 && code <= 0x10FFFF && (code < 0xD800 || code > 0xDFFF);
      return valid ? String.fromCharCode(code) : '\uFFFD';
    });

// The text of a raw element: what lies between its start and end tags, minus
// any markup inside.
String _innerText(String element) {
  final start = element.indexOf('>') + 1;
  final end = element.lastIndexOf('</');
  final inner = end > start ? element.substring(start, end) : '';
  final out = StringBuffer();
  var index = 0;
  while (index < inner.length) {
    final lt = inner.indexOf('<', index);
    if (lt == -1) {
      out.write(inner.substring(index));
      break;
    }
    out.write(inner.substring(index, lt));
    final gt = inner.indexOf('>', lt);
    if (gt == -1) {
      out.write(inner.substring(lt));
      break;
    }
    index = gt + 1;
  }
  return out.toString();
}

// Drops trailing spaces and collapses runs of blank lines into one.
String _tidy(String text) {
  final lines = <String>[];
  var blankRun = 0;
  for (final line in text.split('\n')) {
    final trimmed = line.trimRight();
    if (trimmed.isEmpty) {
      if (++blankRun > 1) continue;
    } else {
      blankRun = 0;
    }
    lines.add(trimmed);
  }
  return lines.join('\n').trim();
}
