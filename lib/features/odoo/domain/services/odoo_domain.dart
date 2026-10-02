import 'dart:convert';
import '../entities/odoo_model_info.dart';

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
  static String toPython(DomainNode node) => _python(toList(node));

  static String _python(Object? v) => switch (v) {
        null => 'None',
        true => 'True',
        false => 'False',
        String s => "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'",
        List<dynamic> l when l.length == 3 && l.first is String && !_isOp(l.first as String) =>
          '(${l.map(_python).join(', ')})',
        List<dynamic> l => '[${l.map(_python).join(', ')}]',
        _ => '$v',
      };

  static bool _isOp(String s) => s == '&' || s == '|' || s == '!';

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

  /// Parses JSON or a Python-style domain (`[('a','=',1)]`).
  static DomainNode? parseText(String text) {
    final t = text.trim();
    if (t.isEmpty) return const DomainGroup();
    try {
      final json = jsonDecode(t);
      if (json is List) return fromList(json);
    } on FormatException {
      // Fall through to the Python form.
    }
    try {
      final py = t
          .replaceAll("'", '"')
          .replaceAll('(', '[')
          .replaceAll(')', ']')
          .replaceAllMapped(RegExp(r'\bTrue\b'), (_) => 'true')
          .replaceAllMapped(RegExp(r'\bFalse\b'), (_) => 'false')
          .replaceAllMapped(RegExp(r'\bNone\b'), (_) => 'null')
          .replaceAll(RegExp(r',\s*\]'), ']');
      final json = jsonDecode(py);
      if (json is List) return fromList(json);
    } on FormatException {
      return null;
    }
    return null;
  }

  /// Turns what was typed into the value a field expects: `42` for an
  /// integer, `true` for a boolean, a list for `in`, text otherwise.
  static Object? parseValue(String raw, {required String operator, OdooField? field}) {
    final text = raw.trim();
    Object? one(String s) {
      final t = s.trim();
      switch (field?.type) {
        case 'integer' || 'many2one' || 'one2many' || 'many2many':
          return int.tryParse(t) ?? t;
        case 'float' || 'monetary':
          return num.tryParse(t) ?? t;
        case 'boolean':
          return t.toLowerCase() == 'true' || t == '1';
        default:
          return t;
      }
    }

    if (operator == 'in' || operator == 'not in') {
      return text.isEmpty ? <Object?>[] : text.split(',').map(one).toList();
    }
    if (field?.type == 'boolean') return one(text);
    return one(text);
  }
}
