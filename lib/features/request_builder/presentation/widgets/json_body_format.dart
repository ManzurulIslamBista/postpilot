/// Outcome of reformatting a JSON body: the new [text], or [error] saying why
/// the input is not JSON. Exactly one of them is set.
final class JsonFormatResult {
  final String? text;
  final String? error;

  const JsonFormatResult.success(String this.text) : error = null;
  const JsonFormatResult.failure(String this.error) : text = null;
}

/// Beautifies and minifies a raw JSON request body. Both walk the original
/// text and only change the whitespace between tokens, so numbers (`1.0`,
/// `12345678901234567890`), string escapes, key order and duplicate keys come
/// out exactly as written; a decode/encode round trip would change them.
///
/// Input must be strict JSON, except that a `{{variable}}` placeholder is
/// accepted wherever a value may stand, because bodies are templates that are
/// only filled in on send (`{"id": {{userId}}}`).
abstract final class JsonBodyFormat {
  static JsonFormatResult beautify(String source) => _JsonScanner(source, pretty: true).run();

  static JsonFormatResult minify(String source) => _JsonScanner(source, pretty: false).run();
}

// Indentation stops growing past this depth so a pathologically nested body
// cannot make the output quadratically larger than the input.
const _maxIndentDepth = 64;

// Same name syntax as AppConstants.variablePattern, anchored by matchAsPrefix.
final _placeholder = RegExp(r'\{\{[\w.$-]+\}\}');

const _simpleEscapes = '"\\/bfnrt';

enum _State { value, valueOrEnd, keyOrEnd, key, colon, afterValue }

/// A single iterative pass (no recursion, so nesting depth cannot overflow the
/// stack) that validates while it writes.
final class _JsonScanner {
  final String _s;
  final bool pretty;
  final _out = StringBuffer();
  final _open = <int>[];
  final _indents = <String>[''];
  var _i = 0;

  _JsonScanner(this._s, {required this.pretty});

  JsonFormatResult run() {
    try {
      _scan();
      return JsonFormatResult.success(_out.toString());
    } on FormatException catch (e) {
      return JsonFormatResult.failure(_describe(e));
    }
  }

  void _scan() {
    if (_s.isNotEmpty && _s.codeUnitAt(0) == 0xFEFF) _i = 1;
    _skipSpace();
    if (_i >= _s.length) throw const FormatException('Nothing to format: the body is empty');

    var state = _State.value;
    while (true) {
      _skipSpace();
      if (_i >= _s.length) {
        if (state == _State.afterValue && _open.isEmpty) return;
        throw FormatException('Unexpected end of JSON', _s, _s.length);
      }
      final c = _s.codeUnitAt(_i);
      switch (state) {
        case _State.value:
          if (c == 0x5D && _open.isNotEmpty && _open.last == 0x5B) throw _at("Trailing comma before ']'");
          state = _readValue(c);
        case _State.valueOrEnd:
          if (c == 0x5D) {
            _closeEmpty(c);
            state = _State.afterValue;
          } else {
            _newline();
            state = _readValue(c);
          }
        case _State.keyOrEnd:
          if (c == 0x7D) {
            _closeEmpty(c);
            state = _State.afterValue;
          } else {
            _newline();
            _readKey(c);
            state = _State.colon;
          }
        case _State.key:
          if (c == 0x7D) throw _at("Trailing comma before '}'");
          _readKey(c);
          state = _State.colon;
        case _State.colon:
          if (c != 0x3A) throw _at("Expected ':' after the property name, found ${_found()}");
          _out.write(pretty ? ': ' : ':');
          _i++;
          state = _State.value;
        case _State.afterValue:
          state = _readAfterValue(c);
      }
    }
  }

  _State _readValue(int c) {
    if (c == 0x7B && !_s.startsWith('{{', _i)) {
      _openContainer(c);
      return _State.keyOrEnd;
    }
    if (c == 0x5B) {
      _openContainer(c);
      return _State.valueOrEnd;
    }
    if (c == 0x22) {
      _readString();
    } else {
      _readScalar(c);
    }
    return _State.afterValue;
  }

  _State _readAfterValue(int c) {
    if (_open.isEmpty) throw _at('Unexpected ${_found()} after the end of the JSON value');
    final isObject = _open.last == 0x7B;
    if (c == 0x2C) {
      _out.writeCharCode(c);
      _i++;
      _newline();
      return isObject ? _State.key : _State.value;
    }
    if (c == (isObject ? 0x7D : 0x5D)) {
      _open.removeLast();
      _newline();
      _out.writeCharCode(c);
      _i++;
      return _State.afterValue;
    }
    throw _at("Expected ',' or '${isObject ? '}' : ']'}', found ${_found()}");
  }

  void _openContainer(int c) {
    _out.writeCharCode(c);
    _open.add(c);
    _i++;
  }

  void _closeEmpty(int c) {
    _open.removeLast();
    _out.writeCharCode(c);
    _i++;
  }

  void _readKey(int c) {
    if (c != 0x22) throw _at('Expected a property name in double quotes, found ${_found()}');
    _readString();
  }

  void _readString() {
    final start = _i;
    _i++;
    while (true) {
      if (_i >= _s.length) throw FormatException('Unterminated string', _s, start);
      final c = _s.codeUnitAt(_i);
      if (c == 0x22) {
        _i++;
        break;
      }
      if (c < 0x20) throw _at('Unescaped control character in a string');
      if (c != 0x5C) {
        _i++;
        continue;
      }
      _i++;
      if (_i >= _s.length) throw FormatException('Unterminated string', _s, start);
      final escaped = _s.codeUnitAt(_i);
      if (escaped == 0x75) {
        for (var k = 1; k <= 4; k++) {
          if (_i + k >= _s.length || !_isHex(_s.codeUnitAt(_i + k))) {
            throw FormatException('Invalid \\u escape in a string', _s, _i - 1);
          }
        }
        _i += 5;
      } else if (_simpleEscapes.contains(String.fromCharCode(escaped))) {
        _i++;
      } else {
        throw FormatException('Invalid escape sequence in a string', _s, _i - 1);
      }
    }
    _out.write(_s.substring(start, _i));
  }

  void _readScalar(int c) {
    final start = _i;
    if (c == 0x7B) {
      final match = _placeholder.matchAsPrefix(_s, _i);
      if (match == null) throw _at('Invalid {{variable}} placeholder');
      _i = match.end;
    } else if (c == 0x2D || _isDigit(c)) {
      _readNumber();
    } else if (!(_takeWord('true') || _takeWord('false') || _takeWord('null'))) {
      throw _at('Expected a value, found ${_found()}');
    }
    _out.write(_s.substring(start, _i));
  }

  bool _takeWord(String word) {
    if (!_s.startsWith(word, _i)) return false;
    _i += word.length;
    return true;
  }

  void _readNumber() {
    final start = _i;
    if (_s.codeUnitAt(_i) == 0x2D) _i++;
    if (_i >= _s.length || !_isDigit(_s.codeUnitAt(_i))) throw FormatException('Invalid number', _s, start);
    if (_s.codeUnitAt(_i) == 0x30) {
      _i++;
      if (_i < _s.length && _isDigit(_s.codeUnitAt(_i))) {
        throw FormatException('Numbers cannot have leading zeros', _s, start);
      }
    } else {
      _skipDigits();
    }
    if (_i < _s.length && _s.codeUnitAt(_i) == 0x2E) {
      _i++;
      _requireDigits(start);
    }
    if (_i < _s.length && (_s.codeUnitAt(_i) | 0x20) == 0x65) {
      _i++;
      if (_i < _s.length && (_s.codeUnitAt(_i) == 0x2B || _s.codeUnitAt(_i) == 0x2D)) _i++;
      _requireDigits(start);
    }
  }

  void _requireDigits(int numberStart) {
    if (_i >= _s.length || !_isDigit(_s.codeUnitAt(_i))) throw FormatException('Invalid number', _s, numberStart);
    _skipDigits();
  }

  void _skipDigits() {
    while (_i < _s.length && _isDigit(_s.codeUnitAt(_i))) {
      _i++;
    }
  }

  void _skipSpace() {
    while (_i < _s.length) {
      final c = _s.codeUnitAt(_i);
      if (c != 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) return;
      _i++;
    }
  }

  void _newline() {
    if (!pretty) return;
    final level = _open.length < _maxIndentDepth ? _open.length : _maxIndentDepth;
    while (_indents.length <= level) {
      _indents.add('  ' * _indents.length);
    }
    _out
      ..write('\n')
      ..write(_indents[level]);
  }

  FormatException _at(String message) => FormatException(message, _s, _i);

  /// The offending character for a message: shown as itself when it is
  /// printable ASCII, by code point otherwise (a stray NBSP looks like a space).
  String _found() {
    var rune = _s.codeUnitAt(_i);
    if (rune >= 0xD800 && rune <= 0xDBFF && _i + 1 < _s.length) {
      final low = _s.codeUnitAt(_i + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) rune = 0x10000 + ((rune - 0xD800) << 10) + (low - 0xDC00);
    }
    if (rune > 0x20 && rune < 0x7F) return "'${String.fromCharCode(rune)}'";
    return 'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  }

  String _describe(FormatException e) {
    final offset = e.offset;
    if (offset == null) return e.message;
    var line = 1;
    var lineStart = 0;
    for (var i = 0; i < offset && i < _s.length; i++) {
      final c = _s.codeUnitAt(i);
      final crlf = c == 0x0D && i + 1 < _s.length && _s.codeUnitAt(i + 1) == 0x0A;
      if (c == 0x0A || (c == 0x0D && !crlf)) {
        line++;
        lineStart = i + 1;
      }
    }
    return 'Invalid JSON: ${e.message} (line $line, column ${offset - lineStart + 1})';
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static bool _isHex(int c) => _isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66);
}
