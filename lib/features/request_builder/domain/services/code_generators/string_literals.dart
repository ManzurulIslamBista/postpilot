import 'dart:convert';

// One quoting function per target language, each returning the complete
// literal (quotes included) that evaluates back to exactly the input.
// Snippets embed request bodies verbatim, and multipart bodies carry CRLFs,
// so control characters are always spelled out instead of left raw.

typedef _Escape = String? Function(int rune);

String _literal(String value, String open, String close, _Escape escape) {
  final out = StringBuffer(open);
  for (final rune in value.runes) {
    // utf8.encode turns a lone surrogate into U+FFFD, so that is what is sent.
    final safe = rune >= 0xD800 && rune <= 0xDFFF ? 0xFFFD : rune;
    final escaped = escape(safe);
    if (escaped == null) {
      out.writeCharCode(safe);
    } else {
      out.write(escaped);
    }
  }
  return (out..write(close)).toString();
}

bool _isControl(int r) => r < 0x20 || r == 0x7F;

// Characters better written as escapes: line breaks to some lexers (C#,
// PowerShell), a BOM, and the bidirectional overrides and isolates, which make
// source read differently from how it runs and which rustc refuses in a literal.
bool _isInvisible(int r) =>
    r == 0x85 || r == 0x2028 || r == 0x2029 || r == 0xFEFF || (r >= 0x202A && r <= 0x202E) || (r >= 0x2066 && r <= 0x2069);

/// Whether [value] can sit raw between single quotes: only printable text and
/// line feeds. Anything else (CR, tab, ...) must be written as an escape.
bool _isPlain(String value) => value.runes.every(
      (r) => r == 0x0A || !(_isControl(r) || _isInvisible(r) || (r >= 0xD800 && r <= 0xDFFF)),
    );

String _hex(int value, int width) => value.toRadixString(16).padLeft(width, '0');

String _doubleQuoted(String value, String Function(int rune) unicode, {Map<int, String> extra = const {}}) =>
    _literal(
      value,
      '"',
      '"',
      (r) =>
          extra[r] ??
          switch (r) {
            0x22 => r'\"',
            0x5C => r'\\',
            0x0A => r'\n',
            0x0D => r'\r',
            0x09 => r'\t',
            _ when _isControl(r) || _isInvisible(r) => unicode(r),
            _ => null,
          },
    );

String _unicode4(int r) => '\\u${_hex(r, 4)}';

String _unicodeBraced(int r) => '\\u{${_hex(r, 1)}}';

/// JSON strings are JavaScript string literals, except that engines before
/// ES2019 reject a raw U+2028/U+2029 inside one.
String jsString(String value) =>
    jsonEncode(value).replaceAll('\u{2028}', '\\u2028').replaceAll('\u{2029}', '\\u2029');

String pythonString(String value) => _literal(
      value,
      "'",
      "'",
      (r) => switch (r) {
        0x27 => r"\'",
        0x5C => r'\\',
        0x0A => r'\n',
        0x0D => r'\r',
        0x09 => r'\t',
        _ when _isControl(r) => '\\x${_hex(r, 2)}',
        _ => null,
      },
    );

/// `$` starts an interpolation in a Dart string, so it is always escaped.
String dartString(String value) => _literal(
      value,
      "'",
      "'",
      (r) => switch (r) {
        0x27 => r"\'",
        0x5C => r'\\',
        0x24 => r'\$',
        0x0A => r'\n',
        0x0D => r'\r',
        0x09 => r'\t',
        _ when _isControl(r) => '\\x${_hex(r, 2)}',
        _ when _isInvisible(r) => _unicode4(r),
        _ => null,
      },
    );

/// Java translates `\uXXXX` before it lexes, so a control character can never
/// be written as `\u000a` (that would end the literal); those use octal.
/// Non-ASCII is escaped too because `javac` reads sources in the platform
/// charset before JDK 18.
String javaString(String value) => _literal(
      value,
      '"',
      '"',
      (r) => switch (r) {
        0x22 => r'\"',
        0x5C => r'\\',
        0x0A => r'\n',
        0x0D => r'\r',
        0x09 => r'\t',
        _ when _isControl(r) => '\\${r.toRadixString(8).padLeft(3, '0')}',
        _ when r > 0xFFFF => _utf16Pair(r),
        _ when r > 0x7F => _unicode4(r),
        _ => null,
      },
    );

String _utf16Pair(int r) {
  final offset = r - 0x10000;
  return _unicode4(0xD800 + (offset >> 10)) + _unicode4(0xDC00 + (offset & 0x3FF));
}

String kotlinString(String value) => _doubleQuoted(value, _unicode4, extra: {0x24: r'\$'});

/// C# lexes U+0085, U+2028 and U+2029 as line breaks, which would end the literal.
String csharpString(String value) => _doubleQuoted(value, _unicode4);

/// Go's raw strings drop every CR and cannot hold a backtick, so [preferRaw]
/// only takes effect for plain text that gains readability (quotes, backslashes
/// or line feeds); everything else is an interpreted string.
String goString(String value, {bool preferRaw = false}) {
  if (preferRaw && _isPlain(value) && !value.contains('`') && value.contains(RegExp(r'["\\\n]'))) {
    return '`$value`';
  }
  return _doubleQuoted(value, _unicode4);
}

String rustString(String value) => _doubleQuoted(value, _unicodeBraced);

/// `\(` starts an interpolation in Swift; escaping every backslash rules it out.
String swiftString(String value) => _doubleQuoted(value, _unicodeBraced);

String _phpOrRubyDouble(String value, {required Map<int, String> extra}) => _doubleQuoted(
      value,
      (r) => _isControl(r) ? '\\x${_hex(r, 2)}' : _unicodeBraced(r),
      extra: extra,
    );

/// Single quotes interpolate nothing, so plain text uses them; only `\` and
/// `'` need escaping there. Double quotes take over for CR/tab/control text.
String phpString(String value) => _isPlain(value)
    ? "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'"
    : _phpOrRubyDouble(value, extra: {0x24: r'\$'});

/// Same single-vs-double split as [phpString]; in double quotes every `#` is
/// escaped because `#{`, `#$` and `#@` all interpolate.
String rubyString(String value) => _isPlain(value)
    ? "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'"
    : _phpOrRubyDouble(value, extra: {0x23: r'\#'});

// PowerShell treats these typographic quotes as the ASCII quote of their kind.
final _psSingleQuotes = RegExp('[\'\u{2018}\u{2019}\u{201A}\u{201B}]');

String powershellString(String value) {
  if (_isPlain(value)) {
    return "'${value.replaceAllMapped(_psSingleQuotes, (m) => '${m[0]}${m[0]}')}'";
  }
  return _literal(
    value,
    '"',
    '"',
    (r) => switch (r) {
      0x60 => '``',
      0x24 => r'`$',
      0x22 || 0x201C || 0x201D || 0x201E => String.fromCharCode(r) * 2,
      0x0A => '`n',
      0x0D => '`r',
      0x09 => '`t',
      _ when _isControl(r) || _isInvisible(r) => '\$([char]0x${_hex(r, 2)})',
      _ => null,
    },
  );
}

/// Non-ASCII is escaped because R on Windows reads scripts in the ANSI code
/// page, which garbles it, while `\u` escapes are independent of the locale.
String rString(String value) => _literal(
      value,
      '"',
      '"',
      (r) => switch (r) {
        0x22 => r'\"',
        0x5C => r'\\',
        0x0A => r'\n',
        0x0D => r'\r',
        0x09 => r'\t',
        _ when _isControl(r) => '\\x${_hex(r, 2)}',
        _ when r > 0xFFFF => '\\U${_hex(r, 8)}',
        _ when r > 0x7F => _unicode4(r),
        _ => null,
      },
    );

/// POSIX single quotes for plain text; bash/zsh ANSI-C quotes (`$'...'`) when
/// the value holds CR, tab or other control characters, which a terminal
/// would otherwise treat as keystrokes when the snippet is pasted.
/// With [ansiC] false such characters stay raw inside single quotes, for
/// output that something has to parse back and cannot read `$'...'`.
String shellQuote(String value, {bool ansiC = true}) {
  if (!ansiC || _isPlain(value)) return "'${value.replaceAll("'", r"'\''")}'";
  return _literal(
    value,
    r"$'",
    "'",
    (r) => switch (r) {
      0x27 => r"\'",
      0x5C => r'\\',
      0x0A => r'\n',
      0x0D => r'\r',
      0x09 => r'\t',
      _ when _isControl(r) => '\\x${_hex(r, 2)}',
      _ => null,
    },
  );
}

final _shellSafeWord = RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$');

String shellWord(String value) => _shellSafeWord.hasMatch(value) ? value : shellQuote(value);

/// Joins command [lines] with trailing backslashes; continuation lines get [indent].
String shellLines(List<String> lines, {String indent = ''}) => [
      for (var i = 0; i < lines.length; i++)
        '${i == 0 ? '' : indent}${lines[i]}${i == lines.length - 1 ? '' : ' \\'}',
    ].join('\n');
