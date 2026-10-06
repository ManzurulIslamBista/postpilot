import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/odoo/domain/entities/odoo_model_info.dart';
import 'package:postpilot/features/odoo/domain/entities/odoo_request_shape.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_names.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_request_checker.dart';
import 'support/fake_odoo.dart';

final _partner = OdooModelInfo.parse('res.partner', jsonEncode(partnerFields))!;
final _category = OdooModelInfo.parse('res.partner.category', jsonEncode(categoryFields))!;
final _country = OdooModelInfo.parse('res.country', jsonEncode(countryFields))!;

OdooModelInfo? _related(String model) => {'res.partner': _partner, 'res.partner.category': _category, 'res.country': _country}[model];

const _json2Create = '/json/2/res.partner/create';
const _json2Write = '/json/2/res.partner/write';
const _json2Search = '/json/2/res.partner/search_read';

OdooRequestShape _shape(String url, String body) {
  final read = OdooRequestShape.read(url, body);
  expect(read.error, isNull, reason: body);
  return read.shape!;
}

OdooCheckContext _context({Set<String>? defaults = const {'active', 'type'}, bool withRelated = true}) =>
    OdooCheckContext(info: _partner, modelExists: true, defaults: defaults, related: withRelated ? _related : null);

List<OdooProblem> _check(String url, String body, {OdooCheckContext? context}) => OdooRequestChecker.check(_shape(url, body), context ?? _context());

/// The body text after the fix of the first problem with [code] (and [about] in its message).
String _fixed(String url, String body, String code, {String? about}) {
  final shape = _shape(url, body);
  final problem = OdooRequestChecker.check(shape, _context()).firstWhere((p) => p.code == code && (about == null || p.message.contains(about)));
  expect(problem.fix, isNotNull, reason: problem.message);
  return OdooRequestChecker.applyFixes(shape, [problem.fix!]);
}

Object? _vals(String text) => ((jsonDecode(text.replaceAll(RegExp(r'\{\{[^{}]+\}\}'), '0')) as Map)['vals_list'] as List).first;

/// Creates `res.partner` with one field set (plus the name, so the required rule stays quiet).
String _create(String field, Object? value) => jsonEncode({'vals_list': [{'name': 'A', field: value}]});

Set<String> _codes(List<OdooProblem> ps) => {for (final p in ps) p.code};

void main() {
  group('a body that is right', () {
    test('has no problems, in JSON-2 and as a call_kw', () {
      expect(_check(_json2Create, jsonEncode({'vals_list': [{'name': 'A', 'is_company': true, 'type': 'invoice', 'color': 2, 'parent_id': 2, 'category_id': [[6, 0, [1]]], 'date': '2026-10-06'}]})), isEmpty);
      expect(_check(_json2Write, jsonEncode({'ids': [7], 'vals': {'credit_limit': 1.5}})), isEmpty);
      expect(
        _check('/web/dataset/call_kw/res.partner/write', jsonEncode({'jsonrpc': '2.0', 'method': 'call', 'params': {'model': 'res.partner', 'method': 'write', 'args': [[7], {'color': 3}], 'kwargs': {}}})),
        isEmpty,
      );
      expect(_check(_json2Search, jsonEncode({'domain': [['name', 'ilike', 'a'], ['parent_id', 'in', [1, 2]]], 'fields': ['name', 'email'], 'limit': 5, 'order': 'name desc, id'})), isEmpty);
    });

    test('a {{variable}} where a value goes is not judged', () {
      final body = '{"vals_list": [{"name": "A", "parent_id": {{pid}}, "color": {{n}}, "category_id": {{tags}}, "date": "{{d}}"}]}';
      expect(_check(_json2Create, body).where((p) => p.path != 'vals_list[0].date'), isEmpty);
      expect(_check(_json2Write, '{"ids": [{{recordId}}], "vals": {"name": "N"}}'), isEmpty);
    });
  });

  group('the model', () {
    test('a model the server does not have comes with the nearest names and a fix that switches to one', () {
      final shape = _shape('/json/2/res.partnr/create', '{"vals_list": [{"name": "A"}]}');
      final problems = OdooRequestChecker.check(shape, const OdooCheckContext(modelExists: false, knownModels: ['res.partner', 'res.country', 'sale.order']));
      expect(problems, hasLength(1));
      expect(problems.single.code, 'model_missing');
      expect(problems.single.message, contains('"res.partner"'));
      expect(problems.single.fix!.model, 'res.partner');
      expect(problems.single.fix!.changesBody, isFalse);
    });

    test('fields that could not be read are said so, and only the structure is checked', () {
      final shape = _shape(_json2Write, '{"ids": [1], "vals": {"anything": 1}}');
      final problems = OdooRequestChecker.check(shape, const OdooCheckContext(modelExists: true));
      expect(_codes(problems), {'no_schema'});
      expect(problems.single.severity, OdooProblemSeverity.warning);
    });
  });

  group('field names', () {
    test('a typo is named, with its fix, and the fix leaves the rest of the body alone', () {
      final body = '{"vals_list": [{"nmae": "A", "emial": "a@b.c"}]}';
      final problems = _check(_json2Create, body);
      final typos = problems.where((p) => p.code == 'unknown_field').toList();
      expect(typos.map((p) => p.path), ['vals_list[0].nmae', 'vals_list[0].emial']);
      expect(typos[0].message, 'Field "nmae" does not exist on res.partner. Did you mean "name"?');
      final fixed = OdooRequestChecker.applyFixes(_shape(_json2Create, body), [for (final t in typos) t.fix!]);
      expect(jsonDecode(fixed), {
        'vals_list': [
          {'name': 'A', 'email': 'a@b.c'},
        ],
      });
      // The keys keep their place.
      expect((jsonDecode(fixed)['vals_list'][0] as Map).keys.toList(), ['name', 'email']);
    });

    test('a name with no look-alike can only be removed', () {
      final problems = _check(_json2Write, '{"ids": [1], "vals": {"x_my_custom_thing": 1}}');
      expect(problems.single.code, 'unknown_field');
      expect(problems.single.fix!.label, 'Remove "x_my_custom_thing"');
      expect(jsonDecode(_fixed(_json2Write, '{"ids": [1], "vals": {"x_my_custom_thing": 1, "color": 1}}', 'unknown_field')), {'ids': [1], 'vals': {'color': 1}});
    });

    test('fields, order and dotted paths are checked too', () {
      final problems = _check(_json2Search, jsonEncode({'domain': [['parent_id.nmae', '=', 'x']], 'fields': ['name', 'emial', 'create_date'], 'order': 'nmae desc, id'}));
      expect(problems.map((p) => p.path), containsAll(['domain[0][0]', 'fields[1]', 'order']));
      expect(problems.where((p) => p.code == 'unknown_field'), hasLength(3));
      final body = jsonEncode({'domain': [['parent_id.nmae', '=', 'x']], 'fields': ['name', 'emial'], 'order': 'nmae desc, id'});
      final shape = _shape(_json2Search, body);
      final fixes = [for (final p in OdooRequestChecker.check(shape, _context())) p.fix!];
      expect(jsonDecode(OdooRequestChecker.applyFixes(shape, fixes)), {
        'domain': [['parent_id.name', '=', 'x']],
        'fields': ['name', 'email'],
        'order': 'name desc, id',
      });
    });

    test('Odoo-managed fields are errors, read-only ones warnings, both with a removal', () {
      final problems = _check(_json2Write, jsonEncode({'ids': [1], 'vals': {'id': 5, 'create_date': 'x', 'complete_name': 'y', 'name': 'ok'}}));
      final byPath = {for (final p in problems) p.path: p};
      expect(byPath['vals.id']!.code, 'magic_field');
      expect(byPath['vals.create_date']!.severity, OdooProblemSeverity.error);
      expect(byPath['vals.complete_name']!.code, 'readonly');
      expect(byPath['vals.complete_name']!.severity, OdooProblemSeverity.warning);
      final shape = _shape(_json2Write, jsonEncode({'ids': [1], 'vals': {'id': 5, 'complete_name': 'y', 'name': 'ok'}}));
      final fixed = OdooRequestChecker.applyFixes(shape, [for (final p in OdooRequestChecker.check(shape, _context())) p.fix!]);
      expect(jsonDecode(fixed), {'ids': [1], 'vals': {'name': 'ok'}});
    });
  });

  group('types', () {
    // field, wrong value, the code of the problem, its severity, and the value the fix writes (null: no fix).
    final cases = <(String, Object?, String, OdooProblemSeverity, Object?)>[
      ('comment', 5, 'type', OdooProblemSeverity.warning, '5'),
      ('comment', [1], 'type', OdooProblemSeverity.error, null),
      ('color', '7', 'type', OdooProblemSeverity.error, 7),
      ('color', 7.0, 'type', OdooProblemSeverity.warning, 7),
      ('color', true, 'type', OdooProblemSeverity.error, null),
      ('color', 'seven', 'type', OdooProblemSeverity.error, null),
      ('credit_limit', '12.5', 'type', OdooProblemSeverity.error, 12.5),
      ('credit_limit', 'lots', 'type', OdooProblemSeverity.error, null),
      ('is_company', 'yes', 'type', OdooProblemSeverity.error, true),
      ('is_company', 'False', 'type', OdooProblemSeverity.error, false),
      ('is_company', 1, 'type', OdooProblemSeverity.error, true),
      ('is_company', 0, 'type', OdooProblemSeverity.error, false),
      ('is_company', 'maybe', 'type', OdooProblemSeverity.error, null),
      ('date', '2026-10-06T12:30:00', 'format', OdooProblemSeverity.warning, '2026-10-06'),
      ('date', '2026-10-06 12:30:00', 'format', OdooProblemSeverity.warning, '2026-10-06'),
      ('date', '2026/10/6', 'format', OdooProblemSeverity.error, '2026-10-06'),
      ('date', '13/10/2026', 'format', OdooProblemSeverity.error, '2026-10-13'),
      ('date', '10-13-2026', 'format', OdooProblemSeverity.error, '2026-10-13'),
      ('date', '06/10/2026', 'format', OdooProblemSeverity.error, null),
      ('date', '2026-02-30', 'format', OdooProblemSeverity.error, null),
      ('date', 'tomorrow', 'format', OdooProblemSeverity.error, null),
      ('date', 20261006, 'format', OdooProblemSeverity.error, null),
      ('type', 'Invoice Address', 'selection', OdooProblemSeverity.error, 'invoice'),
      ('type', 'invoce', 'selection', OdooProblemSeverity.error, 'invoice'),
      ('type', 'banana', 'selection', OdooProblemSeverity.error, null),
      ('parent_id', [2, 'Azure Interior'], 'many2one', OdooProblemSeverity.error, 2),
      ('parent_id', '5', 'many2one', OdooProblemSeverity.error, 5),
      ('parent_id', true, 'many2one', OdooProblemSeverity.error, null),
      ('parent_id', 2.5, 'many2one', OdooProblemSeverity.error, null),
    ];
    for (final (field, value, code, severity, fixTo) in cases) {
      test('$field = ${jsonEncode(value)} is a $code ${severity.name}${fixTo == null ? ' with no fix' : ', fixed to ${jsonEncode(fixTo)}'}', () {
        final body = _create(field, value);
        final problems = _check(_json2Create, body).where((p) => p.path == 'vals_list[0].$field').toList();
        expect(problems, hasLength(1), reason: problems.map((p) => p.message).join(' | '));
        expect(problems.single.code, code);
        expect(problems.single.severity, severity);
        if (fixTo == null) {
          expect(problems.single.fix, isNull);
        } else {
          expect((_vals(_fixed(_json2Create, body, code, about: field)) as Map)[field], fixTo);
        }
      });
    }

    test('a datetime in ISO form is rewritten in UTC, an offset is converted', () {
      final field = OdooField(name: 'stamp', type: 'datetime', label: 'Stamp');
      final info = OdooModelInfo('x.model', [field]);
      List<OdooProblem> check(Object? v) => OdooRequestChecker.check(_shape('/json/2/x.model/write', jsonEncode({'ids': [1], 'vals': {'stamp': v}})), OdooCheckContext(info: info, modelExists: true));
      String? fixed(Object? v) {
        final shape = _shape('/json/2/x.model/write', jsonEncode({'ids': [1], 'vals': {'stamp': v}}));
        final p = OdooRequestChecker.check(shape, OdooCheckContext(info: info, modelExists: true)).single;
        return ((jsonDecode(OdooRequestChecker.applyFixes(shape, [p.fix!]))['vals'] as Map)['stamp'] as String?);
      }

      expect(check('2026-10-06 14:30:00'), isEmpty);
      expect(check('2026-10-06'), isEmpty, reason: 'a date alone is midnight');
      expect(fixed('2026-10-06T14:30:00'), '2026-10-06 14:30:00');
      expect(fixed('2026-10-06T14:30'), '2026-10-06 14:30:00');
      expect(fixed('2026-10-06T14:30:00Z'), '2026-10-06 14:30:00');
      expect(fixed('2026-10-06T14:30:00.250Z'), '2026-10-06 14:30:00');
      expect(fixed('2026-10-06T14:30:00+02:00'), '2026-10-06 12:30:00');
      expect(check('2026-13-06 14:30:00').single.fix, isNull);
      expect(check('6 Oct 2026').single.severity, OdooProblemSeverity.error);
    });

    test('a name where an id goes is turned into a lookup that is resolved when sent', () {
      final body = _create('parent_id', 'Azure Interior');
      final problems = _check(_json2Create, body).where((p) => p.code == 'many2one').toList();
      expect(problems.single.message, contains('{{ref:res.partner:Azure Interior}}'));
      final fixed = _fixed(_json2Create, body, 'many2one');
      expect(fixed, contains('"parent_id": {{ref:res.partner:Azure Interior}}'), reason: 'bare, so it becomes a number');
      expect(_vals(fixed), containsPair('parent_id', 0));
    });

    test('the selection error lists the allowed values', () {
      final p = _check(_json2Create, _create('type', 'banana')).single;
      expect(p.message, contains('Allowed: contact, invoice, delivery, other.'));
    });
  });

  group('x2many commands', () {
    test('a plain list of ids, or one id, is turned into the command that was meant', () {
      expect(_vals(_fixed(_json2Create, _create('category_id', [1, 2]), 'x2many')), containsPair('category_id', [[6, 0, [1, 2]]]));
      expect(_vals(_fixed(_json2Create, _create('category_id', 5), 'x2many')), containsPair('category_id', [[4, 5]]));
    });

    test('every wrong shape of a command is named', () {
      List<String> messages(Object? commands) => [for (final p in _check(_json2Create, _create('category_id', commands)).where((p) => p.code == 'x2many')) p.message];
      expect(messages([[9, 1]]).single, contains('starts with 9, which is not a command'));
      expect(messages(['link']).single, contains('must be a list starting with a number 0 to 6'));
      expect(messages([[0, 0]]).single, contains('create is [0, 0, {values}]'));
      expect(messages([[0, 1, {}]]).single, contains('create is [0, 0, {values}]'));
      expect(messages([[1, 4]]).single, contains('update is [1, id, {values}]'));
      expect(messages([[4]]).single, contains('link (4, id) takes the id'));
      expect(messages([[4, 'x']]).single, contains('takes the id'));
      expect(messages([[6, 0, 5]]).single, contains('set is [6, 0, [id, id, ...]]'));
      expect(messages([[6, 1, []]]).single, contains('set is'));
      expect(messages([[6, 0, ['a']]]).single, contains('must be numbers'));
      expect(messages('x').single, contains('but the value is text'));
      // Right ones.
      expect(messages([[0, 0, {'name': 'T'}], [1, 3, {'name': 'U'}], [2, 4], [3, 5], [4, 6], [5, 0, 0], [5], [6, 0, [1, 2]], [4, 7, 0]]), isEmpty);
    });

    test('the records created inside a command are checked against their own model, without asking for the parent link', () {
      final nested = _check(_json2Create, jsonEncode({'vals_list': [{'name': 'Co', 'child_ids': [[0, 0, {'nmae': 'Kid', 'color': 'x'}], [1, 4, {'email': 5}]]}]}));
      expect(nested.map((p) => p.path), containsAll(['vals_list[0].child_ids[0][2].nmae', 'vals_list[0].child_ids[0][2].color', 'vals_list[0].child_ids[1][2].email']));
      expect(nested.where((p) => p.code == 'required'), isEmpty, reason: 'the parent fills the link and the name check belongs to the top-level create');
      final tags = _check(_json2Create, jsonEncode({'vals_list': [{'name': 'Co', 'category_id': [[0, 0, {'colour': 1}]]}]}));
      expect(tags.single.message, contains('does not exist on res.partner.category'));
    });
  });

  group('the required fields of create', () {
    test('without the list of defaults it is a warning, with it an error, and a field with a default is not missing', () {
      const body = '{"vals_list": [{"email": "a@b.c"}]}';
      final unknown = _check(_json2Create, body, context: _context(defaults: null));
      expect(unknown.single.code, 'required');
      expect(unknown.single.severity, OdooProblemSeverity.warning);
      expect(unknown.single.message, contains('unless Odoo has a default'));
      final known = _check(_json2Create, body);
      expect(known.single.severity, OdooProblemSeverity.error);
      expect(known.single.message, contains('has no default'));
      expect(_check(_json2Create, body, context: _context(defaults: const {'name'})), isEmpty);
    });

    test('the fix adds the field with a value of its type', () {
      final fixed = _fixed(_json2Create, '{"vals_list": [{"email": "a@b.c"}]}', 'required');
      expect(jsonDecode(fixed), {
        'vals_list': [
          {'email': 'a@b.c', 'name': ''},
        ],
      });
    });

    test('write never asks for required fields', () {
      expect(_check(_json2Write, '{"ids": [1], "vals": {"email": "a@b.c"}}'), isEmpty);
    });

    test('every record of vals_list is judged', () {
      final problems = _check(_json2Create, '{"vals_list": [{"name": "A"}, {"email": "x"}]}');
      expect(problems.single.path, 'vals_list[1].name');
    });
  });

  group('parameters and ids', () {
    test('vals for create and vals_list for write, the usual mix-ups', () {
      expect(jsonDecode(_fixed(_json2Create, '{"vals": {"name": "A"}}', 'param_name')), {
        'vals_list': [
          {'name': 'A'},
        ],
      });
      expect(jsonDecode(_fixed(_json2Write, '{"ids": [1], "vals_list": [{"name": "A"}]}', 'param_name')), {'ids': [1], 'vals': {'name': 'A'}});
      final unfixable = _check(_json2Write, '{"ids": [1], "vals_list": [{"name": "A"}, {"name": "B"}]}').firstWhere((p) => p.code == 'param_name');
      expect(unfixable.fix, isNull);
    });

    test('a misspelt parameter is renamed', () {
      final body = '{"domian": [], "fields": ["name"]}';
      final problems = _check(_json2Search, body);
      expect(problems.single.code, 'param_unknown');
      expect(problems.single.message, contains('did you mean "domain"'));
      expect(jsonDecode(_fixed(_json2Search, body, 'param_unknown')), {'domain': [], 'fields': ['name']});
    });

    test('a method on records needs ids, as a list', () {
      expect(_check('/json/2/res.partner/unlink', '{}').single.code, 'ids_missing');
      expect(jsonDecode(_fixed('/json/2/res.partner/unlink', '{"ids": 5}', 'ids_type')), {'ids': [5]});
      expect(_check('/json/2/res.partner/unlink', '{"ids": []}').single.code, 'ids_empty');
      expect(_check('/json/2/res.partner/unlink', '{"ids": [{{recordId}}]}'), isEmpty);
      expect(_check('/json/2/res.partner/some_custom_action', '{"anything": 1}'), isEmpty, reason: 'a method the table does not know is not judged');
    });
  });

  group('domains', () {
    List<OdooProblem> domain(Object? d) => _check(_json2Search, jsonEncode({'domain': d}));

    test('an operator that does not exist is replaced by the nearest one', () {
      final p = domain([['name', 'iilike', 'a']]).single;
      expect(p.code, 'operator');
      expect(p.message, contains('Did you mean "ilike"'));
      expect(jsonDecode(_fixed(_json2Search, jsonEncode({'domain': [['name', 'iilike', 'a']]}), 'operator')), {
        'domain': [['name', 'ilike', 'a']],
      });
      expect(domain([['name', '~', 'a']]).single.fix, isNull, reason: 'nothing is close to ~');
    });

    test('an operator that exists but does not suit the type is a warning that lists the right ones', () {
      final p = domain([['color', 'ilike', 'a']]).single;
      expect(p.severity, OdooProblemSeverity.warning);
      expect(p.message, contains('(type integer)'));
      expect(p.message, contains('=, !=, >, >=, <, <=, in, not in'));
      expect(domain([['is_company', '>', true]]).single.code, 'operator');
      expect(domain([['name', 'child_of', 1]]).single.severity, OdooProblemSeverity.warning);
    });

    test('in and not in need a list', () {
      final p = domain([['parent_id', 'in', 5]]).single;
      expect(p.message, contains('compares with a list'));
      expect(jsonDecode(_fixed(_json2Search, jsonEncode({'domain': [['parent_id', 'in', 5]]}), 'operator')), {
        'domain': [['parent_id', 'in', [5]]],
      });
      expect(domain([['parent_id', 'in', [5, 6]]]), isEmpty);
    });

    test('the shape of the domain is checked: prefix operators, three-part conditions', () {
      expect(domain([['name', '=', 'a'], ['color', '=', 1]]), isEmpty, reason: 'an implicit AND');
      expect(domain(['|', ['name', '=', 'a'], ['color', '=', 1]]), isEmpty);
      expect(domain(['!', ['name', '=', 'a']]), isEmpty);
      expect(domain(['|', ['name', '=', 'a']]).single.message, contains('has no condition to join'));
      expect(domain([['name', '=']]).single.message, contains('three parts'));
      expect(domain(['and', ['name', '=', 'a']]).single.message, contains('must be "&", "|", "!"'));
      expect(domain('name = a').single.message, contains('must be a list of conditions'));
    });

    test('values are compared with the type of the field', () {
      expect(jsonDecode(_fixed(_json2Search, jsonEncode({'domain': [['color', '=', '7']]}), 'type')), {
        'domain': [['color', '=', 7]],
      });
      expect(domain([['type', '=', 'invoce']]).single.message, contains('Did you mean "invoice"'));
      expect(domain([['parent_id', '=', '5']]).single.severity, OdooProblemSeverity.warning);
      expect(domain([['date', '>=', 'yesterday']]).single.code, 'type');
      expect(domain([['name', 'ilike', 5]]), isEmpty);
      expect(domain([['parent_id', '=', false]]), isEmpty);
    });

    test('the same checks run on the domain of a call_kw', () {
      final body = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {'model': 'res.partner', 'method': 'search_read', 'args': [[['colour', '=', 1]], ['name']], 'kwargs': {'limit': 5}},
      });
      final problems = _check('/web/dataset/call_kw', body);
      expect(problems.single.code, 'unknown_field');
      expect(problems.single.path, 'domain[0][0]');
    });
  });

  group('fixes on a request written for Odoo 18', () {
    const url = '/web/dataset/call_kw/res.partner/write';

    test('a call_kw body is rewritten in the same layout with the fix applied', () {
      final body = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {'model': 'res.partner', 'method': 'write', 'args': [[7], {'nmae': 'X', 'color': '3'}], 'kwargs': {}},
      });
      final shape = _shape(url, body);
      expect(shape.protocol.name, 'jsonRpc');
      expect(shape.named, {'ids': [7], 'vals': {'nmae': 'X', 'color': '3'}});
      final problems = OdooRequestChecker.check(shape, _context());
      expect(_codes(problems), {'unknown_field', 'type'});
      final fixed = jsonDecode(OdooRequestChecker.applyFixes(shape, [for (final p in problems) p.fix!]));
      expect(fixed['params'], {
        'model': 'res.partner',
        'method': 'write',
        'args': [[7], {'name': 'X', 'color': 3}],
        'kwargs': <String, Object?>{},
      });
    });

    test('{{variables}} survive a fix, in JSON-2 and in call_kw', () {
      final json2 = OdooRequestChecker.applyFixes(
        _shape(_json2Write, '{"ids": [{{recordId}}], "vals": {"nmae": "x", "parent_id": {{pid}}}}'),
        [for (final p in _check(_json2Write, '{"ids": [{{recordId}}], "vals": {"nmae": "x", "parent_id": {{pid}}}}')) p.fix!],
      );
      expect(json2, contains('[{{recordId}}]'));
      expect(json2, contains('"parent_id": {{pid}}'));
      expect(json2, contains('"name": "x"'));
      const rpc = '{"jsonrpc":"2.0","method":"call","params":{"model":"res.partner","method":"write","args":[[{{recordId}}],{"nmae":"x"}],"kwargs":{}}}';
      final shape = _shape(url, rpc);
      final fixed = OdooRequestChecker.applyFixes(shape, [for (final p in OdooRequestChecker.check(shape, _context())) p.fix!]);
      expect(fixed, contains('[{{recordId}}]'));
      expect(fixed, contains('"name": "x"'));
    });

    test('a fix of a body that was not touched leaves a copy: the original shape is never changed', () {
      final shape = _shape(_json2Write, '{"ids": [1], "vals": {"nmae": "x"}}');
      final before = jsonEncode(shape.named);
      OdooRequestChecker.applyFixes(shape, [for (final p in OdooRequestChecker.check(shape, _context())) p.fix!]);
      expect(jsonEncode(shape.named), before);
    });
  });

  group('reading a request', () {
    test('a body that is not JSON, or a URL that is not Odoo, says so', () {
      expect(OdooRequestShape.read(_json2Write, '{"ids": [1],').error, startsWith('The body is not valid JSON'));
      expect(OdooRequestShape.read('https://api.example.com/users', '{}').error, contains('not an Odoo call'));
      expect(OdooRequestShape.read(_json2Write, '[1, 2]').error, 'The body must be a JSON object.');
      expect(OdooRequestShape.read('/web/dataset/call_kw', '{"params": {"args": []}}').error, contains('params.model'));
    });

    test('the model and the method come from the URL, and a variable in the URL means unknown', () {
      expect(OdooRequestShape.ofUrl('{{odooUrl}}/json/2/res.partner/search_read?x=1')!.model, 'res.partner');
      expect(OdooRequestShape.ofUrl('https://x/json/2/{{model}}/create')!.model, '');
      expect(OdooRequestShape.ofUrl('https://x/web/dataset/call_kw/sale.order/action_confirm')!.method, 'action_confirm');
      expect(OdooRequestShape.ofUrl('https://x/api/users'), isNull);
    });

    test('an empty body is an empty object', () {
      expect(_shape('/json/2/res.partner/search', '').named, isEmpty);
    });
  });

  group('did you mean', () {
    test('counts a swap of two letters as one step', () {
      expect(OdooNames.distance('parnter_id', 'partner_id'), 1);
      expect(OdooNames.distance('kitten', 'sitting'), 3);
      expect(OdooNames.distance('', 'abc'), 3);
      expect(OdooNames.distance('same', 'same'), 0);
    });

    test('suggests near misses first, then names that contain the word, and not the name itself', () {
      final names = _partner.fields.map((f) => f.name);
      expect(OdooNames.suggest('emial', names), ['email']);
      expect(OdooNames.suggest('parnter_id', names), ['parent_id']);
      expect(OdooNames.suggest('partner', names), contains('commercial_partner_id'), reason: 'a name that contains the word');
      expect(OdooNames.suggest('categ', names), ['category_id']);
      expect(OdooNames.suggest('name', names), isNot(contains('name')));
      expect(OdooNames.suggest('zzzzzz', names), isEmpty);
      expect(OdooNames.suggest('', names), isEmpty);
    });
  });
}
