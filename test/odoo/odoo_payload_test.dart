import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/odoo/domain/entities/odoo_connection.dart';
import 'package:postpilot/features/odoo/domain/entities/odoo_model_info.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_payload.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_snippets.dart';
import 'support/fake_odoo.dart';

OdooModelInfo _partner() => OdooModelInfo.parse('res.partner', jsonEncode(partnerFields))!;

Map<String, Object?> _body(String text) => jsonDecode(text.replaceAll(RegExp(r'\{\{[^{}]+\}\}'), '0')) as Map<String, Object?>;

void main() {
  final info = _partner();
  OdooField f(String name) => info.field(name)!;

  group('the fields of the form', () {
    test('writable stored fields only, the required one first', () {
      final names = OdooPayload.editableFields(info).map((x) => x.name).toList();
      expect(names.first, 'name');
      expect(names.skip(1).toList(), [
        'active', 'category_id', 'child_ids', 'color', 'comment', 'country_id', 'credit_limit', 'date', 'email', 'is_company', 'parent_id', 'phone', 'type', 'user_id',
      ]);
      // Left out: id, display_name (Odoo's own), complete_name and commercial_partner_id (read-only),
      // create_date and write_date (Odoo's own), partner_share (computed, not stored), image_1920 (binary).
      for (final gone in ['id', 'display_name', 'complete_name', 'commercial_partner_id', 'create_date', 'write_date', 'partner_share', 'image_1920']) {
        expect(names, isNot(contains(gone)), reason: gone);
      }
    });

    test('read-only fields come back when asked for, Odoo-managed and computed ones never', () {
      final names = OdooPayload.editableFields(info, includeReadonly: true).map((x) => x.name).toSet();
      expect(names, containsAll(['complete_name', 'commercial_partner_id']));
      expect(names, isNot(containsAll(['id', 'create_date', 'partner_share', 'image_1920'])));
      expect(names.contains('partner_share'), isFalse);
      expect(names.contains('image_1920'), isFalse);
    });
  });

  group('what is typed becomes the value of the field', () {
    test('text stays as typed, including spaces and an empty text', () {
      expect(OdooPayload.parse(f('name'), '  Acme  ').value, '  Acme  ');
      expect(OdooPayload.parse(f('name'), '').value, '');
    });

    test('integers and floats, with their errors', () {
      expect(OdooPayload.parse(f('color'), ' 7 ').value, 7);
      expect(OdooPayload.parse(f('color'), '7.5').error, 'Enter a whole number.');
      expect(OdooPayload.parse(f('color'), 'x').error, isNotNull);
      expect(OdooPayload.parse(f('credit_limit'), '12.5').value, 12.5);
      expect(OdooPayload.parse(f('credit_limit'), '12').value, 12);
      expect(OdooPayload.parse(f('credit_limit'), '1,5').error, contains('number'));
    });

    test('a {{token}} is accepted for numbers and ids and stays a token', () {
      expect(OdooPayload.parse(f('color'), '{{col}}').value, const OdooToken('{{col}}'));
      expect(OdooPayload.parse(f('country_id'), '{{xmlid:base.bd}}').value, const OdooToken('{{xmlid:base.bd}}'));
      expect(OdooPayload.parse(f('name'), '{{x}}').value, '{{x}}', reason: 'inside text it is part of the text');
    });

    test('dates are checked against the calendar', () {
      expect(OdooPayload.parse(f('date'), '2026-10-06').value, '2026-10-06');
      expect(OdooPayload.parse(f('date'), '2026-02-30').error, contains('YYYY-MM-DD'));
      expect(OdooPayload.parse(f('date'), '06/10/2026').error, contains('YYYY-MM-DD'));
      final datetime = OdooField(name: 'x', type: 'datetime', label: 'X');
      expect(OdooPayload.parse(datetime, '2026-10-06 14:30:00').value, '2026-10-06 14:30:00');
      expect(OdooPayload.parse(datetime, '2026-10-06T14:30:00').value, '2026-10-06 14:30:00');
      expect(OdooPayload.parse(datetime, '2026-10-06 25:00:00').error, contains('HH:MM:SS'));
    });

    test('a selection takes only its stored values', () {
      expect(OdooPayload.parse(f('type'), 'invoice').value, 'invoice');
      expect(OdooPayload.parse(f('type'), 'Invoice Address').error, 'Choose one of: contact, invoice, delivery, other.');
    });

    test('a many2one takes an id', () {
      expect(OdooPayload.parse(f('parent_id'), '14').value, 14);
      expect(OdooPayload.parse(f('parent_id'), 'Azure').error, contains('res.partner'));
    });

    test('json and booleans', () {
      final json = OdooField(name: 'p', type: 'json', label: 'P');
      expect(OdooPayload.parse(json, '{"a": [1, 2]}').value, {'a': [1, 2]});
      expect(OdooPayload.parse(json, '{a').error, startsWith('Not valid JSON'));
      expect(OdooPayload.parse(f('active'), 'true').value, true);
      expect(OdooPayload.parse(f('active'), 'no').value, false);
      expect(OdooPayload.parse(f('active'), 'maybe').error, isNotNull);
    });

    test('format is the inverse of parse for what a box shows', () {
      expect(OdooPayload.format(f('color'), 7), '7');
      expect(OdooPayload.format(f('parent_id'), const OdooToken('{{ref:res.partner:Azure Interior}}')), '{{ref:res.partner:Azure Interior}}');
      expect(OdooPayload.format(f('name'), false), '');
      expect(OdooPayload.format(f('active'), false), 'false');
    });
  });

  group('x2many commands', () {
    test('each command is written as the array Odoo reads', () {
      final all = <X2ManyCommand>[
        const CreateCommand({'name': 'Kid'}),
        const UpdateCommand(4, {'name': 'B'}),
        const DeleteCommand(5),
        const UnlinkCommand(6),
        const LinkCommand(7),
        const ClearCommand(),
        const SetCommand([8, 9]),
      ];
      expect([for (final c in all) c.toJson()], [
        [0, 0, {'name': 'Kid'}],
        [1, 4, {'name': 'B'}],
        [2, 5],
        [3, 6],
        [4, 7],
        [5, 0, 0],
        [6, 0, [8, 9]],
      ]);
      expect([for (final c in all) c.code], [0, 1, 2, 3, 4, 5, 6]);
      expect(all[2].summary, 'Delete record 5');
      expect(all[6].summary, 'Replace all with: 8, 9');
    });

    test('commands read back from JSON, and bad ones are refused', () {
      final read = X2ManyCommand.listFromJson([
        [0, 0, {'name': 'K'}],
        [1, 4, {'name': 'B'}],
        [2, 5],
        [3, 6],
        [4, 7],
        [5],
        [6, 0, [8, 9]],
      ])!;
      expect([for (final c in read) c.runtimeType], [CreateCommand, UpdateCommand, DeleteCommand, UnlinkCommand, LinkCommand, ClearCommand, SetCommand]);
      expect(X2ManyCommand.listFromJson([[9, 1]]), isNull);
      expect(X2ManyCommand.listFromJson([[4]]), isNull);
      expect(X2ManyCommand.listFromJson([[0, 0, 'x']]), isNull);
      expect(X2ManyCommand.listFromJson([[6, 0, 'x']]), isNull);
      expect(X2ManyCommand.listFromJson('x'), isNull);
    });
  });

  group('the body', () {
    final values = <String, Object?>{
      'name': 'Acme',
      'is_company': true,
      'type': 'invoice',
      'color': 3,
      'credit_limit': 12.5,
      'date': '2026-10-06',
      'parent_id': 2,
      'country_id': const OdooToken('{{xmlid:base.bd}}'),
      'category_id': [const LinkCommand(1), const SetCommand([1, 2])],
      'child_ids': [const CreateCommand({'name': 'Kid'}), const ClearCommand()],
    };

    test('create with every kind of field, in JSON-2', () {
      final text = OdooPayload.bodyText(protocol: OdooProtocol.json2, model: 'res.partner', method: 'create', values: values);
      expect(text, contains('"country_id": {{xmlid:base.bd}}'), reason: 'the token stays bare, so it can resolve to a number');
      expect(_body(text), {
        'vals_list': [
          {
            'name': 'Acme',
            'is_company': true,
            'type': 'invoice',
            'color': 3,
            'credit_limit': 12.5,
            'date': '2026-10-06',
            'parent_id': 2,
            'country_id': 0,
            'category_id': [
              [4, 1],
              [6, 0, [1, 2]],
            ],
            'child_ids': [
              [0, 0, {'name': 'Kid'}],
              [5, 0, 0],
            ],
          },
        ],
      });
    });

    test('the same payload for Odoo 18 is a call_kw with the vals as the first argument', () {
      final text = OdooPayload.bodyText(protocol: OdooProtocol.jsonRpc, model: 'res.partner', method: 'create', values: {'name': 'Acme', 'parent_id': const OdooToken('{{ref:res.partner:Azure Interior}}')});
      expect(text, contains('"parent_id": {{ref:res.partner:Azure Interior}}'));
      expect(_body(text), {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': 'res.partner',
          'method': 'create',
          'args': [
            [
              {'name': 'Acme', 'parent_id': 0},
            ],
          ],
          'kwargs': <String, Object?>{},
        },
        'id': 1,
      });
    });

    test('write names the ids, and without them uses the variable that stays undefined', () {
      expect(_body(OdooPayload.bodyText(protocol: OdooProtocol.json2, model: 'res.partner', method: 'write', values: {'name': 'N'}, ids: [7, 8])), {
        'ids': [7, 8],
        'vals': {'name': 'N'},
      });
      final noIds = OdooPayload.bodyText(protocol: OdooProtocol.json2, model: 'res.partner', method: 'write', values: {'name': 'N'});
      expect(noIds, contains('"ids": [{{recordId}}]'));
      final rpc = OdooPayload.bodyText(protocol: OdooProtocol.jsonRpc, model: 'res.partner', method: 'write', values: {'name': 'N'}, ids: [7]);
      expect(_body(rpc)['params'], {
        'model': 'res.partner',
        'method': 'write',
        'args': [
          [7],
          {'name': 'N'},
        ],
        'kwargs': <String, Object?>{},
      });
    });

    test('copy sends its values as "default"', () {
      expect(_body(OdooPayload.bodyText(protocol: OdooProtocol.json2, model: 'res.partner', method: 'copy', values: {'name': 'Copy'}, ids: [2])), {
        'ids': [2],
        'default': {'name': 'Copy'},
      });
    });

    test('ids are numbers and tokens', () {
      expect(OdooPayload.parseIds('7, 8  9').ids, [7, 8, 9]);
      expect(OdooPayload.parseIds('{{recordId}},3').ids, [const OdooToken('{{recordId}}'), 3]);
      expect(OdooPayload.parseIds('7, x').error, contains('"x"'));
      expect(OdooPayload.parseIds('').ids, isEmpty);
    });

    test('values survive encodeValue and decodeValue, tokens included', () {
      const vals = {'name': 'K', 'parent_id': OdooToken('{{xmlid:base.main_partner}}'), 'x': [1, 2]};
      final text = OdooPayload.encodeValue(vals);
      expect(text, contains('"parent_id": {{xmlid:base.main_partner}}'));
      expect(OdooPayload.decodeValue(text).value, vals);
      expect(OdooPayload.decodeValue('{oops').error, isNotNull);
    });
  });

  group('loading an existing record', () {
    test('read-only and Odoo-managed fields are dropped, a pair becomes its id, a list of ids becomes [6, 0, ids]', () {
      final record = <String, Object?>{
        'id': 2,
        'display_name': 'Azure Interior',
        'complete_name': 'Azure Interior',
        'name': 'Azure Interior',
        'email': false,
        'phone': false,
        'is_company': true,
        'active': true,
        'type': 'contact',
        'color': 3,
        'credit_limit': 1500.5,
        'parent_id': false,
        'child_ids': [4],
        'category_id': [1, 2],
        'country_id': [233, 'United States'],
        'user_id': false,
        'commercial_partner_id': [2, 'Azure Interior'],
        'create_date': '2026-01-01 10:00:00',
        'write_date': '2026-02-01 10:00:00',
        'image_1920': false,
        'comment': false,
        'date': false,
      };
      final loaded = OdooPayload.fromRecord(info, record);
      expect(loaded['name'], 'Azure Interior');
      expect(loaded['country_id'], 233);
      expect(loaded['child_ids'], hasLength(1));
      expect(loaded['child_ids'], [isA<SetCommand>()]);
      expect([for (final c in loaded['child_ids'] as List) (c as X2ManyCommand).toJson()], [
        [6, 0, [4]],
      ]);
      expect([for (final c in loaded['category_id'] as List) (c as X2ManyCommand).toJson()], [
        [6, 0, [1, 2]],
      ]);
      expect(loaded['is_company'], true);
      expect(loaded['color'], 3);
      expect(loaded['credit_limit'], 1500.5);
      for (final gone in ['id', 'display_name', 'complete_name', 'commercial_partner_id', 'create_date', 'write_date', 'image_1920', 'email', 'phone', 'parent_id', 'user_id', 'comment', 'date']) {
        expect(loaded.containsKey(gone), isFalse, reason: gone);
      }
    });

    test('a false boolean is a value and stays', () {
      final loaded = OdooPayload.fromRecord(info, {'is_company': false, 'active': false});
      expect(loaded, {'is_company': false, 'active': false});
    });

    test('an empty list of ids is left out, an unknown key is ignored', () {
      final loaded = OdooPayload.fromRecord(info, {'child_ids': <int>[], 'nope': 1});
      expect(loaded, isEmpty);
    });

    test('the fields asked of read are the editable ones', () {
      final asked = OdooPayload.readFields(info);
      expect(asked, contains('name'));
      expect(asked, isNot(contains('write_date')));
      expect(asked, isNot(contains('image_1920')));
    });

    test('what default_get returns becomes form values; x2many defaults are commands', () {
      final defaults = OdooPayload.fromDefaults(info, {
        'active': true,
        'type': 'contact',
        'category_id': [
          [6, 0, [3]],
        ],
        'parent_id': 7,
        'country_id': false,
        'create_date': 'x',
        'unknown': 1,
      });
      expect(defaults['active'], true);
      expect(defaults['type'], 'contact');
      expect(defaults['parent_id'], 7);
      expect([for (final c in defaults['category_id'] as List) (c as X2ManyCommand).toJson()], [
        [6, 0, [3]],
      ]);
      expect(defaults.containsKey('country_id'), isFalse);
      expect(defaults.containsKey('unknown'), isFalse);
    });
  });

  group('putting a field into a body that is being typed', () {
    test('a field starts from a value of its type', () {
      expect(OdooSnippets.fieldSnippet(f('name')), '"name": ""');
      expect(OdooSnippets.fieldSnippet(f('is_company')), '"is_company": false');
      expect(OdooSnippets.fieldSnippet(f('color')), '"color": 0');
      expect(OdooSnippets.fieldSnippet(f('credit_limit')), '"credit_limit": 0.0');
      expect(OdooSnippets.fieldSnippet(f('type')), '"type": "contact"');
      expect(OdooSnippets.fieldSnippet(f('parent_id')), '"parent_id": 0');
      expect(OdooSnippets.fieldSnippet(f('child_ids')), '"child_ids": []');
      expect(OdooSnippets.fieldSnippet(f('date')), '"date": "YYYY-MM-DD"');
    });

    test('a comma goes where the neighbouring text is another entry', () {
      const text = '{"name": "A"}';
      // Cursor after the "A" (offset 12), before the closing brace.
      final after = OdooSnippets.insert(text, 12, 12, '"email": ""');
      expect(after.text, '{"name": "A", "email": ""}');
      expect(after.cursor, 12 + ', "email": ""'.length);
      // Cursor right after the opening brace.
      final before = OdooSnippets.insert(text, 1, 1, '"email": ""');
      expect(before.text, '{"email": "", "name": "A"}');
      // Empty body.
      expect(OdooSnippets.insert('', 0, 0, '"a": 1').text, '{\n  "a": 1\n}');
      // A selection is replaced.
      expect(OdooSnippets.insert('{"a": 1, "b": 2}', 9, 15, '"c": 3').text, '{"a": 1, "c": 3}');
    });
  });
}
