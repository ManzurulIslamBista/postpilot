/// One operation of a GraphQL document, with the names of the fields it asks
/// for at its root (`deleteUser` in `mutation { deleteUser(id: 1) { id } }`).
final class GraphqlOperation {
  /// `query`, `mutation` or `subscription`; an anonymous `{ ... }` is a `query`.
  final String type;
  final String? name;
  final List<String> rootFields;

  const GraphqlOperation(this.type, this.name, this.rootFields);

  bool get isMutation => type == 'mutation';
}

/// A small, forgiving GraphQL reader: it only has to tell queries from
/// mutations and spot the root fields of a mutation, so it does not validate
/// the document. Pure Dart, shared by the app's production lock and the CLI.
abstract final class GraphqlOperations {
  /// The operations of [document], or `null` when it is not an executable
  /// GraphQL document this reader can follow (text that is not GraphQL, a
  /// schema definition, unbalanced braces). Callers must then assume the worst.
  static List<GraphqlOperation>? parse(String document) {
    final tokens = _lex(document);
    if (tokens == null || tokens.isEmpty) return null;
    final operations = <GraphqlOperation>[];
    var i = 0;
    while (i < tokens.length) {
      final token = tokens[i];
      if (token.isPunct('{')) {
        final end = _closing(tokens, i);
        if (end < 0) return null;
        operations.add(GraphqlOperation('query', null, _rootFields(tokens, i + 1, end)));
        i = end + 1;
      } else if (token.isName && _operationTypes.contains(token.text)) {
        i++;
        String? name;
        if (i < tokens.length && tokens[i].isName) name = tokens[i++].text;
        if (i < tokens.length && tokens[i].isPunct('(')) {
          final end = _closing(tokens, i);
          if (end < 0) return null;
          i = end + 1;
        }
        i = _skipDirectives(tokens, i);
        if (i < 0 || i >= tokens.length || !tokens[i].isPunct('{')) return null;
        final end = _closing(tokens, i);
        if (end < 0) return null;
        operations.add(GraphqlOperation(token.text, name, _rootFields(tokens, i + 1, end)));
        i = end + 1;
      } else if (token.isName && token.text == 'fragment') {
        // fragment Name on Type @directive { ... }: nothing to learn, skip it whole.
        while (i < tokens.length && !tokens[i].isPunct('{')) {
          if (tokens[i].isPunct('(')) {
            final end = _closing(tokens, i);
            if (end < 0) return null;
            i = end;
          }
          i++;
        }
        if (i >= tokens.length) return null;
        final end = _closing(tokens, i);
        if (end < 0) return null;
        i = end + 1;
      } else {
        return null;
      }
    }
    return operations.isEmpty ? null : operations;
  }

  static const _operationTypes = {'query', 'mutation', 'subscription'};

  static final _nameStart = RegExp(r'[_A-Za-z][_0-9A-Za-z]*');
  static final _number = RegExp(r'-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?');

  /// Strings and comments are dropped (a string holding the word "mutation"
  /// must not count); `null` for a character GraphQL does not have.
  static List<_Token>? _lex(String source) {
    final tokens = <_Token>[];
    var i = 0;
    while (i < source.length) {
      final c = source[i];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == ',' || c == '﻿') {
        i++;
      } else if (c == '#') {
        while (i < source.length && source[i] != '\n' && source[i] != '\r') {
          i++;
        }
      } else if (c == '"') {
        final end = source.startsWith('"""', i) ? _blockStringEnd(source, i + 3) : _stringEnd(source, i + 1);
        if (end < 0) return null;
        tokens.add(const _Token(_Kind.string, '"'));
        i = end;
      } else if (source.startsWith('...', i)) {
        tokens.add(const _Token(_Kind.punct, '...'));
        i += 3;
      } else if ('{}()[]:=!\$@&|'.contains(c)) {
        tokens.add(_Token(_Kind.punct, c));
        i++;
      } else if (_nameStart.matchAsPrefix(source, i) case final name?) {
        tokens.add(_Token(_Kind.name, name[0]!));
        i = name.end;
      } else if (_number.matchAsPrefix(source, i) case final number?) {
        tokens.add(const _Token(_Kind.other, '0'));
        i = number.end;
      } else {
        return null;
      }
    }
    return tokens;
  }

  /// Index after the closing quote of a one-line string that starts at [from]; -1 when it never closes.
  static int _stringEnd(String source, int from) {
    var j = from;
    while (j < source.length) {
      final c = source[j];
      if (c == '\\') {
        j += 2;
      } else if (c == '"') {
        return j + 1;
      } else if (c == '\n' || c == '\r') {
        return -1;
      } else {
        j++;
      }
    }
    return -1;
  }

  /// Index after the closing `"""` of a block string whose body starts at [from]; -1 when it never closes.
  static int _blockStringEnd(String source, int from) {
    var j = from;
    while (j < source.length) {
      if (source.startsWith('\\"""', j)) {
        j += 4;
      } else if (source.startsWith('"""', j)) {
        return j + 3;
      } else {
        j++;
      }
    }
    return -1;
  }

  /// Index of the bracket that closes the one at [open]; -1 when the brackets do not balance.
  static int _closing(List<_Token> tokens, int open) {
    const pairs = {'{': '}', '(': ')', '[': ']'};
    final stack = <String>[];
    for (var i = open; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.kind != _Kind.punct) continue;
      final closer = pairs[token.text];
      if (closer != null) {
        stack.add(closer);
      } else if (pairs.containsValue(token.text)) {
        if (stack.isEmpty || stack.removeLast() != token.text) return -1;
        if (stack.isEmpty) return i;
      }
    }
    return -1;
  }

  /// Index after the `@directive(args)` run that starts at [from]; -1 when one is malformed.
  static int _skipDirectives(List<_Token> tokens, int from) {
    var i = from;
    while (i < tokens.length && tokens[i].isPunct('@')) {
      i++;
      if (i >= tokens.length || !tokens[i].isName) return -1;
      i++;
      if (i < tokens.length && tokens[i].isPunct('(')) {
        final end = _closing(tokens, i);
        if (end < 0) return -1;
        i = end + 1;
      }
    }
    return i;
  }

  /// The field names directly inside the selection set that spans `start..end`
  /// (exclusive). Aliases give way to the real field name; the fields of an
  /// inline fragment count as root fields too.
  static List<String> _rootFields(List<_Token> tokens, int start, int end) {
    final fields = <String>[];
    var i = start;
    while (i < end) {
      final token = tokens[i];
      if (token.isPunct('...')) {
        i++;
        if (i < end && tokens[i].isName && tokens[i].text == 'on') i += 2;
        if (i < end && tokens[i].isName) i++; // a named fragment spread: its fields are not known here
        i = _skipDirectives(tokens, i);
        if (i < 0) return fields;
        if (i < end && tokens[i].isPunct('{')) {
          final close = _closing(tokens, i);
          if (close < 0) return fields;
          fields.addAll(_rootFields(tokens, i + 1, close));
          i = close + 1;
        }
      } else if (token.isName) {
        var name = token.text;
        i++;
        if (i < end && tokens[i].isPunct(':') && i + 1 < end && tokens[i + 1].isName) {
          name = tokens[i + 1].text;
          i += 2;
        }
        fields.add(name);
        if (i < end && tokens[i].isPunct('(')) {
          final close = _closing(tokens, i);
          if (close < 0) return fields;
          i = close + 1;
        }
        i = _skipDirectives(tokens, i);
        if (i < 0) return fields;
        if (i < end && tokens[i].isPunct('{')) {
          final close = _closing(tokens, i);
          if (close < 0) return fields;
          i = close + 1;
        }
      } else {
        i++;
      }
    }
    return fields;
  }
}

enum _Kind { name, punct, string, other }

final class _Token {
  final _Kind kind;
  final String text;
  const _Token(this.kind, this.text);

  bool get isName => kind == _Kind.name;
  bool isPunct(String value) => kind == _Kind.punct && text == value;
}
