import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/response_tools/domain/services/bug_report_builder.dart';
import 'package:postpilot/features/response_tools/domain/services/json_diff.dart';
import 'package:postpilot/features/response_tools/domain/services/json_schema_tools.dart';
import 'package:postpilot/features/response_tools/domain/services/json_table.dart';
import 'package:postpilot/features/response_tools/domain/services/json_tree.dart';
import 'package:postpilot/features/response_tools/domain/services/quick_decoder.dart';
import 'package:postpilot/features/scripting/domain/evaluator/json_path_resolver.dart';

String _b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');

void main() {
  group('JsonTree / JsonPaths', () {
    final json = {
      'data': {
        'items': [
          {'id': 1, 'a.b': 'x'},
        ],
      },
    };

    test('paths read back through JsonPathResolver', () {
      final node = JsonNode.root(json).children.single.children.single.children.single;
      expect(node.path, 'data.items[0]');
      final id = node.children.firstWhere((n) => n.label == 'id');
      expect(JsonPathResolver.resolve(json, id.path), 1);
      final odd = node.children.firstWhere((n) => n.label == 'a.b');
      expect(odd.path, 'data.items[0]["a.b"]');
      expect(JsonPathResolver.resolve(json, odd.path), 'x');
    });

    test('previews and kinds', () {
      expect(JsonNode.root(json).preview, '{1}');
      expect(JsonNode(label: 'k', path: 'k', value: 'hi').preview, '"hi"');
      expect(JsonNode(label: 'k', path: 'k', value: null).kind, JsonNodeKind.nullValue);
    });

    test('search finds keys and values and caps results', () {
      expect(JsonNode.search(json, 'items'), contains('data.items'));
      expect(JsonNode.search(json, 'x'), contains('data.items[0]["a.b"]'));
      expect(JsonNode.search(List.generate(500, (i) => 'match$i'), 'match', limit: 10), hasLength(10));
      expect(JsonNode.search(json, ''), isEmpty);
    });
  });

  group('JWT, epoch and quick decode', () {
    final token =
        '${_b64({'alg': 'HS256'})}.${_b64({'sub': '1', 'exp': 1700000000, 'iat': 1699990000})}.sig123';

    test('decodes a JWT and reads its times', () {
      final jwt = JwtDecoder.tryDecode('Bearer $token')!;
      expect(jwt.header['alg'], 'HS256');
      expect(jwt.expiresAt, DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(jwt.isExpired(DateTime.utc(2026)), isTrue);
      expect(jwt.isExpired(DateTime.utc(2023)), isFalse);
      expect(JwtDecoder.tryDecode('a.b.c'), isNull);
      expect(JwtDecoder.tryDecode('hello'), isNull);
    });

    test('finds JWTs inside a response', () {
      final found = JwtDecoder.findIn({
        'data': {'access_token': token},
        'other': 'plain',
      });
      expect(found.keys.single, 'data.access_token');
    });

    test('epoch guess picks the unit and ignores ordinary numbers', () {
      expect(EpochConverter.guess(1700000000)!.unit, 'seconds');
      expect(EpochConverter.guess(1700000000000)!.unit, 'milliseconds');
      expect(EpochConverter.guess(42), isNull);
      expect(EpochConverter.guess(1700000000.5), isNull);
      final hits = EpochConverter.findIn({'created_at': 1700000000, 'id': 1700000000, 'items': [{'exp': 1700000000}]});
      expect(hits.map((h) => h.path), ['created_at', 'items[0].exp']);
    });

    test('decodeAll offers every interpretation that applies', () {
      final kinds = QuickDecoder.decodeAll(token).map((r) => r.kind);
      expect(kinds, containsAll(['JWT header', 'JWT payload']));
      expect(QuickDecoder.decodeAll('1700000000').map((r) => r.kind), contains('Unix time (seconds)'));
      expect(QuickDecoder.decodeAll('SGVsbG8gd29ybGQ=').firstWhere((r) => r.kind == 'Base64').output, 'Hello world');
      expect(QuickDecoder.decodeAll('a%20b%26c').firstWhere((r) => r.kind == 'URL-encoded').output, 'a b&c');
      expect(QuickDecoder.decodeAll('{"a":1}').map((r) => r.kind), contains('JSON (formatted)'));
      expect(QuickDecoder.decodeAll('   '), isEmpty);
    });
  });

  group('JsonDiff', () {
    test('reports added, removed and changed with resolvable paths', () {
      final r = JsonDiff.compare(
        {'a': 1, 'b': {'c': 2}, 'list': [1, 2, 3], 'gone': true},
        {'a': 1, 'b': {'c': 3}, 'list': [1, 2], 'new': 'x'},
      );
      String at(JsonChangeKind k) => r.changes.where((c) => c.kind == k).map((c) => c.path).join(',');
      expect(at(JsonChangeKind.changed), 'b.c');
      expect(at(JsonChangeKind.removed), contains('gone'));
      expect(at(JsonChangeKind.removed), contains('list[2]'));
      expect(at(JsonChangeKind.added), 'new');
      expect(r.isIdentical, isFalse);
    });

    test('ignored keys do not count and identical documents are identical', () {
      final a = {'id': 1, 'updated_at': 'x'};
      final b = {'id': 1, 'updated_at': 'y'};
      expect(JsonDiff.compare(a, b).isIdentical, isFalse);
      expect(JsonDiff.compare(a, b, ignoreKeys: {'UPDATED_AT'}).isIdentical, isTrue);
      expect(JsonDiff.compare([1, 2], [1, 2]).isIdentical, isTrue);
    });

    test('a scalar root change is reported at the root', () {
      final r = JsonDiff.compare(1, 2);
      expect(r.changes.single.path, r'$');
    });
  });

  group('JsonSchemaTools', () {
    test('infers types, required and formats from several samples', () {
      final schema = JsonSchemaTools.infer([
        {'id': 1, 'name': 'A', 'when': '2026-10-02T10:00:00Z', 'tags': ['x'], 'note': null},
        {'id': 2, 'name': 'B', 'when': '2026-10-03T10:00:00Z', 'tags': [], 'extra': 1.5},
      ]);
      expect(schema['type'], 'object');
      final props = schema['properties'] as Map<String, dynamic>;
      expect((props['id'] as Map)['type'], 'integer');
      expect((props['when'] as Map)['format'], 'date-time');
      expect(schema['required'], containsAll(['id', 'name', 'when', 'tags']));
      expect(schema['required'], isNot(contains('extra')));
      expect((props['note'] as Map)['type'], 'null');
    });

    test('validates types, required, nested paths and arrays', () {
      final schema = {
        'type': 'object',
        'required': ['id', 'name'],
        'properties': {
          'id': {'type': 'integer'},
          'name': {'type': 'string', 'minLength': 2},
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'status': {'enum': ['open', 'closed']},
        },
      };
      expect(JsonSchemaTools.validate(schema, {'id': 1, 'name': 'ab', 'tags': ['x'], 'status': 'open'}), isEmpty);
      final bad = JsonSchemaTools.validate(schema, {'id': '1', 'tags': ['x', 2], 'status': 'x'});
      final text = bad.join('\n');
      expect(text, contains(r'$.id: Expected integer, got string'));
      expect(text, contains('Missing required "name"'));
      expect(text, contains(r'$.tags[1]: Expected string, got integer'));
      expect(text, contains(r'$.status: Must be one of open, closed'));
    });

    test('nullable, number ranges, formats, additionalProperties', () {
      expect(JsonSchemaTools.validate({'type': 'string', 'nullable': true}, null), isEmpty);
      expect(JsonSchemaTools.validate({'type': 'string'}, null), isNotEmpty);
      expect(JsonSchemaTools.validate({'type': 'number', 'minimum': 1, 'maximum': 3}, 5).single.message, contains('above'));
      expect(JsonSchemaTools.validate({'type': 'integer'}, 2.0), isEmpty);
      expect(JsonSchemaTools.validate({'type': 'string', 'format': 'email'}, 'nope'), isNotEmpty);
      expect(JsonSchemaTools.validate({'type': 'string', 'format': 'uuid'}, '123e4567-e89b-12d3-a456-426614174000'), isEmpty);
      expect(
        JsonSchemaTools.validate({'type': 'object', 'properties': {'a': {}}, 'additionalProperties': false}, {'a': 1, 'b': 2})
            .single
            .message,
        contains('Unexpected'),
      );
    });

    test(r'resolves local $ref (OpenAPI components) and allOf/oneOf', () {
      final doc = {
        'components': {
          'schemas': {
            'Pet': {
              'type': 'object',
              'required': ['name'],
              'properties': {'name': {'type': 'string'}},
            },
          },
        },
        r'$ref': '#/components/schemas/Pet',
      };
      expect(JsonSchemaTools.validate(doc, {'name': 'Rex'}), isEmpty);
      expect(JsonSchemaTools.validate(doc, {'name': 1}), isNotEmpty);
      final one = {
        'oneOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
      };
      expect(JsonSchemaTools.validate(one, 'x'), isEmpty);
      expect(JsonSchemaTools.validate(one, true), isNotEmpty);
      expect(JsonSchemaTools.validate({r'$ref': '#/missing'}, 1).single.message, contains('Cannot resolve'));
    });

    test('inferred schema accepts its own samples', () {
      final samples = [
        {'a': 1, 'b': [1, 2]},
        {'a': 2, 'b': []},
      ];
      final schema = JsonSchemaTools.infer(samples);
      for (final s in samples) {
        expect(JsonSchemaTools.validate(schema, s), isEmpty);
      }
    });
  });

  group('JsonTable', () {
    test('finds the first array of objects, even nested', () {
      final t = JsonTable.find({
        'status': 'ok',
        'data': {
          'items': [
            {'id': 1, 'name': 'A'},
            {'id': 2, 'extra': 'x'},
          ],
        },
      })!;
      expect(t.path, 'data.items');
      expect(t.columns, ['id', 'name', 'extra']);
      expect(t.rows, hasLength(2));
      expect(JsonTable.find({'a': 1}), isNull);
      expect(JsonTable.find([1, 2]), isNull);
    });

    test('csv quotes commas, quotes and newlines', () {
      final t = JsonTable.find([
        {'a': 'x,y', 'b': 'say "hi"', 'c': 'l1\nl2'},
      ])!;
      expect(t.toCsv(), 'a,b,c\n"x,y","say ""hi""","l1\nl2"\n');
    });
  });

  group('BugReportBuilder', () {
    test('masks credentials in url, headers and bodies', () {
      final md = BugReportBuilder.build(
        method: 'POST',
        url: 'https://api.test/x?api_key=SECRET123&q=1',
        requestHeaders: {'Authorization': 'Bearer abc.def.ghi', 'Accept': 'application/json'},
        requestBody: '{"password":"hunter2","user":"ann"}',
        statusCode: 500,
        statusText: 'Server Error',
        durationMs: 120,
        sizeBytes: 2048,
        responseBody: '{"error":"boom","token":"zzz"}',
        note: 'Fails on login',
      );
      expect(md, contains('Fails on login'));
      expect(md, contains('**500 Server Error** · 120 ms · 2.0 KB'));
      expect(md, contains('q=1'));
      expect(md, contains('Accept: application/json'));
      expect(md, isNot(contains('SECRET123')));
      expect(md, isNot(contains('abc.def.ghi')));
      expect(md, isNot(contains('hunter2')));
      expect(md, isNot(contains('zzz')));
      expect(md, contains('"user": "ann"'));
    });

    test('long bodies are clipped', () {
      final md = BugReportBuilder.build(
        method: 'GET',
        url: 'https://a.test',
        statusCode: 200,
        responseBody: '{"a":"${'x' * 9000}"}',
        maxBodyChars: 500,
      );
      expect(md, contains('more characters'));
    });
  });
}
