import 'dart:typed_data';

enum MarkupTokenKind {
  /// `<a href="x">`
  open,

  /// `</a>`
  close,

  /// `<br/>`, or a void element such as `<br>` in HTML.
  selfClosing,

  /// A whole `<script>`, `<style>`, `<pre>` or `<textarea>` element (HTML only), content included.
  rawElement,

  /// A comment, CDATA section, processing instruction or declaration.
  other,

  /// Anything between tags, untrimmed.
  text,
}

class MarkupToken {
  final MarkupTokenKind kind;
  final String raw;

  /// The tag name (lower-cased for HTML); empty for text and [MarkupTokenKind.other].
  final String name;

  const MarkupToken(this.kind, this.raw, [this.name = '']);
}

const _rawElements = <String>{'script', 'style', 'pre', 'textarea'};
const _voidElements = <String>{
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'
};

/// Splits [source] into tags and text in one linear pass. It never fails: a
/// `<` that does not begin markup is just text. Every search for a
/// terminator either succeeds and moves past it, or fails once and is
/// remembered, so a hostile body cannot make the scan quadratic.
///
/// Tags end at the first `>`, so a `>` inside a quoted attribute value ends
/// its tag early.
List<MarkupToken> scanMarkup(String source, {required bool html}) => _Scanner(source, html).scan();

class _Scanner {
  final String source;
  final bool html;
  final _tokens = <MarkupToken>[];
  String? _asciiLower;

  var _noTagEnd = false;
  var _noCommentEnd = false;
  var _noCdataEnd = false;
  var _noInstructionEnd = false;
  final _unclosedRawElements = <String>{};

  _Scanner(this.source, this.html);

  List<MarkupToken> scan() {
    var textStart = 0;
    var index = 0;
    while (true) {
      final lt = source.indexOf('<', index);
      if (lt == -1) break;
      final token = _readMarkup(lt);
      if (token == null) {
        index = lt + 1;
        continue;
      }
      if (lt > textStart) _tokens.add(MarkupToken(MarkupTokenKind.text, source.substring(textStart, lt)));
      _tokens.add(token);
      index = textStart = lt + token.raw.length;
    }
    if (textStart < source.length) _tokens.add(MarkupToken(MarkupTokenKind.text, source.substring(textStart)));
    return _tokens;
  }

  MarkupToken? _readMarkup(int lt) {
    final next = _unitAt(lt + 1);
    if (next == 0x21) return _readDeclaration(lt); // <!
    if (next == 0x3F) {
      // <?
      final end = _indexOfEnd('?>', lt + 2, missing: _noInstructionEnd);
      if (end == -1) {
        _noInstructionEnd = true;
        return null;
      }
      return MarkupToken(MarkupTokenKind.other, source.substring(lt, end));
    }
    if (next == 0x2F) {
      // </
      if (!_isNameStart(_unitAt(lt + 2))) return null;
      final gt = _indexOfTagEnd(lt + 2);
      if (gt == -1) return null;
      return MarkupToken(MarkupTokenKind.close, source.substring(lt, gt + 1), _nameAt(lt + 2));
    }
    if (!_isNameStart(next)) return null;
    final gt = _indexOfTagEnd(lt + 1);
    if (gt == -1) return null;
    final raw = source.substring(lt, gt + 1);
    final name = _nameAt(lt + 1);
    if (raw.endsWith('/>') || (html && _voidElements.contains(name))) {
      return MarkupToken(MarkupTokenKind.selfClosing, raw, name);
    }
    if (html && _rawElements.contains(name)) {
      final end = _rawElementEnd(name, gt + 1);
      if (end != -1) return MarkupToken(MarkupTokenKind.rawElement, source.substring(lt, end), name);
    }
    return MarkupToken(MarkupTokenKind.open, raw, name);
  }

  MarkupToken? _readDeclaration(int lt) {
    if (source.startsWith('<!--', lt)) {
      final end = _indexOfEnd('-->', lt + 4, missing: _noCommentEnd);
      if (end == -1) {
        _noCommentEnd = true;
        return null;
      }
      return MarkupToken(MarkupTokenKind.other, source.substring(lt, end));
    }
    if (source.startsWith('<![CDATA[', lt)) {
      final end = _indexOfEnd(']]>', lt + 9, missing: _noCdataEnd);
      if (end == -1) {
        _noCdataEnd = true;
        return null;
      }
      return MarkupToken(MarkupTokenKind.other, source.substring(lt, end));
    }
    if (!_isLetter(_unitAt(lt + 2))) return null;
    final gt = _indexOfTagEnd(lt + 2);
    return gt == -1 ? null : MarkupToken(MarkupTokenKind.other, source.substring(lt, gt + 1));
  }

  // The index just past [terminator], or -1.
  int _indexOfEnd(String terminator, int from, {required bool missing}) {
    if (missing) return -1;
    final index = source.indexOf(terminator, from);
    return index == -1 ? -1 : index + terminator.length;
  }

  int _indexOfTagEnd(int from) {
    if (_noTagEnd) return -1;
    final gt = source.indexOf('>', from);
    if (gt == -1) _noTagEnd = true;
    return gt;
  }

  // The index just past the closing tag of a raw element whose start tag
  // ends at [from], or -1 when it is never closed.
  int _rawElementEnd(String name, int from) {
    if (_unclosedRawElements.contains(name)) return -1;
    final lower = _asciiLower ??= _toAsciiLowerCase(source);
    final close = lower.indexOf('</$name', from);
    final gt = close == -1 ? -1 : source.indexOf('>', close);
    if (gt == -1) {
      _unclosedRawElements.add(name);
      return -1;
    }
    return gt + 1;
  }

  String _nameAt(int from) {
    var end = from;
    while (end < source.length) {
      final unit = source.codeUnitAt(end);
      if (unit <= 0x20 || unit == 0x2F || unit == 0x3E) break;
      end++;
    }
    final name = source.substring(from, end);
    return html ? name.toLowerCase() : name;
  }

  int _unitAt(int index) => index < source.length ? source.codeUnitAt(index) : -1;

  static bool _isLetter(int unit) => (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);

  static bool _isNameStart(int unit) => _isLetter(unit) || unit == 0x5F || unit == 0x3A;

  // Unlike toLowerCase(), never changes the string's length, so offsets stay valid.
  static String _toAsciiLowerCase(String text) {
    final units = Uint16List(text.length);
    for (var i = 0; i < units.length; i++) {
      final unit = text.codeUnitAt(i);
      units[i] = unit >= 0x41 && unit <= 0x5A ? unit + 0x20 : unit;
    }
    return String.fromCharCodes(units);
  }
}
