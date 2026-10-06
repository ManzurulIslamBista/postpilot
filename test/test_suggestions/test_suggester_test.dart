import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/evaluator/assertion_evaluator.dart';
import 'package:postpilot/features/test_suggestions/domain/entities/test_suggestion.dart';
import 'package:postpilot/features/test_suggestions/domain/services/assertion_dedupe.dart';
import 'package:postpilot/features/test_suggestions/domain/services/test_suggester.dart';
import 'response_fixtures.dart';

const _suggester = TestSuggester();

TestSuggestion _row(SuggestionResult r, String id) => r.suggestions.firstWhere((s) => s.id == id, orElse: () => fail('no suggestion "$id" in ${r.suggestions.map((s) => s.id).toList()}'));

List<String> _ids(SuggestionResult r) => [for (final s in r.suggestions) s.id];

void main() {
  group('suggestions from one realistic response', () {
    final ordersResponse = response(ordersBody());
    final result = _suggester.suggest(ordersResponse);

    test('every proposal, in group order and document order', () {
      expect(_ids(result), [
        'status', 'content-type', 'time',
        'schema',
        'exists:data', 'exists:data.page', 'exists:data.next_cursor', 'exists:currency', 'exists:queueDepth',
        'exists:requestId', 'exists:ok', 'exists:tags',
        'array:data.orders', 'shape:data.orders',
        'enum:data.orders[].status',
        'format:data.orders[].id', 'format:data.orders[].email', 'format:data.orders[].created_at',
        'equals:data.page', 'equals:currency', 'equals:queueDepth', 'equals:ok',
      ]);
    });

    test('labels say what the check means in plain words', () {
      String label(String id) => _row(result, id).label;
      expect(label('status'), 'status is 200');
      expect(label('content-type'), 'Content-Type is application/json; charset=utf-8');
      expect(label('time'), 'response time is under 500 ms');
      expect(label('schema'), 'body has the fields and types seen here');
      expect(label('exists:data.page'), 'body.data.page exists');
      expect(label('array:data.orders'), 'body.data.orders is a non-empty array');
      expect(label('shape:data.orders'), 'body.data.orders elements have id, status, total, email, note, created_at');
      expect(label('enum:data.orders[].status'), 'body.data.orders[*].status is one of "paid", "shipped"');
      expect(label('format:data.orders[].id'), 'body.data.orders[*].id is a UUID');
      expect(label('format:data.orders[].email'), 'body.data.orders[*].email is an email address');
      expect(label('format:data.orders[].created_at'), 'body.data.orders[*].created_at is a date and time');
      expect(label('equals:currency'), 'body.currency equals "USD"');
      expect(label('equals:data.page'), 'body.data.page equals 1');
      expect(label('equals:ok'), 'body.ok equals true');
    });

    test('only the status, the content type and the whole-body schema are ticked to start with', () {
      final ticked = [for (final s in result.suggestions) if (s.recommended) s.id];
      expect(ticked, ['status', 'content-type', 'schema']);
    });

    test('the response time limit is three times the measurement, with a floor of 500 ms', () {
      final time = _row(result, 'time').assertion;
      expect(time.type, AssertionType.responseTimeBelowMs);
      expect(time.expected, '500'); // 120 ms x 3 = 360, rounded up to 400, raised to the floor
      final slow = _suggester.suggest(response(ordersBody(), ms: 1234));
      expect(_row(slow, 'time').assertion.expected, '3800'); // 3702 rounded up to 3800
    });

    test('the whole-body schema is the inferred one: types, nulls, required fields', () {
      final schema = jsonDecode(_row(result, 'schema').assertion.expected) as Map<String, dynamic>;
      expect(schema['type'], 'object');
      expect(schema['required'], ['currency', 'data', 'ok', 'queueDepth', 'requestId', 'tags']);
      final order = (((schema['properties'] as Map)['data'] as Map)['properties'] as Map)['orders'] as Map;
      final item = order['items'] as Map<String, dynamic>;
      expect(item['required'], ['created_at', 'email', 'id', 'note', 'status', 'total']);
      final props = item['properties'] as Map<String, dynamic>;
      expect((props['note'] as Map)['type'], ['null', 'string'], reason: 'null in some elements is allowed, not required');
      expect((props['total'] as Map)['type'], 'number', reason: '19.99 and 5 together are numbers');
      expect((props['created_at'] as Map)['format'], 'date-time');
    });

    test('pattern checks for ids, emails and dates look inside every element of the array', () {
      final id = _row(result, 'format:data.orders[].id').assertion;
      expect(id.type, AssertionType.jsonSchema);
      expect(id.path, 'data.orders');
      expect(jsonDecode(id.expected), {
        'type': 'array',
        'items': {
          'properties': {
            'id': {'type': 'string', 'format': 'uuid'},
          },
        },
      });
      expect(_row(result, 'format:data.orders[].id').confidence, SuggestionConfidence.high, reason: 'four values agree');
    });

    test('a small value set becomes an enum check, as a low-confidence extra', () {
      final enumRow = _row(result, 'enum:data.orders[].status');
      expect(jsonDecode(enumRow.assertion.expected), {
        'type': 'array',
        'items': {
          'properties': {
            'status': {
              'type': 'string',
              'enum': ['paid', 'shipped'],
            },
          },
        },
      });
      expect(enumRow.confidence, SuggestionConfidence.low);
      expect(enumRow.recommended, isFalse);
      expect(_ids(result).where((id) => id.startsWith('enum:')), ['enum:data.orders[].status'],
          reason: 'ids, emails and an optional note are not value sets');
    });

    test('arrays get a non-empty check and an element-shape check; an empty array gets neither', () {
      final nonEmpty = _row(result, 'array:data.orders').assertion;
      expect(nonEmpty.path, 'data.orders');
      expect(jsonDecode(nonEmpty.expected), {'type': 'array', 'minItems': 1});
      expect(_ids(result).contains('array:tags'), isFalse, reason: 'tags is empty: nothing to say about its items');
      expect(_ids(result).contains('shape:tags'), isFalse);
      expect(_ids(result).contains('exists:tags'), isTrue, reason: 'but the field itself is still required');
    });

    test('required-field checks skip containers below the top level and anything inside arrays', () {
      final exists = [for (final s in result.suggestions) if (s.id.startsWith('exists:')) s.assertion.path];
      expect(exists, ['data', 'data.page', 'data.next_cursor', 'currency', 'queueDepth', 'requestId', 'ok', 'tags']);
      expect(exists.any((p) => p.contains('[')), isFalse);
    });

    test('volatile values never become equals checks: ids, timestamps, cursors, request ids, counters', () {
      final equals = [for (final s in result.suggestions) if (s.assertion.type == AssertionType.jsonPathEquals) s.assertion.path];
      expect(equals, ['data.page', 'currency', 'queueDepth', 'ok']);
      expect(equals.contains('requestId'), isFalse, reason: 'a 64-bit id');
      expect(equals.contains('data.next_cursor'), isFalse, reason: 'a cursor token');
      expect(result.volatile.map((v) => v.label), ['body.data.next_cursor', 'body.requestId']);
      expect(result.volatile.map((v) => v.reason), ['it is a token or hash', 'it is an id']);
    });

    test('without a second response, exact values are low confidence and say they are unverified', () {
      final row = _row(result, 'equals:queueDepth');
      expect(row.confidence, SuggestionConfidence.low);
      expect(row.detail, contains('Not verified'));
      expect(row.recommended, isFalse);
      expect(result.probed, isFalse);
    });

    test('every proposal passes on the response it was made from', () {
      final results = const AssertionEvaluator().evaluate(ordersResponse, [for (final s in result.suggestions) s.assertion]);
      final failed = [
        for (var i = 0; i < results.length; i++)
          if (!results[i].passed) '${result.suggestions[i].id}: ${results[i].name} (${results[i].actual})',
      ];
      expect(failed, isEmpty);
    });
  });

  group('the stability probe', () {
    final first = response(ordersBody());
    final second = response(
      ordersBody(queueDepth: 15, cursor: 'ZGlmZmVyZW50LWN1cnNvci0xMjM0NTY3ODkwYWJjZGVmZ2hp', requestId: 9007199254740999),
      ms: 300,
    );
    final result = _suggester.suggest(first, probe: second);

    test('a field that changed between the two responses is not offered as an exact value', () {
      final equals = [for (final s in result.suggestions) if (s.assertion.type == AssertionType.jsonPathEquals) s.assertion.path];
      expect(equals, ['data.page', 'currency', 'ok'], reason: 'queueDepth went from 12 to 15');
      expect(result.probed, isTrue);
    });

    test('the fields that changed are listed with the evidence, ahead of the guesses', () {
      expect(result.volatile.map((v) => v.label), ['body.data.next_cursor', 'body.queueDepth', 'body.requestId']);
      expect(result.volatile.every((v) => v.reason == 'it changed between the two responses'), isTrue);
    });

    test('stable scalars become medium-confidence exact values, still unticked', () {
      final row = _row(result, 'equals:currency');
      expect(row.confidence, SuggestionConfidence.medium);
      expect(row.detail, 'The same in both responses.');
      expect(row.recommended, isFalse);
    });

    test('the schema and the time limit use both responses', () {
      expect(_row(result, 'schema').confidence, SuggestionConfidence.high);
      expect(_row(result, 'time').assertion.expected, '900', reason: 'the slower one, 300 ms x 3');
    });

    test('a field present in only one response is optional: not required, not in the schema', () {
      final withOptional = ordersBody();
      (withOptional['data'] as Map)['extra'] = 'x';
      final r = _suggester.suggest(response(withOptional), probe: response(ordersBody()));
      expect(_ids(r).contains('exists:data.extra'), isFalse);
      final schema = jsonDecode(_row(r, 'schema').assertion.expected) as Map<String, dynamic>;
      final data = (schema['properties'] as Map)['data'] as Map;
      expect(data['required'], isNot(contains('extra')));
      expect(((data['properties'] as Map).containsKey('extra')), isTrue, reason: 'still known, just optional');
      expect(r.volatile.map((v) => v.label), contains('body.data.extra'));
    });

    test('an array that was empty in the second response is not required to have items', () {
      final emptied = ordersBody();
      (emptied['data'] as Map)['orders'] = <Object?>[];
      final r = _suggester.suggest(response(ordersBody()), probe: response(emptied));
      expect(_ids(r).where((id) => id.contains('data.orders') && (id.startsWith('array:') || id.startsWith('shape:'))), isEmpty);
    });

    test('a second response with another status class is ignored, and the person is told', () {
      final r = _suggester.suggest(first, probe: response({'error': 'busy'}, status: 503));
      expect(r.probed, isFalse);
      expect(r.notes.single, contains('503'));
      expect(r.suggestions.length, _suggester.suggest(first).suggestions.length);
    });

    test('a second response that is not JSON cannot be compared', () {
      final r = _suggester.suggest(first, probe: response('<html></html>', headers: const {'Content-Type': 'application/json; charset=utf-8'}));
      expect(r.notes.single, contains('not JSON'));
      expect(r.volatile.map((v) => v.label), isNot(contains('body.queueDepth')));
    });

    test('a different content type in the second response drops that check', () {
      final r = _suggester.suggest(first, probe: response(ordersBody(), headers: const {'Content-Type': 'text/plain'}));
      expect(_ids(r).contains('content-type'), isFalse);
      expect(r.notes.join(' '), contains('Content-Type was different'));
    });
  });

  group('other shapes of response', () {
    test('a root array with 64-bit ids, mixed types and a decimal', () {
      final body = '[{"id":1234567890123456789,"score":1,"label":"a"},{"id":1234567890123456790,"score":2.5,"label":7}]';
      final r = _suggester.suggest(response(body));
      expect(_ids(r), ['status', 'content-type', 'time', 'schema', 'array:', 'shape:']);
      expect(_row(r, 'schema').label, 'body is an array whose elements have the shape seen here');
      expect(_row(r, 'array:').label, 'body is a non-empty array');
      expect(_row(r, 'array:').assertion.path, '');
      expect(_row(r, 'shape:').label, 'body elements have id, score, label');
      final schema = jsonDecode(_row(r, 'schema').assertion.expected) as Map<String, dynamic>;
      final props = (schema['items'] as Map)['properties'] as Map;
      expect((props['id'] as Map)['type'], 'integer');
      expect((props['score'] as Map)['type'], 'number');
      expect((props['label'] as Map)['type'], ['integer', 'string']);
      final results = const AssertionEvaluator().evaluate(response(body), [for (final s in r.suggestions) s.assertion]);
      expect(results.every((x) => x.passed), isTrue, reason: results.where((x) => !x.passed).map((x) => x.name).join(', '));
    });

    test('a scalar JSON body is described by its type', () {
      final r = _suggester.suggest(response('"ok"'));
      expect(_row(r, 'schema').label, 'body is a string');
      expect(jsonDecode(_row(r, 'schema').assertion.expected), {'type': 'string'});
    });

    test('an HTML body gets status, content type and time only, with a note', () {
      final r = _suggester.suggest(response('<html><body>hi</body></html>', headers: const {'Content-Type': 'text/html'}));
      expect(_ids(r), ['status', 'content-type', 'time']);
      expect(r.notes.single, contains('not JSON'));
    });

    test('an empty body (204) says so', () {
      final r = _suggester.suggest(response('', status: 204, headers: const {}));
      expect(_ids(r), ['status', 'time'], reason: 'no Content-Type header, no body');
      expect(r.notes.single, contains('empty'));
      expect(_row(r, 'status').label, 'status is 204');
    });

    test('a body cut off at the size limit gets no body checks', () {
      final r = _suggester.suggest(response('{"a":1,"b":[1,2,', truncated: true));
      expect(_ids(r), ['status', 'content-type', 'time']);
      expect(r.notes.single, contains('cut off'));
    });

    test('an error answer is proposed with a warning and only medium confidence', () {
      final r = _suggester.suggest(response({'error': 'not found'}, status: 404));
      final status = _row(r, 'status');
      expect(status.label, 'status is 404');
      expect(status.confidence, SuggestionConfidence.medium);
      expect(status.detail, contains('error'));
      expect(status.recommended, isTrue);
    });

    test('keys that are not plain words get quoted paths that still resolve', () {
      final body = {'a.b': 1, 'first name': 'Ann', 'ok': true};
      final r = _suggester.suggest(response(body));
      final results = const AssertionEvaluator().evaluate(response(body), [for (final s in r.suggestions) s.assertion]);
      expect(results.every((x) => x.passed), isTrue, reason: results.where((x) => !x.passed).map((x) => x.name).join(', '));
      expect(_ids(r), containsAll(['exists:["a.b"]', 'exists:["first name"]', 'equals:["first name"]']));
    });

    test('a huge body is analysed in part and says so, and the schema stays a manageable size', () {
      final items = [
        for (var i = 0; i < 700; i++) {'sku': 'S$i', 'qty': i, 'tags': ['a', 'b'], 'dims': {'w': 1.5, 'h': 2}},
      ];
      final r = _suggester.suggest(response({'items': items}));
      expect(r.notes.single, contains('analysed'));
      expect(jsonEncode(jsonDecode(_row(r, 'schema').assertion.expected)).length, lessThanOrEqualTo(TestSuggester.maxSchemaChars));
    });

    test('nested nulls and an optional nested object produce no exists check for a null', () {
      final body = {'user': {'name': 'Ann', 'deleted_at': null, 'address': null}};
      final r = _suggester.suggest(response(body));
      expect(_ids(r).where((id) => id.startsWith('exists:')), ['exists:user', 'exists:user.name']);
    });
  });

  group('adding suggestions to a request that has tests already', () {
    final result = _suggester.suggest(response(ordersBody()));

    test('what the request has is not added again, whatever the spelling', () {
      final existing = [
        AssertionEntity(type: AssertionType.statusEquals, expected: ' 200 '),
        AssertionEntity(type: AssertionType.headerEquals, path: 'content-type', expected: 'application/json; charset=utf-8'),
        AssertionEntity(type: AssertionType.jsonPathExists, path: r'$.data.page'),
        // The same schema with its keys in another order and spaced out.
        AssertionEntity(
          type: AssertionType.jsonSchema,
          path: 'data.orders',
          expected: '{ "minItems": 1, "type": "array" }',
        ),
      ];
      final fresh = AssertionDedupe.newOnly(existing, [for (final s in result.suggestions) s.assertion]);
      final all = result.suggestions.length;
      expect(fresh.length, all - 4);
      expect(fresh.any((a) => a.type == AssertionType.statusEquals), isFalse);
      expect(fresh.any((a) => a.type == AssertionType.headerEquals), isFalse);
      expect(fresh.any((a) => a.path == 'data.page' && a.type == AssertionType.jsonPathExists), isFalse);
      expect(fresh.any((a) => a.path == 'data.orders' && a.expected.contains('minItems')), isFalse);
    });

    test('two suggestions that say the same thing are added once', () {
      final a = AssertionEntity(type: AssertionType.jsonPathEquals, path: 'x', expected: '1');
      final b = AssertionEntity(type: AssertionType.jsonPathEquals, path: r'$.x', expected: '1');
      expect(AssertionDedupe.newOnly(const [], [a, b]), [a]);
    });

    test('a different expected value is a different check', () {
      final a = AssertionEntity(type: AssertionType.statusEquals, expected: '200');
      final b = AssertionEntity(type: AssertionType.statusEquals, expected: '201');
      expect(AssertionDedupe.same(a, b), isFalse);
      expect(AssertionDedupe.same(a, AssertionEntity(type: AssertionType.statusIn2xx)), isFalse);
    });

    test('the existing tests are never touched: newOnly returns only fresh ones', () {
      final existing = [AssertionEntity(type: AssertionType.statusEquals, expected: '200')];
      final fresh = AssertionDedupe.newOnly(existing, [AssertionEntity(type: AssertionType.statusEquals, expected: '200')]);
      expect(fresh, isEmpty);
      expect(existing.length, 1);
    });
  });
}
