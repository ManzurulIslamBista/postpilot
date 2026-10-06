import 'dart:convert';
import '../entities/odoo_model_info.dart';
import 'python_literal.dart';

/// Operators of an Odoo domain leaf, with what each means in plain words.
abstract final class OdooOperators {
  static const all = <String, String>{
    '=': 'equals',
    '!=': 'not equals',
    '>': 'greater than',
    '>=': 'greater or equal',
    '<': 'less than',
    '<=': 'less or equal',
    'ilike': 'contains (any case)',
    'not ilike': 'does not contain',
    'like': 'contains (case sensitive)',
    '=ilike': 'matches pattern (any case)',
    'in': 'is one of',
    'not in': 'is none of',
    'child_of': 'is child of',
    'parent_of': 'is parent of',
  };

  /// The operators worth offering for a field type, most useful first.
  static List<String> forType(String type) => switch (type) {
        'char' || 'text' || 'html' => ['ilike', '=', '!=', 'not ilike', 'like', '=ilike', 'in', 'not in'],
        'integer' || 'float' || 'monetary' => ['=', '!=', '>', '>=', '<', '<=', 'in', 'not in'],
        'date' || 'datetime' => ['>=', '<=', '>', '<', '=', '!='],
        'boolean' => ['=', '!='],
        'selection' => ['=', '!=', 'in', 'not in'],
        'many2one' => ['=', '!=', 'in', 'not in', 'ilike', 'child_of', 'parent_of'],
        'one2many' || 'many2many' => ['in', 'not in', '=', '!=', 'ilike'],
        _ => ['=', '!=', 'in', 'not in'],
      };
}

/// A node of a domain tree. Odoo writes domains in prefix notation
/// (`['|', a, b]`); this tree is what a person edits, and [OdooDomain] converts.
sealed class DomainNode {
  const DomainNode();
}

final class DomainLeaf extends DomainNode {
  final String field;
  final String operator;
  final Object? value;
  const DomainLeaf(this.field, this.operator, this.value);

  DomainLeaf copyWith({String? field, String? operator, Object? value}) =>
      DomainLeaf(field ?? this.field, operator ?? this.operator, value ?? this.value);
}

/// Children joined by AND (`all`) or OR (`any`).
final class DomainGroup extends DomainNode {
  final bool any;
  final List<DomainNode> children;
  const DomainGroup({this.any = false, this.children = const []});

  DomainGroup copyWith({bool? any, List<DomainNode>? children}) =>
      DomainGroup(any: any ?? this.any, children: children ?? this.children);
}

final class DomainNot extends DomainNode {
  final DomainNode child;
  const DomainNot(this.child);
}

abstract final class OdooDomain {
  /// The domain as Odoo's prefix-notation list, ready for a request body.
  static List<Object?> toList(DomainNode node) {
    switch (node) {
      case DomainLeaf():
        return [
          [node.field, node.operator, node.value],
        ];
      case DomainNot():
        return ['!', ...toList(node.child)];
      case DomainGroup():
        final parts = [for (final c in node.children) toList(c)];
        if (parts.isEmpty) return [];
        final op = node.any ? '|' : '&';
        final out = <Object?>[for (var i = 0; i < parts.length - 1; i++) op];
        for (final p in parts) {
          out.addAll(p);
        }
        return out;
    }
  }

  /// Compact JSON for a request body.
  static String toJson(DomainNode node) => jsonEncode(toList(node));

  /// The same domain as a Python expression, which is how Odoo developers
  /// write domains in models and views.
  static String toPython(DomainNode node) => '[${toList(node).map(_term).join(', ')}]';

  /// One item of the prefix list: an operator string, or a leaf as a tuple.
  /// A leaf's own value stays a plain list (`('id', 'in', [1, 2, 3])`).
  static String _term(Object? item) => item is List ? '(${item.map(_python).join(', ')})' : _python(item);

  static String _python(Object? v) => switch (v) {
        null => 'None',
        true => 'True',
        false => 'False',
        String s => _pythonString(s),
        List<dynamic> l => '[${l.map(_python).join(', ')}]',
        Map<dynamic, dynamic> m => '{${m.entries.map((e) => '${_python(e.key)}: ${_python(e.value)}').join(', ')}}',
        _ => '$v',
      };

  static String _pythonString(String s) {
    final escaped = s
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t');
    return "'$escaped'";
  }

  /// Reads a prefix-notation domain back into a tree. `null` if [domain] is malformed.
  static DomainNode? fromList(List<dynamic> domain) {
    if (domain.isEmpty) return const DomainGroup();
    var i = 0;
    DomainNode? parse() {
      if (i >= domain.length) return null;
      final item = domain[i++];
      if (item == '&' || item == '|') {
        final a = parse();
        final b = parse();
        if (a == null || b == null) return null;
        final any = item == '|';
        // Flatten chains of the same operator into one group.
        List<DomainNode> kids(DomainNode n) => n is DomainGroup && n.any == any ? n.children : [n];
        return DomainGroup(any: any, children: [...kids(a), ...kids(b)]);
      }
      if (item == '!') {
        final c = parse();
        return c == null ? null : DomainNot(c);
      }
      if (item is List && item.length == 3 && item[0] is String && item[1] is String) {
        return DomainLeaf(item[0] as String, item[1] as String, item[2]);
      }
      return null;
    }

    // An implicit AND joins top-level siblings.
    final nodes = <DomainNode>[];
    while (i < domain.length) {
      final n = parse();
      if (n == null) return null;
      nodes.add(n);
    }
    return nodes.length == 1 && nodes.single is DomainGroup ? nodes.single : DomainGroup(children: nodes);
  }

  /// Parses JSON or a Python-style domain (`[('a','=',1)]`). The Python form is
  /// read as real Python literals, so quotes and brackets inside a string stay
  /// where they are; a name that is not a literal (`user.id`) becomes a
  /// `{{user.id}}` variable like in the Convert tab.
  static DomainNode? parseText(String text) {
    final t = text.trim();
    if (t.isEmpty) return const DomainGroup();
    Object? parsed;
    try {
      parsed = jsonDecode(t);
    } on FormatException {
      parsed = PythonLiteral.parse(t);
    }
    return parsed is List ? fromList(parsed) : null;
  }

  static const _likeOperators = {'like', 'not like', 'ilike', 'not ilike', '=like', '=ilike'};

  /// Turns what was typed into the value a field expects. Plain text follows
  /// the field's type (`42` is a number for an integer field, text for a char
  /// field). `True`, `False` and `None` are those values (`('parent_id', '=',
  /// False)` means "has no parent"), `[1, 2]` is a list, and quoted text is
  /// taken exactly as written, so `'False'` is the word. For `in` a bare list
  /// may be comma separated. Pattern operators (`ilike`...) always search for
  /// text. [formatValue] is the inverse.
  static Object? parseValue(String raw, {required String operator, OdooField? field}) {
    final text = raw.trim();
    final pattern = _likeOperators.contains(operator);
    if (!pattern && (text.startsWith('[') || text.startsWith('(') || text.startsWith('{'))) {
      final literal = PythonLiteral.parse(text, strict: true);
      if (literal is List || literal is Map) return literal;
    }
    if (operator == 'in' || operator == 'not in') {
      return [for (final part in _splitTopLevel(text)) _element(part, pattern: false, field: field)];
    }
    return _element(text, pattern: pattern, field: field);
  }

  static final _number = RegExp(r'^-?\d+(\.\d+)?([eE][+-]?\d+)?$');

  static Object? _element(String raw, {required bool pattern, OdooField? field}) {
    final t = raw.trim();
    if (t.length >= 2 && (t.startsWith("'") || t.startsWith('"'))) {
      final quoted = PythonLiteral.parse(t, strict: true);
      if (quoted is String) return quoted;
    }
    if (pattern) return t;
    switch (t) {
      case 'True' || 'true':
        return true;
      case 'False' || 'false':
        return false;
      case 'None' || 'null':
        return null;
    }
    num? number() => _number.hasMatch(t) ? num.parse(t) : null;
    switch (field?.type) {
      case 'integer' || 'many2one' || 'one2many' || 'many2many' || 'many2one_reference':
        return int.tryParse(t) ?? number() ?? t;
      case 'float' || 'monetary':
        return number() ?? t;
      case 'boolean':
        return t.toLowerCase() == 'true' || t == '1';
      case null:
        // Without the model's field list a bare number is the best guess.
        return number() ?? t;
      default:
        return t;
    }
  }

  /// [text] cut at commas that are outside quotes and brackets; blank pieces drop.
  static List<String> _splitTopLevel(String text) {
    final parts = <String>[];
    final current = StringBuffer();
    String? quote;
    var depth = 0;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quote != null) {
        current.write(c);
        if (c == r'\' && i + 1 < text.length) {
          current.write(text[++i]);
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
      } else if (c == '[' || c == '(' || c == '{') {
        depth++;
      } else if ((c == ']' || c == ')' || c == '}') && depth > 0) {
        depth--;
      } else if (c == ',' && depth == 0) {
        parts.add(current.toString());
        current.clear();
        continue;
      }
      current.write(c);
    }
    parts.add(current.toString());
    return [
      for (final p in parts)
        if (p.trim().isNotEmpty) p.trim(),
    ];
  }

  /// The text to show in a value box for [value] so that [parseValue] reads it
  /// back to exactly [value]: plain text where that is unambiguous, a Python
  /// literal (`'False'`, `[1, 2]`, `None`) where it is not.
  static String formatValue(Object? value, {required String operator, OdooField? field}) {
    final plain = switch (value) {
      String s => s,
      List<dynamic> l when operator == 'in' || operator == 'not in' => l.map((e) => e is String ? e : _python(e)).join(', '),
      _ => null,
    };
    if (plain != null && _same(parseValue(plain, operator: operator, field: field), value)) return plain;
    return _python(value);
  }

  static bool _same(Object? a, Object? b) {
    if (a is List && b is List) {
      return a.length == b.length && [for (var i = 0; i < a.length; i++) _same(a[i], b[i])].every((same) => same);
    }
    if (a is Map && b is Map) {
      return a.length == b.length && a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
    }
    // 1 and 1.0 are different JSON, so type matters, not only value.
    return a.runtimeType == b.runtimeType && a == b;
  }
}
