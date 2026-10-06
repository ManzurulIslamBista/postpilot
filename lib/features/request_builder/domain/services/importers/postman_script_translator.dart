import 'dart:convert';
import '../../../../scripting/domain/entities/assertion_entity.dart';
import '../../../../scripting/domain/entities/extractor_entity.dart';

/// What [PostmanScriptTranslator] made of one Postman test script.
final class ScriptTranslation {
  final List<AssertionEntity> assertions;
  final List<ExtractorEntity> extractors;

  /// Statements with no declarative equivalent, shortened for display. They
  /// were left out, never approximated.
  final List<String> untranslated;

  /// Statements that were converted with a difference worth telling about.
  final List<String> adjusted;

  const ScriptTranslation({
    this.assertions = const [],
    this.extractors = const [],
    this.untranslated = const [],
    this.adjusted = const [],
  });
}

/// Turns the common shapes of a Postman `test` script into this app's
/// declarative assertions and extractors (scripts cannot run on web, so a
/// `pm.test` becomes a row on the request's Tests tab):
///
/// * `pm.response.to.have.status(N)`, `pm.response.to.be.ok`, `...have.header(name[, value])`
/// * `pm.expect(pm.response.code).to.eql(N)`, `...responseTime).to.be.below(N)`,
///   `pm.expect(pm.response.text()).to.include('x')`, `pm.expect(headers.get('X')).to.eql('v')`
/// * `pm.expect(jsonData.a.b).to.eql(x)` / `.to.exist` / `.to.be.a('string')` / `pm.expect(jsonData).to.have.property('id')`,
///   where `jsonData` is any variable assigned from `pm.response.json()` (also `JSON.parse(responseBody)` and a
///   sub-path of either)
/// * `pm.environment.set('k', jsonData.path)`, the same for `pm.globals`, `pm.collectionVariables` and the
///   legacy `postman.setEnvironmentVariable`, plus `pm.response.headers.get('X')` as the value
///
/// A statement it does not recognise, including every negation and every
/// expression it would have to guess about, is left out and listed in
/// [ScriptTranslation.untranslated]. `console.*` calls do nothing a declarative
/// runner could miss and are dropped silently.
abstract final class PostmanScriptTranslator {
  /// Translates a `test` script given as one text.
  static ScriptTranslation translateTests(String script) {
    final translator = _Translator();
    for (final statement in splitStatements(script)) {
      translator.statement(statement);
    }
    return translator.result();
  }

  /// Every statement of [script] that matters, shortened for display. Used for
  /// pre-request scripts, which can never be translated.
  static List<String> describeStatements(String script) => [
    for (final statement in splitStatements(script))
      if (!_isNoise(statement.trim())) _preview(statement),
  ];

  /// The statements of [source] at the top level, with comments removed.
  static List<String> splitStatements(String source) {
    final text = _stripComments(source);
    final statements = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    String? quote;

    void flush() {
      final statement = buffer.toString().trim();
      if (statement.isNotEmpty) statements.add(statement);
      buffer.clear();
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quote != null) {
        buffer.write(char);
        if (char == r'\' && i + 1 < text.length) {
          buffer.write(text[++i]);
        } else if (char == quote) {
          quote = null;
        }
        continue;
      }
      switch (char) {
        case '"' || "'" || '`':
          quote = char;
          buffer.write(char);
        case '(' || '[' || '{':
          depth++;
          buffer.write(char);
        case ')' || ']' || '}':
          if (depth > 0) depth--;
          buffer.write(char);
        case ';' when depth == 0:
          flush();
        case '\n' when depth == 0:
          if (_continuesOnNextLine(buffer.toString(), text, i + 1)) {
            buffer.write(' ');
          } else {
            flush();
          }
        default:
          buffer.write(char);
      }
    }
    flush();
    return statements;
  }

  static const _operatorTails = ['=', '+', '-', '*', '/', '%', '&', '|', '^', '<', '>', '!', '?', ':', ',', '.', '('];
  static final _continuingHead = RegExp(r'^(?:[.?:+*/=]|&&|\|\||else\b|catch\b|finally\b)');

  /// A line break ends a statement unless the statement is visibly unfinished
  /// (it ends with an operator) or the next line continues it (`.then(...)`, `else`).
  static bool _continuesOnNextLine(String pending, String text, int next) {
    final head = pending.trimRight();
    if (head.isEmpty) return false;
    if (!head.endsWith('++') && !head.endsWith('--') && _operatorTails.any(head.endsWith)) return true;
    var start = next;
    while (start < text.length && ' \t\r\n'.contains(text[start])) {
      start++;
    }
    return _continuingHead.hasMatch(text.substring(start));
  }

  /// Removes `//` and `/* */` comments, leaving string literals alone.
  static String _stripComments(String source) {
    final out = StringBuffer();
    String? quote;
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (quote != null) {
        out.write(char);
        if (char == r'\' && i + 1 < source.length) {
          out.write(source[++i]);
        } else if (char == quote) {
          quote = null;
        }
      } else if (char == '"' || char == "'" || char == '`') {
        quote = char;
        out.write(char);
      } else if (char == '/' && i + 1 < source.length && source[i + 1] == '/') {
        while (i < source.length && source[i] != '\n') {
          i++;
        }
        if (i < source.length) out.write('\n');
      } else if (char == '/' && i + 1 < source.length && source[i + 1] == '*') {
        final end = source.indexOf('*/', i + 2);
        i = end == -1 ? source.length : end + 1;
        out.write(' ');
      } else {
        out.write(char);
      }
    }
    return out.toString();
  }

  static final _noise = RegExp(r'''^(?:console\.(?:log|info|warn|error|debug)\s*\(|["']use strict["']$)''');
  static bool _isNoise(String statement) => _noise.hasMatch(statement);

  static String _preview(String statement) {
    final flat = statement.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length > 80 ? '${flat.substring(0, 80)}...' : flat;
  }
}

/// A JS string literal, single or double quoted (or a template literal without
/// `${}`), as the text it denotes.
String? _stringLiteral(String text) {
  final t = text.trim();
  if (t.length < 2) return null;
  final quote = t[0];
  if ((quote != '"' && quote != "'" && quote != '`') || t[t.length - 1] != quote) return null;
  final body = t.substring(1, t.length - 1);
  if (quote == '`' && body.contains(r'${')) return null;
  final out = StringBuffer();
  for (var i = 0; i < body.length; i++) {
    final char = body[i];
    if (char == quote) return null; // an unescaped quote: this is two literals, not one
    if (char != r'\') {
      out.write(char);
      continue;
    }
    if (++i >= body.length) return null;
    switch (body[i]) {
      case 'n':
        out.write('\n');
      case 't':
        out.write('\t');
      case 'r':
        out.write('\r');
      case 'u':
        final hex = i + 4 < body.length ? body.substring(i + 1, i + 5) : null;
        final code = hex == null ? null : int.tryParse(hex, radix: 16);
        if (code == null) return null;
        out.writeCharCode(code);
        i += 4;
      case 'x' || '0' || 'b' || 'f' || 'v':
        return null;
      default:
        out.write(body[i]);
    }
  }
  return out.toString();
}

/// Index of the bracket that closes the one at [open], skipping string literals; -1 when it never closes.
int _closing(String text, int open) {
  var depth = 0;
  String? quote;
  for (var i = open; i < text.length; i++) {
    final char = text[i];
    if (quote != null) {
      if (char == r'\') {
        i++;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      quote = char;
    } else if (char == '(' || char == '[' || char == '{') {
      depth++;
    } else if (char == ')' || char == ']' || char == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// [text] split at its top-level commas.
List<String> _arguments(String text) {
  final out = <String>[];
  final buffer = StringBuffer();
  var depth = 0;
  String? quote;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quote != null) {
      buffer.write(char);
      if (char == r'\' && i + 1 < text.length) {
        buffer.write(text[++i]);
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      quote = char;
    } else if (char == '(' || char == '[' || char == '{') {
      depth++;
    } else if (char == ')' || char == ']' || char == '}') {
      depth--;
    } else if (char == ',' && depth == 0) {
      out.add(buffer.toString().trim());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  final last = buffer.toString().trim();
  if (last.isNotEmpty || out.isNotEmpty) out.add(last);
  return out;
}

final class _Translator {
  final _assertions = <AssertionEntity>[];
  final _extractors = <ExtractorEntity>[];
  final _untranslated = <String>[];
  final _adjusted = <String>[];

  /// Variables known to hold (part of) the response JSON, with the path they point at.
  final _aliases = <String, String>{};

  static const _rootPath = r'$';
  static const _identifier = r'[A-Za-z_$][\w$]*';

  ScriptTranslation result() => ScriptTranslation(
    assertions: _assertions,
    extractors: _extractors,
    untranslated: _untranslated,
    adjusted: _adjusted,
  );

  void statement(String raw) {
    final text = raw.trim();
    if (text.isEmpty || PostmanScriptTranslator._isNoise(text)) return;
    if (_test(text) || _declaration(text) || _responseCheck(text) || _expect(text) || _setVariable(text)) return;
    _untranslated.add(PostmanScriptTranslator._preview(text));
  }

  // --- pm.test(name, callback) ------------------------------------------------------------

  bool _test(String text) {
    if (!text.startsWith('pm.test(')) return false;
    final open = text.indexOf('(');
    final close = _closing(text, open);
    if (close == -1 || text.substring(close + 1).trim().isNotEmpty) return false;
    final args = _arguments(text.substring(open + 1, close));
    if (args.length < 2 || _stringLiteral(args.first) == null) return false;
    final body = _callbackBody(args[1]);
    if (body == null) return false;
    for (final inner in PostmanScriptTranslator.splitStatements(body)) {
      statement(inner);
    }
    return true;
  }

  /// The statements inside a `function () { ... }`, `() => { ... }` or `() => expression` callback.
  static String? _callbackBody(String callback) {
    var text = callback.trim();
    if (text.startsWith('async ')) text = text.substring(6).trimLeft();
    final function = RegExp(r'^function\s*[\w$]*\s*\(').firstMatch(text);
    if (function != null) {
      final paramsEnd = _closing(text, function.end - 1);
      if (paramsEnd == -1) return null;
      return _braced(text.substring(paramsEnd + 1).trim());
    }
    final arrow = RegExp(r'^(?:\([^)]*\)|[\w$]+)\s*=>\s*').firstMatch(text);
    if (arrow == null) return null;
    final rest = text.substring(arrow.end).trim();
    return rest.startsWith('{') ? _braced(rest) : rest;
  }

  static String? _braced(String text) {
    if (!text.startsWith('{')) return null;
    final close = _closing(text, 0);
    if (close == -1 || text.substring(close + 1).trim().isNotEmpty) return null;
    return text.substring(1, close);
  }

  // --- var jsonData = pm.response.json() --------------------------------------------------

  static final _declarationPattern = RegExp(r'^(?:(?:var|let|const)\s+)?([A-Za-z_$][\w$]*)\s*=(?!=)\s*([\s\S]+)$');

  bool _declaration(String text) {
    final match = _declarationPattern.firstMatch(text);
    if (match == null) return false;
    final name = match.group(1)!;
    final path = _jsonPath(match.group(2)!);
    if (path == null) {
      _aliases.remove(name); // reassigned to something else: it no longer points into the response
      return false;
    }
    _aliases[name] = path;
    return true;
  }

  // --- pm.response.to.have... ---------------------------------------------------------------

  static const _namedStatuses = {
    'ok': 200,
    'accepted': 202,
    'badRequest': 400,
    'unauthorized': 401,
    'forbidden': 403,
    'notFound': 404,
    'rateLimited': 429,
  };

  static final _statusCheck = RegExp(r'^pm\.response\.to\.have\.status\(\s*(\d{3})\s*\)$');
  static final _namedStatusCheck = RegExp(r'^pm\.response\.to\.be\.(\w+)$');
  static final _headerCheck = RegExp(r'^pm\.response\.to\.have\.header\(([\s\S]*)\)$');

  bool _responseCheck(String text) {
    if (!text.startsWith('pm.response.to.')) return false;
    final status = _statusCheck.firstMatch(text);
    if (status != null) {
      _assertions.add(AssertionEntity(type: AssertionType.statusEquals, expected: status.group(1)!));
      return true;
    }
    final named = _namedStatusCheck.firstMatch(text);
    if (named != null) {
      final word = named.group(1)!;
      if (word == 'success') {
        _assertions.add(AssertionEntity(type: AssertionType.statusIn2xx));
        return true;
      }
      final code = _namedStatuses[word];
      if (code == null) return false;
      _assertions.add(AssertionEntity(type: AssertionType.statusEquals, expected: '$code'));
      return true;
    }
    final header = _headerCheck.firstMatch(text);
    if (header != null) {
      final args = _arguments(header.group(1)!);
      final name = args.isEmpty ? null : _stringLiteral(args.first);
      if (name == null || name.trim().isEmpty || args.length > 2) return false;
      if (args.length == 1) {
        _assertions.add(AssertionEntity(type: AssertionType.headerExists, path: name));
        return true;
      }
      final value = _expectedText(args[1]);
      if (value == null) return false;
      _assertions.add(AssertionEntity(type: AssertionType.headerEquals, path: name, expected: value));
      return true;
    }
    return false;
  }

  // --- pm.expect(subject).to.... ------------------------------------------------------------

  static const _fillers = {'to', 'be', 'been', 'is', 'that', 'which', 'and', 'have', 'has', 'with', 'at', 'of', 'same', 'deep'};
  static const _typeNames = {'string', 'number', 'boolean', 'object', 'array', 'null'};
  static final _headerGet = RegExp(r'^pm\.response\.headers\.get\(\s*([\s\S]+?)\s*\)$');

  bool _expect(String text) {
    if (!text.startsWith('pm.expect(')) return false;
    final open = text.indexOf('(');
    final close = _closing(text, open);
    if (close == -1) return false;
    final subject = text.substring(open + 1, close).trim();

    var rest = text.substring(close + 1).trim();
    List<String>? args;
    final callAt = rest.indexOf('(');
    if (callAt != -1) {
      final callEnd = _closing(rest, callAt);
      if (callEnd == -1 || rest.substring(callEnd + 1).trim().isNotEmpty) return false;
      args = _arguments(rest.substring(callAt + 1, callEnd));
      rest = rest.substring(0, callAt).trim();
    }
    final words = [for (final word in rest.split('.').skip(1)) word.trim()];
    if (rest.isNotEmpty && !rest.startsWith('.') || words.isEmpty) return false;
    final verb = words.last;
    if (!words.take(words.length - 1).every(_fillers.contains)) return false;

    final target = _target(subject);
    if (target == null) return false;
    final assertion = _assertionFor(target, verb, args);
    if (assertion == null) return false;
    _assertions.add(assertion);
    return true;
  }

  AssertionEntity? _assertionFor(_Target target, String verb, List<String>? args) {
    switch (verb) {
      case 'eql' || 'equal' || 'equals' || 'eq':
        if (args == null || args.length != 1) return null;
        switch (target.kind) {
          case _Kind.status:
            final code = int.tryParse(args.single.trim());
            return code == null ? null : AssertionEntity(type: AssertionType.statusEquals, expected: '$code');
          case _Kind.header:
            final expected = _expectedText(args.single);
            return expected == null ? null : AssertionEntity(type: AssertionType.headerEquals, path: target.path, expected: expected);
          case _Kind.json:
            final expected = _expectedText(args.single);
            return expected == null
                ? null
                : AssertionEntity(type: AssertionType.jsonPathEquals, path: target.path, expected: expected);
          case _Kind.time || _Kind.body:
            return null;
        }
      case 'exist':
        if (args != null) return null;
        return switch (target.kind) {
          _Kind.json => AssertionEntity(type: AssertionType.jsonPathExists, path: target.path),
          _Kind.header => AssertionEntity(type: AssertionType.headerExists, path: target.path),
          _ => null,
        };
      case 'a' || 'an':
        if (target.kind != _Kind.json || args == null || args.length != 1) return null;
        final type = _stringLiteral(args.single);
        if (type == null || !_typeNames.contains(type)) return null;
        return AssertionEntity(
          type: AssertionType.jsonSchema,
          path: target.path == _rootPath ? '' : target.path,
          expected: jsonEncode({'type': type}),
        );
      case 'property':
        if (target.kind != _Kind.json || args == null || args.isEmpty || args.length > 2) return null;
        final key = _stringLiteral(args.first);
        if (key == null || key.isEmpty) return null;
        final path = _appendKey(target.path, key);
        if (args.length == 1) return AssertionEntity(type: AssertionType.jsonPathExists, path: path);
        final expected = _expectedText(args[1]);
        return expected == null ? null : AssertionEntity(type: AssertionType.jsonPathEquals, path: path, expected: expected);
      case 'below' || 'lessThan' || 'lt':
        if (target.kind != _Kind.time || args == null || args.length != 1) return null;
        final limit = int.tryParse(args.single.trim());
        return limit == null ? null : AssertionEntity(type: AssertionType.responseTimeBelowMs, expected: '$limit');
      case 'include' || 'includes' || 'contain' || 'contains' || 'string':
        if (target.kind != _Kind.body || args == null || args.length != 1) return null;
        final text = _stringLiteral(args.single);
        if (text == null || text.isEmpty || text != text.trim()) return null;
        return AssertionEntity(type: AssertionType.bodyContains, expected: text);
      case 'within':
        if (target.kind != _Kind.status || args == null || args.length != 2) return null;
        if (args[0].trim() != '200' || args[1].trim() != '299') return null;
        return AssertionEntity(type: AssertionType.statusIn2xx);
    }
    return null;
  }

  _Target? _target(String subject) {
    switch (subject) {
      case 'pm.response.code' || 'responseCode.code':
        return const _Target(_Kind.status);
      case 'pm.response.responseTime' || 'responseTime':
        return const _Target(_Kind.time);
      case 'pm.response.text()' || 'responseBody':
        return const _Target(_Kind.body);
    }
    final header = _headerGet.firstMatch(subject);
    if (header != null) {
      final name = _stringLiteral(header.group(1)!);
      return name == null || name.trim().isEmpty ? null : _Target(_Kind.header, name);
    }
    final path = _jsonPath(subject);
    return path == null ? null : _Target(_Kind.json, path.isEmpty ? _rootPath : path);
  }

  // --- pm.environment.set(key, value) -------------------------------------------------------

  static final _setCall = RegExp(
    r'^(?:pm\.(environment|globals|collectionVariables)\.set|postman\.(setEnvironmentVariable|setGlobalVariable))\(([\s\S]*)\)$',
  );

  bool _setVariable(String text) {
    final match = _setCall.firstMatch(text);
    if (match == null) return false;
    final args = _arguments(match.group(3)!);
    if (args.length != 2) return false;
    final key = _stringLiteral(args.first);
    if (key == null) return false;

    final value = args[1].trim();
    final ExtractorEntity extractor;
    final header = _headerGet.firstMatch(value);
    final scope = match.group(1) == 'globals' || match.group(2) == 'setGlobalVariable'
        ? ExtractorScope.global
        : ExtractorScope.environment;
    if (header != null) {
      final name = _stringLiteral(header.group(1)!);
      if (name == null) return false;
      extractor = ExtractorEntity(source: ExtractorSource.header, path: name, scope: scope, variableKey: key);
    } else {
      final path = _jsonPath(value);
      if (path == null || path.isEmpty) return false;
      extractor = ExtractorEntity(path: path, scope: scope, variableKey: key);
    }
    if (extractor.keyError != null || extractor.pathError != null) return false;

    _extractors.add(extractor);
    if (match.group(1) == 'collectionVariables') {
      _adjusted.add(
        'pm.collectionVariables.set("$key") became an extractor into the active environment '
        '(extractors write environment or global variables, not collection variables)',
      );
    }
    return true;
  }

  // --- shared pieces ------------------------------------------------------------------------

  static const _jsonRoots = ['pm.response.json()', 'JSON.parse(responseBody)', 'JSON.parse(pm.response.text())'];
  static final _firstIdentifier = RegExp('^$_identifier');

  /// The JSON path [expression] points at in the response, `''` for the whole
  /// body; null when it is not a plain read of the response JSON.
  String? _jsonPath(String expression) {
    final text = expression.trim();
    for (final root in _jsonRoots) {
      if (text.startsWith(root)) return _readPath('', text.substring(root.length));
    }
    final name = _firstIdentifier.firstMatch(text);
    final base = name == null ? null : _aliases[name.group(0)];
    return base == null ? null : _readPath(base == _rootPath ? '' : base, text.substring(name!.end));
  }

  static final _step = RegExp(
    r'''^(?:\.([A-Za-z_$][\w$]*)|\[\s*(\d+)\s*\]|\[\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')\s*\])''',
  );

  /// Applies the `.a`, `[0]` and `["a b"]` steps in [rest] to [base]; null for anything else
  /// (a call, `.length`, optional chaining ...).
  static String? _readPath(String base, String rest) {
    var path = base;
    var remaining = rest.trim();
    while (remaining.isNotEmpty) {
      final match = _step.firstMatch(remaining);
      if (match == null) return null;
      if (match.group(1) != null) {
        if (match.group(1) == 'length') return null; // the length of an array or string is not a JSON path
        path = _appendKey(path, match.group(1)!);
      } else if (match.group(2) != null) {
        path = '$path[${match.group(2)}]';
      } else {
        final key = _stringLiteral(match.group(3)!);
        if (key == null) return null;
        path = _appendKey(path, key);
      }
      remaining = remaining.substring(match.end).trimLeft();
    }
    return path;
  }

  static final _simpleKey = RegExp(r'^[A-Za-z_$][\w$]*$');

  static String _appendKey(String path, String key) {
    final base = path == _rootPath ? '' : path;
    if (_simpleKey.hasMatch(key)) return base.isEmpty ? key : '$base.$key';
    return '$base[${jsonEncode(key)}]';
  }

  static final _numberLiteral = RegExp(r'^-?\d+(?:\.\d+)?$');
  static final _variableGet = RegExp(r'^pm\.(?:environment|variables|globals|collectionVariables)\.get\(\s*([\s\S]+?)\s*\)$');

  /// The text an assertion compares against, for a literal [argument]; null when the argument is an
  /// expression whose value cannot be known here. A value the evaluator would trim cannot be expressed.
  static String? _expectedText(String argument) {
    final text = argument.trim();
    if (_numberLiteral.hasMatch(text)) {
      final number = num.parse(text);
      return number is double && number == number.truncateToDouble() ? '${number.toInt()}' : '$number';
    }
    if (text == 'true' || text == 'false' || text == 'null') return text;
    final string = _stringLiteral(text);
    if (string != null) return string == string.trim() ? string : null;
    final variable = _variableGet.firstMatch(text);
    if (variable != null) {
      final key = _stringLiteral(variable.group(1)!);
      return key == null || key.isEmpty ? null : '{{$key}}';
    }
    if (text.startsWith('[') || text.startsWith('{')) {
      try {
        return jsonEncode(jsonDecode(text));
      } on FormatException {
        return null;
      }
    }
    return null;
  }
}

enum _Kind { status, time, body, header, json }

final class _Target {
  final _Kind kind;

  /// The header name or the JSON path.
  final String path;
  const _Target(this.kind, [this.path = '']);
}
