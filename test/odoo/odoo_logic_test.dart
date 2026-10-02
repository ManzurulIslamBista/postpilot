import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/odoo/domain/entities/odoo_model_info.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_dart_generator.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_domain.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_error_parser.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_json2.dart';
import 'package:postpilot/features/odoo/domain/services/odoo_rpc_converter.dart';
import 'package:postpilot/features/odoo/domain/services/python_literal.dart';

const _fieldsGet = '''
{
  "id": {"type": "integer", "string": "ID", "readonly": true, "store": true},
  "name": {"type": "char", "string": "Name", "required": true, "store": true},
  "is_company": {"type": "boolean", "string": "Is a Company", "store": true},
  "type": {"type": "selection", "string": "Address Type", "selection": [["contact","Contact"],["invoice","Invoice"],["other","Other"]], "store": true},
  "parent_id": {"type": "many2one", "string": "Related Company", "relation": "res.partner", "store": true},
  "child_ids": {"type": "one2many", "string": "Contact", "relation": "res.partner", "store": true},
  "birthday": {"type": "date", "string": "Birthday", "store": true},
  "write_date": {"type": "datetime", "string": "Last Updated", "readonly": true, "store": true},
  "credit": {"type": "monetary", "string": "Credit", "store": true},
  "display_name": {"type": "char", "string": "Display Name", "store": false}
}
''';

void main() {
  group('OdooModelInfo', () {
    test('parses a JSON-2 fields_get body', () {
      final m = OdooModelInfo.parse('res.partner', _fieldsGet)!;
      expect(m.fields.first.name, 'id');
      expect(m.field('name')!.required, isTrue);
      expect(m.field('type')!.selection, [('contact', 'Contact'), ('invoice', 'Invoice'), ('other', 'Other')]);
      expect(m.field('parent_id')!.relation, 'res.partner');
      expect(m.field('display_name')!.stored, isFalse);
    });

    test('unwraps the legacy JSON-RPC envelope and rejects other JSON', () {
      expect(OdooModelInfo.parse('m', '{"jsonrpc":"2.0","id":1,"result":{"a":{"type":"char"}}}')!.fields.single.name, 'a');
      expect(OdooModelInfo.parse('m', '{"foo":1}'), isNull);
      expect(OdooModelInfo.parse('m', 'nope'), isNull);
      expect(OdooModelInfo.parse('m', '{}'), isNull);
    });
  });

  group('OdooJson2', () {
    test('builds the documented request shape', () {
      const call = OdooCall(
        model: 'res.partner',
        method: 'search_read',
        params: {'domain': [['name', 'ilike', 'deco']], 'fields': ['name']},
        context: {'lang': 'en_US'},
      );
      expect(call.path, '/json/2/res.partner/search_read');
      expect(jsonDecode(call.bodyText), {
        'context': {'lang': 'en_US'},
        'domain': [['name', 'ilike', 'deco']],
        'fields': ['name'],
      });
      final d = OdooJson2.draft(call);
      expect(d.url, '{{odooUrl}}/json/2/res.partner/search_read');
      expect(d.headers['Authorization'], 'bearer {{odooApiKey}}');
      expect(d.headers['X-Odoo-Database'], '{{odooDb}}');
    });

    test('ids are only sent for recordset calls', () {
      expect(const OdooCall(model: 'm', method: 'unlink', ids: [1, 2]).body, {'ids': [1, 2]});
      expect(const OdooCall(model: 'm', method: 'search').body, isEmpty);
    });

    test('templates cover the common operations with valid JSON bodies', () {
      final t = OdooJson2.templatesFor('sale.order', sampleFields: ['name', 'amount_total']);
      expect(t.length, 10);
      for (final d in t) {
        expect(d.url, contains('/json/2/sale.order/'));
        expect(() => jsonDecode(d.bodyText), returnsNormally);
      }
      final create = t.firstWhere((d) => d.name == 'Create sale.order');
      expect(jsonDecode(create.bodyText), containsPair('vals_list', isA<List<dynamic>>()));
      final write = t.firstWhere((d) => d.name == 'Update sale.order');
      expect(jsonDecode(write.bodyText), allOf(containsPair('ids', [1]), containsPair('vals', isA<Map<String, dynamic>>())));
    });
  });

  group('OdooDomain', () {
    test('writes prefix notation for AND, OR and NOT', () {
      const a = DomainLeaf('state', '=', 'sale');
      const b = DomainLeaf('amount', '>', 100);
      const c = DomainLeaf('x', '=', 1);
      expect(OdooDomain.toList(const DomainGroup(children: [a, b])), [
        '&',
        ['state', '=', 'sale'],
        ['amount', '>', 100],
      ]);
      expect(OdooDomain.toList(const DomainGroup(any: true, children: [a, b, c])), [
        '|',
        '|',
        ['state', '=', 'sale'],
        ['amount', '>', 100],
        ['x', '=', 1],
      ]);
      expect(OdooDomain.toList(const DomainNot(a)), [
        '!',
        ['state', '=', 'sale'],
      ]);
      expect(OdooDomain.toList(const DomainGroup()), isEmpty);
      expect(OdooDomain.toList(const DomainGroup(children: [a])), [
        ['state', '=', 'sale'],
      ]);
    });

    test('reads a domain back, including implicit AND and flattened chains', () {
      final g = OdooDomain.fromList([
        ['a', '=', 1],
        ['b', '=', 2],
      ]) as DomainGroup;
      expect(g.any, isFalse);
      expect(g.children, hasLength(2));
      final or = OdooDomain.fromList([
        '|',
        '|',
        ['a', '=', 1],
        ['b', '=', 2],
        ['c', '=', 3],
      ]) as DomainGroup;
      expect(or.any, isTrue);
      expect(or.children, hasLength(3));
      expect(OdooDomain.fromList(['|', ['a', '=', 1]]), isNull);
      expect(OdooDomain.fromList(['bogus']), isNull);
    });

    test('round-trips through toList / fromList', () {
      const tree = DomainGroup(children: [
        DomainLeaf('a', '=', 1),
        DomainGroup(any: true, children: [DomainLeaf('b', '=', 2), DomainLeaf('c', 'ilike', 'x')]),
        DomainNot(DomainLeaf('d', '=', false)),
      ]);
      final list = OdooDomain.toList(tree);
      expect(OdooDomain.toList(OdooDomain.fromList(list)!), list);
    });

    test('python form uses tuples and Python literals', () {
      const g = DomainGroup(children: [DomainLeaf('active', '=', true), DomainLeaf('name', 'ilike', "O'Neil")]);
      expect(OdooDomain.toPython(g), r"['&', ('active', '=', True), ('name', 'ilike', 'O\'Neil')]");
    });

    test('parses JSON and Python text', () {
      final json = OdooDomain.parseText('[["a","=",1]]') as DomainGroup;
      expect((json.children.single as DomainLeaf).field, 'a');
      final py = OdooDomain.parseText("[('is_company', '=', True), ('name', 'ilike', 'x')]") as DomainGroup;
      expect(py.children, hasLength(2));
      expect((py.children.first as DomainLeaf).value, true);
      expect(OdooDomain.parseText(''), isA<DomainGroup>());
      expect(OdooDomain.parseText('not a domain'), isNull);
    });

    test('typed values', () {
      const int = OdooField(name: 'n', type: 'integer', label: 'N');
      expect(OdooDomain.parseValue('42', operator: '=', field: int), 42);
      expect(OdooDomain.parseValue('1, 2,3', operator: 'in', field: int), [1, 2, 3]);
      expect(OdooDomain.parseValue('true', operator: '=', field: const OdooField(name: 'b', type: 'boolean', label: 'B')), true);
      expect(OdooDomain.parseValue('abc', operator: 'ilike'), 'abc');
      expect(OdooDomain.parseValue('', operator: 'in'), isEmpty);
    });
  });

  group('PythonLiteral', () {
    test('reads calls with every literal kind', () {
      final c = PythonLiteral.callArguments(
        "models.execute_kw(db, uid, password, 'res.partner', 'search_read', [[('is_company', '=', True)]], "
        '{"fields": ["name", \'email\'], "limit": 5, "x": None, "f": -1.5})',
        'execute_kw',
      )!;
      expect(c.positional[0], '{{db}}');
      expect(c.positional[3], 'res.partner');
      expect(c.positional[5], [
        [
          ['is_company', '=', true],
        ],
      ]);
      expect(c.positional[6], {
        'fields': ['name', 'email'],
        'limit': 5,
        'x': null,
        'f': -1.5,
      });
    });

    test('keywords, comments, trailing commas and multi-line', () {
      final c = PythonLiteral.callArguments('''
foo(1,  # one
    "two",
    key=[1, 2,],
)''', 'foo')!;
      expect(c.positional, [1, 'two']);
      expect(c.keywords, {'key': [1, 2]});
    });

    test('returns null for a missing call or broken syntax', () {
      expect(PythonLiteral.callArguments('print(1)', 'execute_kw'), isNull);
      expect(PythonLiteral.callArguments("execute_kw('a', ", 'execute_kw'), isNull);
      expect(PythonLiteral.parse('[1, 2'), isNull);
      expect(PythonLiteral.parse("{'a': [1]}"), {'a': [1]});
    });
  });

  group('OdooRpcConverter', () {
    test('converts an xmlrpc execute_kw search_read', () {
      final r = OdooRpcConverter.convert(
        "models.execute_kw(db, uid, password, 'res.partner', 'search_read', [[['is_company','=',True]]], {'fields': ['name'], 'limit': 5})",
      );
      final call = r.conversion!.call;
      expect(call.model, 'res.partner');
      expect(call.method, 'search_read');
      expect(call.params['domain'], [
        ['is_company', '=', true],
      ]);
      expect(call.params['fields'], ['name']);
      expect(call.params['limit'], 5);
      expect(call.ids, isEmpty);
    });

    test('recordset methods take ids from the first argument', () {
      final read = OdooRpcConverter.convert("m.execute_kw(db,uid,pw,'res.partner','read',[[1,2,3]],{'fields':['name']})")
          .conversion!
          .call;
      expect(read.ids, [1, 2, 3]);
      expect(read.params, {'fields': ['name']});
      final write = OdooRpcConverter.convert("m.execute_kw(db,uid,pw,'res.partner','write',[[7],{'name':'X'}])").conversion!.call;
      expect(write.ids, [7]);
      expect(write.params, {'vals': {'name': 'X'}});
      final unlink = OdooRpcConverter.convert("m.execute_kw(db,uid,pw,'res.partner','unlink',[[9]])").conversion!.call;
      expect(unlink.ids, [9]);
      expect(unlink.params, isEmpty);
    });

    test('legacy create with one dict becomes vals_list', () {
      final c = OdooRpcConverter.convert("m.execute_kw(db,uid,pw,'res.partner','create',[{'name':'New'}])").conversion!.call;
      expect(c.params['vals_list'], [
        {'name': 'New'},
      ]);
    });

    test('context moves out of kwargs; name_search args becomes domain', () {
      final c = OdooRpcConverter.convert(
        "m.execute_kw(db,uid,pw,'res.partner','name_search',[],{'name':'a','args':[['x','=',1]],'context':{'lang':'fr_FR'}})",
      ).conversion!.call;
      expect(c.context, {'lang': 'fr_FR'});
      expect(c.params['domain'], [
        ['x', '=', 1],
      ]);
      expect(c.params['name'], 'a');
    });

    test('converts JSON-RPC bodies: /jsonrpc, call_kw and dataset/search_read', () {
      final rpc = OdooRpcConverter.convert(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'service': 'object',
          'method': 'execute_kw',
          'args': ['db', 2, 'pw', 'res.partner', 'search_count', [[]], {}],
        },
      }));
      expect(rpc.conversion!.call.method, 'search_count');
      expect(rpc.conversion!.call.params['domain'], isEmpty);

      final kw = OdooRpcConverter.convert(jsonEncode({
        'params': {
          'model': 'sale.order',
          'method': 'action_confirm',
          'args': [[5]],
          'kwargs': {},
        },
      }));
      expect(kw.conversion!.call.ids, [5]);
      expect(kw.conversion!.call.method, 'action_confirm');

      final sr = OdooRpcConverter.convert(jsonEncode({
        'params': {'model': 'res.partner', 'domain': [], 'fields': ['name'], 'limit': 80, 'sort': 'name asc'},
      }));
      expect(sr.conversion!.call.method, 'search_read');
      expect(sr.conversion!.call.params['order'], 'name asc');
    });

    test('notes unknown methods and removed ones', () {
      final unknown = OdooRpcConverter.convert("m.execute_kw(db,uid,pw,'x.y','my_method',['a'])").conversion!;
      expect(unknown.notes.join(' '), contains('not a standard method'));
      expect(unknown.call.params['arg0'], 'a');
      final nameGet = OdooRpcConverter.convert("m.execute_kw(db,uid,pw,'x.y','name_get',[[1]])").conversion!;
      expect(nameGet.notes.join(' '), contains('removed'));
    });

    test('reports what is wrong with input it cannot convert', () {
      expect(OdooRpcConverter.convert('').error, isNotNull);
      expect(OdooRpcConverter.convert('print("hi")').error, contains('execute_kw'));
      expect(OdooRpcConverter.convert('{bad json').error, contains('JSON'));
      expect(OdooRpcConverter.convert('{"a": 1}').error, contains('recognise'));
    });
  });

  group('OdooErrorParser', () {
    test('reads a JSON-2 error and explains an invalid key', () {
      final e = OdooErrorParser.parse(jsonEncode({
        'name': 'werkzeug.exceptions.Unauthorized',
        'message': 'Invalid apikey',
        'arguments': ['Invalid apikey', 401],
        'context': {},
        'debug': 'Traceback (most recent call last):\n  File "/odoo/http.py", line 1, in x\nUnauthorized: 401',
      }), statusCode: 401)!;
      expect(e.title, 'Invalid API key');
      expect(e.hint, contains('API Key'));
      expect(e.failingLine, 'Unauthorized: 401');
    });

    test('reads a legacy JSON-RPC error with traceback frames', () {
      final e = OdooErrorParser.parse(jsonEncode({
        'jsonrpc': '2.0',
        'error': {
          'code': 200,
          'message': 'Odoo Server Error',
          'data': {
            'name': 'odoo.exceptions.AccessError',
            'message': 'You are not allowed to access Contact',
            'arguments': ['x'],
            'debug': 'Traceback\n  File "/opt/odoo/odoo/models.py", line 4, in check\n  File "/opt/odoo/addons/base/models/res_partner.py", line 99, in write\nodoo.exceptions.AccessError: nope',
          },
        },
      }))!;
      expect(e.title, 'Access denied');
      expect(e.frames, isNotEmpty);
      expect(e.frames.last, 'addons/base/models/res_partner.py:99 in write');
    });

    test('explains wrong parameter names', () {
      final e = OdooErrorParser.parse(jsonEncode({
        'name': 'builtins.TypeError',
        'message': "search_read() got an unexpected keyword argument 'domian'",
        'arguments': [],
      }))!;
      expect(e.title, 'Unknown parameter');
      expect(e.hint, contains('domian'));
    });

    test('ignores anything that is not an Odoo error', () {
      expect(OdooErrorParser.parse('[{"id":1}]'), isNull);
      expect(OdooErrorParser.parse('<html>'), isNull);
      expect(OdooErrorParser.parse('{"error":"plain string"}'), isNull);
      expect(OdooErrorParser.parse('{"name":"x"}'), isNull);
    });
  });

  group('OdooDartGenerator', () {
    final model = OdooModelInfo.parse('res.partner', _fieldsGet)!;

    test('generates a class that reads Odoo-style JSON', () {
      final files = const OdooDartGenerator().generate(model);
      expect(files.map((f) => f.path), ['lib/models/res_partner.dart', 'lib/models/odoo_json.dart']);
      final code = files.first.content;
      expect(code, contains('class ResPartner {'));
      expect(code, contains('final int? id;'));
      expect(code, contains('final String? name;'));
      expect(code, contains('final bool isCompany;'));
      expect(code, contains('final OdooRef? parentId;'));
      expect(code, contains('final List<int> childIds;'));
      expect(code, contains('final DateTime? birthday;'));
      expect(code, contains('final double? credit;'));
      expect(code, contains('final ResPartnerType? type;'));
      expect(code, contains("isCompany: odooBool(json['is_company'])"));
      expect(code, contains("parentId: OdooRef.from(json['parent_id'])"));
      expect(code, contains("writeDate: odooDateTime(json['write_date'])"));
      expect(code, isNot(contains('displayName')), reason: 'computed fields are skipped by default');
      expect(code, contains("static const fieldNames = ['id', 'birthday'"));
      expect(code, contains('enum ResPartnerType {'));
      expect(code, contains("contact('contact', 'Contact')"));
      expect(code, contains('static ResPartnerType? fromOdoo(Object? value)'));
    });

    test('toJson skips ids, read-only fields and unset values', () {
      final code = const OdooDartGenerator().generate(model).first.content;
      final toJson = code.substring(code.indexOf('toJson()'));
      expect(toJson, contains("if (name != null) 'name': name!"));
      expect(toJson, contains("'is_company': isCompany"));
      expect(toJson, contains("if (parentId != null) 'parent_id': parentId!.id"));
      expect(toJson, contains("if (type != null) 'type': type!.odoo"));
      expect(toJson, isNot(contains("'id'")));
      expect(toJson, isNot(contains('write_date')));
    });

    test('field filter and computed switch', () {
      final only = const OdooDartGenerator().generate(model, options: const OdooDartOptions(fieldNames: {'name'})).first.content;
      expect(only, contains('final String? name;'));
      expect(only, isNot(contains('isCompany')));
      final all = const OdooDartGenerator().generate(model, options: const OdooDartOptions(includeComputed: true)).first.content;
      expect(all, contains('displayName'));
    });
  });
}
