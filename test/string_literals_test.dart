import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/request_builder/domain/services/code_generators/string_literals.dart';

String _char(int code) => String.fromCharCode(code);

void main() {
  final loneSurrogate = _char(0xD800);
  final esc = _char(0x1B);

  group('lone surrogates', () {
    test('become U+FFFD everywhere, which is what utf8.encode would have sent', () {
      expect(javaString('a${loneSurrogate}b'), '"a\\ufffdb"');
      expect(kotlinString('a${loneSurrogate}b'), '"a\u{FFFD}b"');
      expect(goString('a${loneSurrogate}b'), '"a\u{FFFD}b"');
      expect(rString('a${loneSurrogate}b'), '"a\\ufffdb"');
      expect(shellQuote('a${loneSurrogate}b'), "\$'a\u{FFFD}b'");
    });
  });

  group('bidirectional controls', () {
    test('are written as escapes wherever the language has them, since rustc rejects them raw', () {
      final override = _char(0x202E);
      final isolate = _char(0x2066);
      expect(rustString('a${override}b$isolate'), r'"a\u{202e}b\u{2066}"');
      expect(goString('a${override}b'), '"a\\u202eb"');
      expect(kotlinString('a${override}b'), '"a\\u202eb"');
      expect(csharpString('a${override}b'), '"a\\u202eb"');
      expect(swiftString('a${override}b'), r'"a\u{202e}b"');
      expect(phpString('a${override}b'), r'"a\u{202e}b"');
      expect(rubyString('a${override}b'), r'"a\u{202e}b"');
      expect(powershellString('a${override}b'), '"a\$([char]0x202e)b"');
    });
  });

  group('jsString', () {
    test('is a JSON string with the two JS-only line separators escaped', () {
      expect(jsString('a"b\\c\n\t'), r'"a\"b\\c\n\t"');
      expect(jsString('${_char(0x2028)}${_char(0x2029)}'), '"\\u2028\\u2029"');
      expect(jsString('caf\u{e9} \u{1F600}'), '"caf\u{e9} \u{1F600}"');
    });
  });

  group('pythonString', () {
    test('escapes the quote, backslash and control characters', () {
      expect(pythonString("it's a\\b\n\r\t$esc"), r"'it\'s a\\b\n\r\t\x1b'");
    });
  });

  group('dartString', () {
    test('escapes the interpolation marker and the line separators', () {
      expect(dartString(r'$a ${b}'), r"'\$a \${b}'");
      expect(dartString("it's"), r"'it\'s'");
      expect(dartString(_char(0x2028)), "'\\u2028'");
    });
  });

  group('javaString', () {
    test('escapes controls in octal, because \\u000a would end the literal before the compiler sees it', () {
      expect(javaString('a\nb\r\t$esc\u{0}${_char(0x7F)}'), r'"a\nb\r\t\033\000\177"');
      expect(javaString(_char(0x0A)), r'"\n"');
    });

    test('escapes non-ASCII as UTF-16 code units so the source is pure ASCII', () {
      expect(javaString('caf\u{e9}'), '"caf\\u00e9"');
      expect(javaString('\u{1F600}'), '"\\ud83d\\ude00"');
      expect(javaString('"\\'), r'"\"\\"');
    });

    test('keeps a literal backslash-u from starting a unicode escape', () {
      expect(javaString(r'\u0041'), r'"\\u0041"');
    });
  });

  group('kotlinString and csharpString', () {
    test('Kotlin escapes the string template marker; C# does not need to', () {
      expect(kotlinString(r'$x ${y} {z}'), r'"\$x \${y} {z}"');
      expect(csharpString(r'$x ${y} {z}'), r'"$x ${y} {z}"');
    });

    test('write control characters and the C# line breaks as \\uXXXX', () {
      expect(kotlinString(esc), '"\\u001b"');
      expect(csharpString('$esc${_char(0x85)}${_char(0x2028)}${_char(0x2029)}'), '"\\u001b\\u0085\\u2028\\u2029"');
    });
  });

  group('goString', () {
    const json = '{\n  "a": 1\n}';

    test('prefers a raw string for plain quoted or multi-line text when asked', () {
      expect(goString(json, preferRaw: true), '`$json`');
      expect(goString(r'C:\dir', preferRaw: true), r'`C:\dir`');
      expect(goString(json), r'"{\n  \"a\": 1\n}"');
    });

    test('falls back to an interpreted string for backticks, CR, tabs and text with nothing to gain', () {
      expect(goString('a`b"', preferRaw: true), r'"a`b\""');
      expect(goString('a\r\n"b"', preferRaw: true), r'"a\r\n\"b\""');
      expect(goString('a\t"b"', preferRaw: true), r'"a\t\"b\""');
      expect(goString('plain', preferRaw: true), '"plain"');
    });

    test('writes control characters as \\uXXXX', () {
      expect(goString('$esc\u{feff}'), '"\\u001b\\ufeff"');
    });
  });

  group('rustString and swiftString', () {
    test('write control characters as \\u{...} and leave braces alone', () {
      expect(rustString('{}$esc'), r'"{}\u{1b}"');
      expect(swiftString('{}$esc\u{2028}'), r'"{}\u{1b}\u{2028}"');
    });

    test('Swift escapes the backslash that would start an interpolation', () {
      expect(swiftString(r'\(x)'), r'"\\(x)"');
    });
  });

  group('phpString', () {
    test('uses single quotes for plain text and escapes only the quote and backslash', () {
      expect(phpString(r"it's a\b $x {$y}"), r"""'it\'s a\\b $x {$y}'""");
      expect(phpString('a\nb'), "'a\nb'");
    });

    test(r'uses double quotes with every $ escaped when the text needs escapes', () {
      expect(phpString('\$x \${y} {\$z}\r\t$esc'), r'"\$x \${y} {\$z}\r\t\x1b"');
      expect(phpString('a\u{2028}'), r'"a\u{2028}"');
    });
  });

  group('rubyString', () {
    test('uses single quotes for plain text', () {
      expect(rubyString(r"it's #{x} a\b"), r"""'it\'s #{x} a\\b'""");
    });

    test('uses double quotes with every # escaped when the text needs escapes', () {
      expect(rubyString('#{x} #\$y #@z\r'), r'"\#{x} \#$y \#@z\r"');
      expect(rubyString(esc), r'"\x1b"');
    });
  });

  group('powershellString', () {
    test('doubles every character PowerShell reads as a single quote', () {
      final quotes = "'${_char(0x2018)}${_char(0x2019)}${_char(0x201A)}${_char(0x201B)}";
      final doubled = quotes.split('').map((c) => c * 2).join();
      expect(powershellString(quotes), "'$doubled'");
    });

    test('leaves everything else in single quotes as it is', () {
      expect(powershellString('a"b \$c `d` \\e\nf'), "'a\"b \$c `d` \\e\nf'");
    });

    test('switches to double quotes with backtick escapes for CR, tab and control characters', () {
      expect(powershellString('a\r\n\t\$b `c` "d" \\ $esc'), '"a`r`n`t`\$b ``c`` ""d"" \\ \$([char]0x1b)"');
    });

    test('doubles the typographic double quotes in a double-quoted string', () {
      final quotes = '${_char(0x201C)}${_char(0x201D)}${_char(0x201E)}';
      final doubled = quotes.split('').map((c) => c * 2).join();
      expect(powershellString('\t$quotes'), '"`t$doubled"');
    });
  });

  group('rString', () {
    test('escapes non-ASCII as \\u (BMP) and \\U (astral) and controls as \\x', () {
      expect(rString('caf\u{e9} \u{1F600}'), '"caf\\u00e9 \\U0001f600"');
      expect(rString('$esc\r\n\t"\\'), r'"\x1b\r\n\t\"\\"');
      expect(rString(r'$x {y} #z %s'), r'"$x {y} #z %s"');
    });
  });

  group('shell quoting', () {
    test("shellQuote wraps plain text in single quotes and closes and reopens around a '", () {
      expect(shellQuote("it's"), r"""'it'\''s'""");
      expect(shellQuote('{\n  "a": 1\n}'), "'{\n  \"a\": 1\n}'");
      expect(shellQuote(r'$HOME `x` \ !'), r"""'$HOME `x` \ !'""");
      expect(shellQuote(''), "''");
    });

    test('shellQuote uses ANSI-C quotes when the text holds CR, tab or other controls', () {
      expect(shellQuote("a\r\n\t'\\$esc"), r"$'a\r\n\t\'\\\x1b'");
    });

    test('shellQuote leaves controls raw inside single quotes when ANSI-C quoting is switched off', () {
      expect(shellQuote("a\r\n\t'b", ansiC: false), "'a\r\n\t'\\''b'");
      expect(shellQuote('plain', ansiC: false), "'plain'");
    });

    test('shellWord leaves safe words bare and quotes the rest', () {
      expect(shellWord('POST'), 'POST');
      expect(shellWord('a-b_c.d/e:f=g'), 'a-b_c.d/e:f=g');
      expect(shellWord('two words'), "'two words'");
      expect(shellWord(''), "''");
      expect(shellWord(r'$x'), r"'$x'");
    });

    test('shellLines joins with continuation backslashes and indents continuation lines', () {
      expect(shellLines(['a', 'b', 'c']), 'a \\\nb \\\nc');
      expect(shellLines(['a', 'b', 'c'], indent: '  '), 'a \\\n  b \\\n  c');
      expect(shellLines(['only']), 'only');
    });
  });
}
