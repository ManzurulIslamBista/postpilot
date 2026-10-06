/// Naming rules shared by every generator that emits Dart: a JSON key, an Odoo
/// model (`res.partner`) or a request title becomes a legal, idiomatic
/// identifier.
abstract final class DartNames {
  /// Words an identifier cannot be, plus `Object` members a field would clash
  /// with. Contextual words such as `get`, `set`, `on` and `part` are fine.
  static const _reserved = {
    'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', 'default', 'do', 'else', 'enum',
    'extends', 'false', 'final', 'finally', 'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return',
    'super', 'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with', 'await', 'yield',
    'hashCode', 'runtimeType', 'toString', 'noSuchMethod',
    // A field called `int` hides the type `int` for every other field of its class.
    'int', 'double', 'num', 'bool', 'dynamic',
    // Members the generated classes already have.
    'toJson', 'fromJson', 'copyWith',
  };

  /// Type names a generated class must not take: a class called `String`, `List`
  /// or `DateTime` replaces the core type for the whole file (or is an ambiguous
  /// import in every file that uses both), and the generated code needs the real
  /// one.
  static const _coreTypes = {
    'Object', 'Null', 'Never', 'Function', 'Record', 'Enum', 'Type', 'Symbol', 'Deprecated',
    'String', 'StringBuffer', 'StringSink', 'Runes', 'RegExp', 'RegExpMatch', 'Match', 'Pattern',
    'List', 'Map', 'Set', 'Iterable', 'Iterator', 'Comparable', 'Sink', 'Expando', 'WeakReference', 'Finalizable',
    'DateTime', 'Duration', 'Stopwatch', 'Future', 'Stream', 'Uri', 'UriData', 'BigInt', 'StackTrace', 'Invocation',
    'Error', 'Exception', 'AssertionError', 'TypeError', 'StateError', 'ArgumentError', 'RangeError',
    'FormatException', 'UnimplementedError', 'UnsupportedError', 'ConcurrentModificationError',
  };

  /// A class name for [input]: like [pascal], but a core type's name becomes
  /// `StringModel`, `ListModel`... [also] lists more names to avoid (the types of
  /// a package the generated file imports).
  static String className(String input, {String fallback = 'Item', Set<String> also = const {}}) {
    final name = pascal(input, fallback: fallback);
    return _coreTypes.contains(name) || also.contains(name) ? '${name}Model' : name;
  }

  /// Splits `snake_case`, `kebab-case`, `dot.case`, `camelCase` and spaced text into words.
  static List<String> words(String input) {
    final spaced = input
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]} ${m[2]}');
    return spaced
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.toLowerCase())
        .toList();
  }

  static String pascal(String input, {String fallback = 'Item'}) {
    final parts = words(input);
    if (parts.isEmpty) return fallback;
    final joined = parts.map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join();
    return RegExp(r'^[0-9]').hasMatch(joined) ? 'N$joined' : joined;
  }

  static String camel(String input, {String fallback = 'value'}) {
    final parts = words(input);
    if (parts.isEmpty) return fallback;
    final joined = parts.first + parts.skip(1).map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join();
    final safe = RegExp(r'^[0-9]').hasMatch(joined) ? 'n$joined' : joined;
    return _reserved.contains(safe) ? '${safe}Value' : safe;
  }

  static String snake(String input, {String fallback = 'model'}) {
    final parts = words(input);
    return parts.isEmpty ? fallback : parts.join('_');
  }

  /// "items" becomes "item", "categories" becomes "category"; "status" stays.
  static String singular(String word) {
    final lower = word.toLowerCase();
    if (lower.endsWith('ies') && word.length > 4) return '${word.substring(0, word.length - 3)}y';
    if (lower.endsWith('sses') || lower.endsWith('shes') || lower.endsWith('ches') || lower.endsWith('xes')) {
      return word.substring(0, word.length - 2);
    }
    if (lower.endsWith('s') &&
        !lower.endsWith('ss') &&
        !lower.endsWith('us') &&
        !lower.endsWith('is') &&
        word.length > 3) {
      return word.substring(0, word.length - 1);
    }
    return word;
  }

  /// [value] as a single-quoted Dart string literal.
  static String quote(String value) => "'${escape(value)}'";

  /// [value] as it must be written between single quotes: `\`, `'`, `$` and
  /// line breaks escaped.
  static String escape(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
}
