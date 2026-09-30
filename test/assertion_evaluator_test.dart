import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/scripting/data/models/scripts_json_codec.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/scripting/domain/evaluator/assertion_evaluator.dart';
import 'package:postpilot/features/scripting/domain/evaluator/extractor_value_resolver.dart';
import 'package:postpilot/features/scripting/domain/evaluator/json_path_resolver.dart';
import 'package:postpilot/features/scripting/domain/evaluator/response_reader.dart';

ApiResponseEntity _response({
  int status = 200,
  String body = '',
  Map<String, String> headers = const {},
  int ms = 50,
}) =>
    ApiResponseEntity(
      statusCode: status,
      statusMessage: '',
      headers: headers,
      bodyBytes: Uint8List.fromList(utf8.encode(body)),
      duration: Duration(milliseconds: ms),
    );

void main() {
  group('JsonPathResolver', () {
    final json = jsonDecode('{"data":{"items":[{"id":7,"tags":["a","b"]},{"id":8}],"a.b":1,"nil":null},"ok":true}');

    test('walks dot and bracket segments', () {
      expect(JsonPathResolver.resolve(json, 'data.items[0].id'), 7);
      expect(JsonPathResolver.resolve(json, 'data.items[1].id'), 8);
      expect(JsonPathResolver.resolve(json, 'data.items[0].tags[1]'), 'b');
      expect(JsonPathResolver.resolve(json, 'ok'), true);
    });

    test('accepts numeric dot segments and a leading \$', () {
      expect(JsonPathResolver.resolve(json, 'data.items.0.id'), 7);
      expect(JsonPathResolver.resolve(json, r'$.data.items[0].id'), 7);
      expect(JsonPathResolver.resolve(json, r'$'), json);
      expect(JsonPathResolver.resolve(json, ''), json);
    });

    test('quoted bracket keys may contain dots', () {
      expect(JsonPathResolver.resolve(json, 'data["a.b"]'), 1);
      expect(JsonPathResolver.resolve(json, "data['a.b']"), 1);
    });

    test('returns null for missing keys, bad indexes and scalars', () {
      expect(JsonPathResolver.resolve(json, 'data.missing'), isNull);
      expect(JsonPathResolver.resolve(json, 'data.items[5].id'), isNull);
      expect(JsonPathResolver.resolve(json, 'data.items[-1]'), isNull);
      expect(JsonPathResolver.resolve(json, 'data.items.x'), isNull);
      expect(JsonPathResolver.resolve(json, 'ok.deeper'), isNull);
      expect(JsonPathResolver.resolve(json, 'data.nil'), isNull);
    });
  });

  group('AssertionEvaluator', () {
    const evaluator = AssertionEvaluator();
    final response = _response(
      status: 201,
      body: '{"data":{"id":42,"name":"Ada","nested":{"x":1}},"list":[1,2]}',
      headers: const {'Content-Type': 'application/json', 'X-Request-Id': 'abc'},
      ms: 120,
    );

    List<AssertionEntity> one(AssertionType type, {String path = '', String expected = ''}) =>
        [AssertionEntity(type: type, path: path, expected: expected)];

    test('statusEquals compares the code and reports the actual one', () {
      final pass = evaluator.evaluate(response, one(AssertionType.statusEquals, expected: '201')).single;
      final fail = evaluator.evaluate(response, one(AssertionType.statusEquals, expected: '200')).single;
      expect(pass.passed, isTrue);
      expect(fail.passed, isFalse);
      expect(fail.actual, '201');
      expect(fail.name, 'Status equals 200');
    });

    test('statusIn2xx', () {
      expect(evaluator.evaluate(response, one(AssertionType.statusIn2xx)).single.passed, isTrue);
      expect(evaluator.evaluate(_response(status: 404), one(AssertionType.statusIn2xx)).single.passed, isFalse);
    });

    test('bodyContains searches the raw body text', () {
      expect(evaluator.evaluate(response, one(AssertionType.bodyContains, expected: '"Ada"')).single.passed, isTrue);
      expect(evaluator.evaluate(response, one(AssertionType.bodyContains, expected: 'Grace')).single.passed, isFalse);
      expect(evaluator.evaluate(response, one(AssertionType.bodyContains, expected: '')).single.passed, isFalse);
    });

    test('jsonPathEquals compares scalars as text and containers as JSON', () {
      expect(evaluator.evaluate(response, one(AssertionType.jsonPathEquals, path: 'data.id', expected: '42')).single.passed, isTrue);
      expect(evaluator.evaluate(response, one(AssertionType.jsonPathEquals, path: 'data.name', expected: 'Ada')).single.passed, isTrue);
      expect(evaluator.evaluate(response, one(AssertionType.jsonPathEquals, path: 'data.nested', expected: '{"x":1}')).single.passed, isTrue);

      final fail = evaluator.evaluate(response, one(AssertionType.jsonPathEquals, path: 'data.id', expected: '43')).single;
      expect(fail.passed, isFalse);
      expect(fail.actual, '42');
    });

    test('jsonPath assertions fail cleanly on a non-JSON body', () {
      final html = _response(body: '<html></html>');
      final result = evaluator.evaluate(html, one(AssertionType.jsonPathEquals, path: 'a', expected: '1')).single;
      expect(result.passed, isFalse);
      expect(result.actual, 'Body is not valid JSON');
      expect(evaluator.evaluate(html, one(AssertionType.jsonPathExists, path: 'a')).single.passed, isFalse);
    });

    test('jsonPathExists', () {
      expect(evaluator.evaluate(response, one(AssertionType.jsonPathExists, path: 'data.name')).single.passed, isTrue);
      expect(evaluator.evaluate(response, one(AssertionType.jsonPathExists, path: 'list[1]')).single.passed, isTrue);
      final missing = evaluator.evaluate(response, one(AssertionType.jsonPathExists, path: 'data.email')).single;
      expect(missing.passed, isFalse);
      expect(missing.actual, 'Missing');
    });

    test('headerEquals and headerExists match header names case-insensitively', () {
      expect(
        evaluator.evaluate(response, one(AssertionType.headerEquals, path: 'content-type', expected: 'application/json')).single.passed,
        isTrue,
      );
      final wrong = evaluator.evaluate(response, one(AssertionType.headerEquals, path: 'Content-Type', expected: 'text/html')).single;
      expect(wrong.passed, isFalse);
      expect(wrong.actual, 'application/json');

      expect(evaluator.evaluate(response, one(AssertionType.headerExists, path: 'x-request-id')).single.passed, isTrue);
      final absent = evaluator.evaluate(response, one(AssertionType.headerExists, path: 'ETag')).single;
      expect(absent.passed, isFalse);
      expect(absent.actual, 'Missing');
    });

    test('responseTimeBelowMs', () {
      expect(evaluator.evaluate(response, one(AssertionType.responseTimeBelowMs, expected: '500')).single.passed, isTrue);
      final slow = evaluator.evaluate(response, one(AssertionType.responseTimeBelowMs, expected: '100')).single;
      expect(slow.passed, isFalse);
      expect(slow.actual, '120 ms');
      expect(evaluator.evaluate(response, one(AssertionType.responseTimeBelowMs, expected: 'fast')).single.passed, isFalse);
    });

    test('evaluates every assertion in order', () {
      final results = evaluator.evaluate(response, [
        AssertionEntity(type: AssertionType.statusIn2xx),
        AssertionEntity(type: AssertionType.statusEquals, expected: '500'),
        AssertionEntity(type: AssertionType.headerExists, path: 'X-Request-Id'),
      ]);
      expect(results.map((r) => r.passed), [true, false, true]);
    });

    test('resolves {{variables}} in expected values, JSON paths and header names', () {
      final resolver = VariableResolver({'userId': '42', 'field': 'id', 'header': 'x-request-id', 'name': 'Ada'});
      bool passes(AssertionType type, {String path = '', String expected = ''}) =>
          evaluator.evaluate(response, one(type, path: path, expected: expected), resolver).single.passed;

      expect(passes(AssertionType.jsonPathEquals, path: 'data.id', expected: '{{userId}}'), isTrue);
      expect(passes(AssertionType.jsonPathEquals, path: 'data.{{field}}', expected: '42'), isTrue);
      expect(passes(AssertionType.headerExists, path: '{{header}}'), isTrue);
      expect(passes(AssertionType.headerEquals, path: '{{header}}', expected: 'abc'), isTrue);
      expect(passes(AssertionType.bodyContains, expected: '"{{name}}"'), isTrue);
      expect(passes(AssertionType.statusEquals, expected: '{{userId}}'), isFalse);
    });

    test('a result is named after the resolved values; unresolved tokens stay literal and fail', () {
      final resolver = VariableResolver({'userId': '43'});
      final stale =
          evaluator.evaluate(response, one(AssertionType.jsonPathEquals, path: 'data.id', expected: '{{userId}}'), resolver).single;
      expect(stale.passed, isFalse);
      expect(stale.actual, '42');
      expect(stale.name, 'data.id equals 43');

      final missing = evaluator.evaluate(response, one(AssertionType.jsonPathEquals, path: 'data.id', expected: '{{nope}}')).single;
      expect(missing.passed, isFalse);
      expect(missing.name, 'data.id equals {{nope}}');
    });

    test('JSON path assertions with a blank path fail instead of matching the whole body', () {
      for (final type in [AssertionType.jsonPathExists, AssertionType.jsonPathEquals]) {
        final blank = evaluator.evaluate(response, one(type, path: '  ', expected: '{"x":1}')).single;
        expect(blank.passed, isFalse, reason: type.name);
        expect(blank.actual, 'Enter a JSON path', reason: type.name);
      }
      expect(evaluator.evaluate(response, one(AssertionType.jsonPathExists, path: r'$')).single.passed, isTrue);
    });

    test('jsonPathEquals treats a whole-number double like the integer', () {
      final prices = _response(body: '{"total":100.0,"ratio":0.5}');
      bool passes(String path, String expected) =>
          evaluator.evaluate(prices, one(AssertionType.jsonPathEquals, path: path, expected: expected)).single.passed;

      expect(passes('total', '100'), isTrue);
      expect(passes('total', '101'), isFalse);
      expect(passes('ratio', '0.5'), isTrue);
    });

    test('jsonPathEquals compares containers structurally', () {
      bool passes(String path, String expected) =>
          evaluator.evaluate(response, one(AssertionType.jsonPathEquals, path: path, expected: expected)).single.passed;

      expect(passes('list', '[1, 2]'), isTrue);
      expect(passes('list', '[2, 1]'), isFalse);
      expect(passes('data.nested', '{ "x": 1 }'), isTrue);
      expect(passes('data.nested', '{"x":2}'), isFalse);
      expect(passes('data', '{"nested":{"x":1},"name":"Ada","id":42}'), isTrue);
      expect(passes('list', 'not json'), isFalse);
    });
  });

  group('ResponseReader.stringify', () {
    test('prints whole-number doubles without a fraction, like the web build', () {
      expect(ResponseReader.stringify(100.0), '100');
      expect(ResponseReader.stringify(-3.0), '-3');
      expect(ResponseReader.stringify(2.5), '2.5');
      expect(ResponseReader.stringify(7), '7');
      expect(ResponseReader.stringify(true), 'true');
      expect(ResponseReader.stringify(null), 'null');
      expect(ResponseReader.stringify('text'), 'text');
    });
  });

  group('ExtractorValueResolver', () {
    final reader = ResponseReader(_response(
      body: '{"token":"t-123","user":{"id":9},"roles":["admin"]}',
      headers: const {'Set-Cookie': 'session=xyz'},
    ));

    test('reads JSON paths as text', () {
      expect(ExtractorValueResolver.resolve(reader, ExtractorEntity(path: 'token', variableKey: 'k')), 't-123');
      expect(ExtractorValueResolver.resolve(reader, ExtractorEntity(path: 'user.id', variableKey: 'k')), '9');
      expect(ExtractorValueResolver.resolve(reader, ExtractorEntity(path: 'roles', variableKey: 'k')), '["admin"]');
    });

    test('reads headers case-insensitively', () {
      final extractor = ExtractorEntity(source: ExtractorSource.header, path: 'set-cookie', variableKey: 'k');
      expect(ExtractorValueResolver.resolve(reader, extractor), 'session=xyz');
    });

    test('returns null when nothing matches', () {
      expect(ExtractorValueResolver.resolve(reader, ExtractorEntity(path: 'nope', variableKey: 'k')), isNull);
      final header = ExtractorEntity(source: ExtractorSource.header, path: 'X-Missing', variableKey: 'k');
      expect(ExtractorValueResolver.resolve(reader, header), isNull);
    });

    test('whole-number doubles come out as integers', () {
      final paged = ResponseReader(_response(body: '{"page":2.0,"score":9.5}'));
      expect(ExtractorValueResolver.resolve(paged, ExtractorEntity(path: 'page', variableKey: 'k')), '2');
      expect(ExtractorValueResolver.resolve(paged, ExtractorEntity(path: 'score', variableKey: 'k')), '9.5');
    });
  });

  group('ExtractorEntity', () {
    test('keyError accepts every name the resolver can substitute', () {
      for (final key in ['token', 'access-token', 'user.id', r'$region', 'a_1', '  token  ']) {
        expect(ExtractorEntity(variableKey: key).keyError, isNull, reason: key);
      }
    });

    test('keyError rejects a blank name and names the resolver could never match', () {
      expect(ExtractorEntity().keyError, 'No variable name');
      for (final key in ['access token', 'a/b', 'a}}{{b', 'tok{en']) {
        expect(ExtractorEntity(variableKey: key).keyError, isNotNull, reason: key);
      }
    });

    test('pathError flags a blank path for either source', () {
      expect(ExtractorEntity(path: 'data.id').pathError, isNull);
      expect(ExtractorEntity(path: ' ').pathError, 'Enter a JSON path');
      expect(ExtractorEntity(source: ExtractorSource.header).pathError, 'Enter a header name');
    });
  });

  group('ScriptsJsonCodec', () {
    test('round-trips assertions and extractors', () {
      final assertions = ScriptsJsonCodec.decodeAssertions(ScriptsJsonCodec.encodeAssertions([
        AssertionEntity(type: AssertionType.jsonPathEquals, path: 'a.b', expected: '1'),
        AssertionEntity(type: AssertionType.statusIn2xx),
      ]));
      expect(assertions.length, 2);
      expect(assertions.first.type, AssertionType.jsonPathEquals);
      expect(assertions.first.path, 'a.b');
      expect(assertions.first.expected, '1');
      expect(assertions.last.type, AssertionType.statusIn2xx);

      final extractors = ScriptsJsonCodec.decodeExtractors(ScriptsJsonCodec.encodeExtractors([
        ExtractorEntity(source: ExtractorSource.header, path: 'ETag', scope: ExtractorScope.global, variableKey: 'etag'),
      ]));
      expect(extractors.single.source, ExtractorSource.header);
      expect(extractors.single.path, 'ETag');
      expect(extractors.single.scope, ExtractorScope.global);
      expect(extractors.single.variableKey, 'etag');
    });

    test('tolerates corrupt or foreign JSON', () {
      expect(ScriptsJsonCodec.decodeAssertions('not json'), isEmpty);
      expect(ScriptsJsonCodec.decodeAssertions('{"a":1}'), isEmpty);
      expect(ScriptsJsonCodec.decodeExtractors('[1, "x"]'), isEmpty);
      expect(ScriptsJsonCodec.decodeAssertions('[{"type":"unknown"}]').single.type, AssertionType.statusIn2xx);
    });
  });
}
