/// A tiny reader for the Python literals found in Odoo scripts: strings,
/// numbers, `True/False/None`, lists, tuples and dicts. Anything else (a
/// variable such as `password`) becomes the string `{{password}}` so it lands
/// in the converted request as a PostPilot variable.
final class PythonLiteral {
  final String _s;
  int _i = 0;

  /// When true an unknown name is an error instead of a `{{name}}` placeholder.
  final bool _strict;
  PythonLiteral._(this._s, [this._strict = false]);

  /// Arguments of the first call to a function named [function] in [source]:
  /// positional values and `name=value` keywords. `null` when the call is not
  /// found or cannot be read.
  static ({List<Object?> positional, Map<String, Object?> keywords})? callArguments(String source, String function) {
    final match = RegExp('${RegExp.escape(function)}\\s*\\(').firstMatch(source);
    if (match == null) return null;
    final reader = PythonLiteral._(source).._i = match.end;
    try {
      final positional = <Object?>[];
      final keywords = <String, Object?>{};
      while (true) {
        reader._skip();
        if (reader._peek == ')') return (positional: positional, keywords: keywords);
        final keyword = reader._tryKeyword();
        final value = reader._value();
        if (keyword != null) {
          keywords[keyword] = value;
        } else {
          positional.add(value);
        }
        reader._skip();
        if (reader._peek == ',') {
          reader._i++;
        } else if (reader._peek != ')') {
          return null;
        }
      }
    } on FormatException {
      return null;
    }
  }

  /// A single literal, or `null` if [text] is not one. With [strict] a bare
  /// name (a variable, a call) makes the text "not a literal" instead of turning
  /// into a `{{name}}` placeholder; use it for text a person typed that may
  /// just be a word.
  static Object? parse(String text, {bool strict = false}) {
    final reader = PythonLiteral._(text, strict);
    try {
      final v = reader._value();
      reader._skip();
      return reader._i >= text.length ? v : null;
    } on FormatException {
      return null;
    }
  }

  String get _peek => _i < _s.length ? _s[_i] : '';

  void _skip() {
    while (_i < _s.length) {
      final c = _s[_i];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        _i++;
      } else if (c == '#') {
        while (_i < _s.length && _s[_i] != '\n') {
          _i++;
        }
      } else if (c == '\\' && _i + 1 < _s.length && (_s[_i + 1] == '\n' || _s[_i + 1] == '\r')) {
        _i += 2;
      } else {
        break;
      }
    }
  }

  String? _tryKeyword() {
    final m = RegExp(r'([A-Za-z_]\w*)\s*=(?!=)').matchAsPrefix(_s, _i);
    if (m == null) return null;
    _i = m.end;
    return m[1];
  }

  Object? _value() {
    _skip();
    final c = _peek;
    if (c.isEmpty) throw const FormatException('Unexpected end');
    if (c == '[') return _sequence(']');
    if (c == '(') {
      return _sequence(')');
    }
    if (c == '{') return _dict();
    if (c == '"' || c == "'") return _string();
    final prefixed = RegExp(r'''([rRuUbB])(["'])''').matchAsPrefix(_s, _i);
    if (prefixed != null) {
      _i++;
      return _string(raw: prefixed[1]!.toLowerCase() == 'r');
    }
    final number = RegExp(r'-?\d+(\.\d+)?([eE][+-]?\d+)?').matchAsPrefix(_s, _i);
    if (number != null) {
      _i = number.end;
      final t = number[0]!;
      return t.contains(RegExp(r'[.eE]')) ? double.parse(t) : int.parse(t);
    }
    final word = RegExp(r'[A-Za-z_][\w.]*').matchAsPrefix(_s, _i);
    if (word != null) {
      _i = word.end;
      final w = word[0]!;
      switch (w) {
        case 'True':
          return true;
        case 'False':
          return false;
        case 'None':
          return null;
      }
      if (_strict) throw FormatException('"$w" is not a literal');
      _skip();
      if (_peek == '(') {
        // A call such as datetime.now(): keep it as an expression placeholder.
        var depth = 0;
        final start = _i;
        while (_i < _s.length) {
          if (_s[_i] == '(') depth++;
          if (_s[_i] == ')') {
            depth--;
            if (depth == 0) {
              _i++;
              break;
            }
          }
          _i++;
        }
        return '{{$w${_s.substring(start, _i).replaceAll(RegExp(r'\s+'), '')}}}';
      }
      return '{{$w}}';
    }
    throw FormatException('Unexpected "$c"');
  }

  List<Object?> _sequence(String close) {
    _i++;
    final items = <Object?>[];
    while (true) {
      _skip();
      if (_peek == close) {
        _i++;
        return items;
      }
      items.add(_value());
      _skip();
      if (_peek == ',') {
        _i++;
      } else if (_peek != close) {
        throw FormatException('Expected "," or "$close"');
      }
    }
  }

  Map<String, Object?> _dict() {
    _i++;
    final map = <String, Object?>{};
    while (true) {
      _skip();
      if (_peek == '}') {
        _i++;
        return map;
      }
      final key = _value();
      _skip();
      if (_peek != ':') throw const FormatException('Expected ":"');
      _i++;
      map['$key'] = _value();
      _skip();
      if (_peek == ',') {
        _i++;
      } else if (_peek != '}') {
        throw const FormatException('Expected "," or "}"');
      }
    }
  }

  String _string({bool raw = false}) {
    final quote = _s[_i];
    final triple = _s.startsWith(quote * 3, _i);
    _i += triple ? 3 : 1;
    final b = StringBuffer();
    while (_i < _s.length) {
      final c = _s[_i];
      if (triple ? _s.startsWith(quote * 3, _i) : c == quote) {
        _i += triple ? 3 : 1;
        return b.toString();
      }
      if (c == '\\' && !raw && _i + 1 < _s.length) {
        _i = _escape(b, _i + 1);
      } else {
        b.write(c);
        _i++;
      }
    }
    throw const FormatException('Unterminated string');
  }

  /// Writes what the escape at [at] (the index after the backslash) stands for
  /// into [b] and returns the index after it. An unknown escape keeps its
  /// backslash, as Python does: `'\d'` is two characters.
  int _escape(StringBuffer b, int at) {
    final n = _s[at];
    int hex(int digits) {
      final end = at + 1 + digits;
      final code = end <= _s.length ? int.tryParse(_s.substring(at + 1, end), radix: 16) : null;
      if (code == null || code > 0x10FFFF) throw FormatException('Bad \\$n escape');
      b.writeCharCode(code);
      return end;
    }

    switch (n) {
      case 'n':
        b.write('\n');
      case 't':
        b.write('\t');
      case 'r':
        b.write('\r');
      case '0':
        b.writeCharCode(0);
      case '\\' || "'" || '"':
        b.write(n);
      case '\n': // a backslash at the end of a line continues the string
        break;
      case '\r':
        return at + 1 < _s.length && _s[at + 1] == '\n' ? at + 2 : at + 1;
      case 'x':
        return hex(2);
      case 'u':
        return hex(4);
      case 'U':
        return hex(8);
      default:
        b.write('\\$n');
    }
    return at + 1;
  }
}
