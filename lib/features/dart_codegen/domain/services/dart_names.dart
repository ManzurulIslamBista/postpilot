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
  };

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
  static String quote(String value) =>
      "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\n', r'\n')}'";
}
