import 'dart:math';

/// Makes a string that matches a JSON-schema `pattern`, for the simple patterns APIs use for codes and identifiers
/// (`^[A-Z]{3}-\d{4}$`, `^(?:red|green|blue)$`, `^\+?\d{7,12}$`). It handles literals, escapes (`\d \w \s`, `\.`),
/// classes, groups, alternation and the quantifiers `* + ? {n} {n,m}`. Anything it cannot read (lookahead, back
/// references, Unicode properties) or a result the pattern then rejects gives null, and the caller falls back to
/// ordinary text.
abstract final class MockPattern {
  static String? generate(String pattern, Random random) {
    try {
      final parser = _Parser(pattern);
      final node = parser.parse();
      if (node == null) return null;
      final text = node.generate(random);
      return RegExp(pattern).hasMatch(text) ? text : null;
    } catch (_) {
      return null;
    }
  }
}

const _word = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_';
const _digits = '0123456789';
const _space = ' ';
const _printable = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

abstract class _Node {
  String generate(Random random);
}

final class _Literal implements _Node {
  final String text;
  const _Literal(this.text);

  @override
  String generate(Random random) => text;
}

final class _OneOf implements _Node {
  final List<String> chars;
  const _OneOf(this.chars);

  @override
  String generate(Random random) => chars[random.nextInt(chars.length)];
}

final class _Sequence implements _Node {
  final List<_Node> parts;
  const _Sequence(this.parts);

  @override
  String generate(Random random) => parts.map((p) => p.generate(random)).join();
}

final class _Choice implements _Node {
  final List<_Node> options;
  const _Choice(this.options);

  @override
  String generate(Random random) => options[random.nextInt(options.length)].generate(random);
}

final class _Repeat implements _Node {
  final _Node node;
  final int min;
  final int max;
  const _Repeat(this.node, this.min, this.max);

  @override
  String generate(Random random) {
    final count = min + (max > min ? random.nextInt(max - min + 1) : 0);
    return [for (var i = 0; i < count; i++) node.generate(random)].join();
  }
}

final class _Parser {
  final String source;
  int _pos = 0;

  _Parser(this.source);

  _Node? parse() {
    final node = _alternation();
    return _pos == source.length ? node : null;
  }

  bool get _done => _pos >= source.length;

  _Node _alternation() {
    final options = [_sequence()];
    while (!_done && source[_pos] == '|') {
      _pos++;
      options.add(_sequence());
    }
    return options.length == 1 ? options.single : _Choice(options);
  }

  _Node _sequence() {
    final parts = <_Node>[];
    while (!_done && source[_pos] != '|' && source[_pos] != ')') {
      final atom = _atom();
      if (atom == null) continue;
      parts.add(_quantified(atom));
    }
    return _Sequence(parts);
  }

  /// Null for something that matches the empty string (an anchor).
  _Node? _atom() {
    final c = source[_pos++];
    switch (c) {
      case '^' || r'$':
        return null;
      case '.':
        return _OneOf(_printable.split(''));
      case '(':
        if (source.startsWith('?:', _pos)) {
          _pos += 2;
        } else if (source.startsWith('?', _pos)) {
          throw const FormatException('lookaround or named group');
        }
        final inner = _alternation();
        if (_done || source[_pos] != ')') throw const FormatException('unclosed group');
        _pos++;
        return inner;
      case '[':
        return _charClass();
      case r'\':
        return _escape();
      case '*' || '+' || '?' || '{':
        throw const FormatException('nothing to repeat');
      default:
        return _Literal(c);
    }
  }

  _Node _escape() {
    if (_done) throw const FormatException('dangling backslash');
    final c = source[_pos++];
    switch (c) {
      case 'd':
        return _OneOf(_digits.split(''));
      case 'w':
        return _OneOf(_word.split(''));
      case 's':
        return const _OneOf([_space]);
      case 'D' || 'W' || 'S':
        return _OneOf('abcxyz'.split(''));
      case 'b' || 'B':
        return const _Literal('');
      case 'n':
        return const _Literal('\n');
      case 't':
        return const _Literal('\t');
      case 'p' || 'P' || 'k' || 'u' || 'x' || 'c':
        throw const FormatException('unsupported escape');
      default:
        if (RegExp(r'[0-9]').hasMatch(c)) throw const FormatException('back reference');
        return _Literal(c);
    }
  }

  _Node _charClass() {
    var negated = false;
    if (!_done && source[_pos] == '^') {
      negated = true;
      _pos++;
    }
    final chars = <String>{};
    var first = true;
    while (!_done && (source[_pos] != ']' || first)) {
      first = false;
      var c = source[_pos++];
      if (c == r'\') {
        if (_done) throw const FormatException('dangling backslash');
        final e = source[_pos++];
        switch (e) {
          case 'd':
            chars.addAll(_digits.split(''));
            continue;
          case 'w':
            chars.addAll(_word.split(''));
            continue;
          case 's':
            chars.add(_space);
            continue;
          case 'n':
            c = '\n';
          case 't':
            c = '\t';
          case 'p' || 'P' || 'u' || 'x':
            throw const FormatException('unsupported escape');
          default:
            c = e;
        }
      }
      if (_pos + 1 < source.length && source[_pos] == '-' && source[_pos + 1] != ']') {
        _pos++;
        var end = source[_pos++];
        if (end == r'\') {
          if (_done) throw const FormatException('dangling backslash');
          end = source[_pos++];
        }
        final from = c.codeUnitAt(0);
        final to = end.codeUnitAt(0);
        if (to < from) throw const FormatException('reversed range');
        for (var code = from; code <= to; code++) {
          chars.add(String.fromCharCode(code));
        }
      } else {
        chars.add(c);
      }
    }
    if (_done) throw const FormatException('unclosed class');
    _pos++; // ]
    if (negated) {
      final allowed = _printable.split('').where((ch) => !chars.contains(ch)).toList();
      if (allowed.isEmpty) throw const FormatException('empty class');
      return _OneOf(allowed);
    }
    if (chars.isEmpty) throw const FormatException('empty class');
    return _OneOf(chars.toList());
  }

  _Node _quantified(_Node atom) {
    if (_done) return atom;
    var min = 1;
    var max = 1;
    switch (source[_pos]) {
      case '*':
        min = 0;
        max = 3;
        _pos++;
      case '+':
        min = 1;
        max = 3;
        _pos++;
      case '?':
        min = 0;
        max = 1;
        _pos++;
      case '{':
        final close = source.indexOf('}', _pos);
        if (close < 0) return atom;
        final body = source.substring(_pos + 1, close);
        final m = RegExp(r'^(\d+)(?:(,)(\d*))?$').firstMatch(body);
        if (m == null) return atom;
        min = int.parse(m[1]!);
        max = m[2] == null ? min : (m[3]!.isEmpty ? min + 3 : int.parse(m[3]!));
        if (max < min || max > 200) throw const FormatException('bad repeat');
        _pos = close + 1;
      default:
        return atom;
    }
    // A lazy or possessive suffix changes nothing about what matches.
    if (!_done && (source[_pos] == '?' || source[_pos] == '+')) _pos++;
    return _Repeat(atom, min, max);
  }
}
