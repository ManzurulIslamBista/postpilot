import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/odoo/domain/entities/odoo_model_info.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_domain.dart';
import 'package:postpilot/features/odoo/domain/services/python_literal.dart';

OdooField _f(String type) => OdooField(name: 'x', type: type, label: 'X');

void main() {
  group('Python domain text', () {
    test('quotes and brackets inside a string are not touched', () {
      // The old reader rewrote every ( ) and ' in the text, so 'Acme (EU)' became 'Acme [EU]'.
      final tree = OdooDomain.parseText("[('name', '=', 'Acme (EU)')]") as DomainGroup;
      expect((tree.children.single as DomainLeaf).value, 'Acme (EU)');

      final tricky = OdooDomain.parseText(r'''[("name", "ilike", "it's [x] (y) \"z\""), ('note', '=', 'a\\b')]''')
          as DomainGroup;
      expect((tricky.children[0] as DomainLeaf).value, 'it\'s [x] (y) "z"');
      expect((tricky.children[1] as DomainLeaf).value, r'a\b');
    });

    test('unicode and escapes', () {
      final tree = OdooDomain.parseText("[('name', '=', 'Müller – 東京 \u{1F600}'), ('n', '=', 'caf\\xe9 \\u00e9\\n')]")
          as DomainGroup;
      expect((tree.children[0] as DomainLeaf).value, 'Müller – 東京 \u{1F600}');
      expect((tree.children[1] as DomainLeaf).value, 'café é\n');
      // An escape Python does not know keeps its backslash.
      expect(PythonLiteral.parse(r"'\d+'"), r'\d+');
    });

    test('False, True, None and numbers keep their type', () {
      final tree = OdooDomain.parseText("[('parent_id', '=', False), ('active', '=', True), ('x', '=', None), ('n', '>', 1.5)]")
          as DomainGroup;
      expect(
        jsonEncode(OdooDomain.toList(tree)),
        '["&","&","&",["parent_id","=",false],["active","=",true],["x","=",null],["n",">",1.5]]',
      );
      final leaves = tree.children.cast<DomainLeaf>();
      expect(leaves.map((l) => l.value), [false, true, null, 1.5]);
    });

    test('nested lists and in-lists', () {
      final tree = OdooDomain.parseText("[('id', 'in', [1, 2, 3]), ('name', 'in', ['a, b', \"c\"]), ('m', '=', [[1, 2], [3]])]")
          as DomainGroup;
      final v = tree.children.cast<DomainLeaf>().map((l) => l.value).toList();
      expect(v, [
        [1, 2, 3],
        ['a, b', 'c'],
        [
          [1, 2],
          [3],
        ],
      ]);
    });

    test('Python text with a trailing comma and tuples inside the value', () {
      final tree = OdooDomain.parseText("[('id', 'in', (1, 2,)), ]") as DomainGroup;
      expect((tree.children.single as DomainLeaf).value, [1, 2]);
    });

    test('a bare name becomes a variable, malformed text is rejected', () {
      final tree = OdooDomain.parseText("[('user_id', '=', user.id)]") as DomainGroup;
      expect((tree.children.single as DomainLeaf).value, '{{user.id}}');
      expect(OdooDomain.parseText("[('a', '=', 'unterminated)]"), isNull);
      expect(OdooDomain.parseText('42'), isNull);
      expect(OdooDomain.parseText('{"a": 1}'), isNull);
    });

    test('toPython and parseText are inverse for strings that need escaping', () {
      const strings = ["it's", r'back\slash', 'line\nbreak', 'tab\there', 'Acme (EU)', 'café \u{1F600}', "'", '"', ''];
      for (final s in strings) {
        final tree = DomainGroup(children: [DomainLeaf('name', '=', s), DomainLeaf('k', 'in', [s, 1])]);
        final back = OdooDomain.parseText(OdooDomain.toPython(tree)) as DomainGroup;
        expect(jsonEncode(OdooDomain.toList(back)), jsonEncode(OdooDomain.toList(tree)), reason: 'value $s');
      }
    });

    test('in-lists are written as lists, not tuples', () {
      const tree = DomainGroup(children: [DomainLeaf('state', 'in', ['a', 'b', 'c'])]);
      expect(OdooDomain.toPython(tree), "[('state', 'in', ['a', 'b', 'c'])]");
    });
  });

  group('negated groups', () {
    test('a negated OR group survives text -> tree -> list', () {
      final tree = OdooDomain.parseText("['!', '|', ('a', '=', 1), ('b', '=', 2)]")!;
      // The top level is an implicit AND holding the one negated group.
      final not = (tree as DomainGroup).children.single as DomainNot;
      final inner = not.child as DomainGroup;
      expect(inner.any, isTrue);
      expect(OdooDomain.toList(tree), [
        '!',
        '|',
        ['a', '=', 1],
        ['b', '=', 2],
      ]);
    });

    test('NOT applies to the next term only', () {
      final tree = OdooDomain.parseText("['!', ('a', '=', 1), ('b', '=', 2)]") as DomainGroup;
      expect(tree.children, hasLength(2));
      expect(tree.children.first, isA<DomainNot>());
      expect(tree.children.last, isA<DomainLeaf>());
    });

    test('double negation and negated groups nested in a group round-trip', () {
      const list = [
        '&',
        '!',
        '!',
        ['a', '=', 1],
        '|',
        '!',
        '&',
        ['b', '=', 2],
        ['c', '=', 3],
        ['d', '=', false],
      ];
      expect(OdooDomain.toList(OdooDomain.fromList(list)!), list);
    });
  });

  group('value box', () {
    test('typed input', () {
      expect(OdooDomain.parseValue('False', operator: '=', field: _f('many2one')), false);
      expect(OdooDomain.parseValue('false', operator: '=', field: _f('char')), false);
      expect(OdooDomain.parseValue('None', operator: '=', field: _f('char')), isNull);
      expect(OdooDomain.parseValue('42', operator: '=', field: _f('integer')), 42);
      expect(OdooDomain.parseValue('42', operator: '=', field: _f('char')), '42');
      expect(OdooDomain.parseValue('42', operator: '=', field: null), 42);
      expect(OdooDomain.parseValue('007', operator: '=', field: _f('char')), '007');
      expect(OdooDomain.parseValue('1.5', operator: '>', field: _f('float')), 1.5);
      expect(OdooDomain.parseValue('1, 2 ,3', operator: 'in', field: _f('many2one')), [1, 2, 3]);
      expect(OdooDomain.parseValue('[1, 2]', operator: 'in', field: _f('many2one')), [1, 2]);
      expect(OdooDomain.parseValue("'a, b', c", operator: 'in', field: _f('char')), ['a, b', 'c']);
      expect(OdooDomain.parseValue('1,,2,', operator: 'in'), [1, 2]);
    });

    test('quotes force text, pattern operators always search for text', () {
      expect(OdooDomain.parseValue("'False'", operator: '=', field: _f('char')), 'False');
      expect(OdooDomain.parseValue('"42"', operator: '=', field: null), '42');
      expect(OdooDomain.parseValue('True', operator: 'ilike', field: _f('char')), 'True');
      expect(OdooDomain.parseValue('42', operator: 'ilike', field: _f('many2one')), '42');
      expect(OdooDomain.parseValue('[draft] note', operator: 'ilike', field: _f('char')), '[draft] note');
      expect(OdooDomain.parseValue('[draft]', operator: '=', field: _f('char')), '[draft]');
    });

    test('formatValue is the inverse of parseValue for every kind of value', () {
      final values = <Object?>[
        'deco', 'Acme (EU)', "it's", 'say "hi"', r'a\b', 'False', 'true', 'None', 'null', '42', '007', '1.5', '', ' padded ',
        '[draft]', '(EU)', 'a, b', "'quoted'", 'café 東京 \u{1F600}', 'line\nbreak',
        0, 42, -7, 1.5, 100000.0, true, false, null,
        [1, 2, 3], <Object?>[], ['a', 'b'], ['a, b', 'c'], ['1', 2], [true, null, 'x'],
        [[1, 2], [3]], {'k': [1, 'v']},
      ];
      const fieldTypes = <String?>[null, 'char', 'integer', 'float', 'boolean', 'many2one', 'selection', 'date'];
      for (final op in ['=', '!=', 'in', 'not in', 'child_of']) {
        for (final type in fieldTypes) {
          final field = type == null ? null : _f(type);
          for (final v in values) {
            final isList = op == 'in' || op == 'not in';
            // `in` is only ever given a list; and a bare number typed for a text or
            // boolean field is by design read as that field's type (`0` is "0").
            if (isList && v is! List) continue;
            if (v is num && (type == 'char' || type == 'selection' || type == 'date' || type == 'boolean')) continue;
            final shown = OdooDomain.formatValue(v, operator: op, field: field);
            final back = OdooDomain.parseValue(shown, operator: op, field: field);
            expect(jsonEncode(back), jsonEncode(v), reason: 'value ${jsonEncode(v)} op $op field $type shown "$shown"');
          }
        }
      }
    });

    test('formatValue keeps plain text plain and quotes only when needed', () {
      expect(OdooDomain.formatValue('deco', operator: 'ilike', field: _f('char')), 'deco');
      expect(OdooDomain.formatValue('Acme (EU)', operator: '=', field: _f('char')), 'Acme (EU)');
      expect(OdooDomain.formatValue(false, operator: '=', field: _f('many2one')), 'False');
      expect(OdooDomain.formatValue(null, operator: '=', field: _f('many2one')), 'None');
      expect(OdooDomain.formatValue(42, operator: '=', field: _f('integer')), '42');
      expect(OdooDomain.formatValue('False', operator: '=', field: _f('char')), "'False'");
      expect(OdooDomain.formatValue([1, 2], operator: 'in', field: _f('many2one')), '1, 2');
      expect(OdooDomain.formatValue('42', operator: '=', field: null), "'42'");
      expect(OdooDomain.formatValue('42', operator: '=', field: _f('char')), '42');
    });

    test('pattern operators cannot show a non-text value as plain text', () {
      // None under ilike would read back as the word, so it is shown as a literal.
      expect(OdooDomain.formatValue(null, operator: 'ilike', field: _f('char')), 'None');
    });
  });
}
