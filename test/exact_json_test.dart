import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/utils/exact_json.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';
import 'package:postpilot/features/scripting/domain/evaluator/extractor_value_resolver.dart';
import 'package:postpilot/features/scripting/domain/evaluator/response_reader.dart';

ApiResponseEntity _response(String body, {Map<String, String> headers = const {}, List<String> setCookies = const []}) =>
    ApiResponseEntity(
      statusCode: 200,
      statusMessage: 'OK',
      headers: headers,
      bodyBytes: Uint8List.fromList(utf8.encode(body)),
      duration: Duration.zero,
      setCookies: setCookies,
    );

void main() {
  group('ExactJson.decodeIfLarge', () {
    Object? decode(String text, {bool web = true}) => ExactJson.decodeIfLarge(text, web: web);

    test('is null when no number is long enough to matter, and for text that is not JSON', () {
      expect(decode('{"id": 12345, "price": 1.5}'), isNull);
      expect(decode('not json'), isNull);
      expect(decode('{"id": 1234567890123456789'), isNull, reason: 'truncated JSON');
    });

    test('on the web an integer past 2^53 becomes a BigInt, as written', () {
      final json = decode('{"id": 1234567890123456789, "list": [-1234567890123456789, 5], "n": {"deep": 9007199254740993}}')!
          as Map<String, dynamic>;

      expect(json['id'], BigInt.parse('1234567890123456789'));
      expect(json['list'], [BigInt.parse('-1234567890123456789'), 5]);
      expect((json['n'] as Map)['deep'], BigInt.parse('9007199254740993'));
    });

    test('2^53 itself is exact on the web and left alone, 2^53 + 1 is not', () {
      expect(decode('{"a": 9007199254740992}'), isNull);
      expect(decode('{"a": -9007199254740992}'), isNull);
      expect((decode('{"a": 9007199254740993}')! as Map)['a'], BigInt.parse('9007199254740993'));
    });

    test('off the web the 64-bit range is exact, and only what is past it becomes a BigInt', () {
      expect(decode('{"a": 9223372036854775807}', web: false), isNull);
      expect(decode('{"a": -9223372036854775808}', web: false), isNull);
      expect((decode('{"a": 9223372036854775808}', web: false)! as Map)['a'], BigInt.parse('9223372036854775808'));
      expect((decode('{"a": -9223372036854775809}', web: false)! as Map)['a'], BigInt.parse('-9223372036854775809'));
    });

    test('a long run of digits inside a string is text and stays text', () {
      expect(decode('{"s": "1234567890123456789"}'), isNull);

      final json = decode(r'{"q": "a\"1234567890123456789\" b", "id": 1234567890123456789}')! as Map;

      expect(json['q'], 'a"1234567890123456789" b');
      expect(json['id'], BigInt.parse('1234567890123456789'));
    });

    test('a float literal is left to the ordinary decoder', () {
      expect(decode('{"f": 1234567890123456789.5, "e": 1234567890123456789e3}'), isNull);
    });

    test('every other value comes back as the ordinary decoder gives it', () {
      const text = '{"id": 1234567890123456789, "s": "x", "b": true, "n": null, "f": 1.5, "list": [1, "2", {"k": 3}]}';

      final exact = decode(text)! as Map<String, dynamic>;
      final plain = jsonDecode(text) as Map<String, dynamic>;

      for (final key in ['s', 'b', 'n', 'f', 'list']) {
        expect(exact[key], plain[key], reason: key);
      }
    });

    test(r'a document that holds the escape \u0000 is not touched: its marker could be forged', () {
      expect(decode(r'{"a": "\u0000bigint:5", "id": 1234567890123456789}'), isNull);
    });
  });

  group('ResponseReader and integers a number cannot hold', () {
    const body = '{"id": 1234567890123456789, "items": [{"id": 9007199254740993}], "obj": {"n": 1234567890123456789}, "small": 42}';

    test('on the web an id that ends a path is read as written, not rounded', () {
      final reader = ResponseReader(_response(body), web: true);

      expect(reader.jsonPath('id'), BigInt.parse('1234567890123456789'));
      expect(reader.jsonPath(r'$.items[0].id'), BigInt.parse('9007199254740993'));
      expect(ResponseReader.stringify(reader.jsonPath('id')), '1234567890123456789');
      expect(ResponseReader.stringify(reader.jsonPath('items[0].id')), '9007199254740993');
      expect(reader.jsonPath('small'), 42);
    });

    test('off the web 64-bit integers were always exact, so nothing changes for them', () {
      final reader = ResponseReader(_response(body), web: false);

      expect(reader.jsonPath('id'), 1234567890123456789);
      expect(ResponseReader.stringify(reader.jsonPath('id')), '1234567890123456789');
    });

    test('off the web an integer past 64 bits is exact too', () {
      final reader = ResponseReader(_response('{"id": 12345678901234567890123}'), web: false);

      expect(ResponseReader.stringify(reader.jsonPath('id')), '12345678901234567890123');
    });

    test('an object or array result keeps plain numbers, which schema checks and comparisons are written for', () {
      final reader = ResponseReader(_response(body), web: true);

      final obj = reader.jsonPath('obj')! as Map;

      expect(obj['n'], isA<num>());
      expect(reader.jsonPath('items'), isA<List<dynamic>>());
    });

    test('a missing path and a body that is not JSON still read as null', () {
      expect(ResponseReader(_response(body), web: true).jsonPath('nope'), isNull);
      final text = ResponseReader(_response('plain text 1234567890123456789'), web: true);
      expect(text.isJson, isFalse);
      expect(text.jsonPath('id'), isNull);
    });

    test('an extractor saves the exact id', () {
      final reader = ResponseReader(_response(body), web: true);

      final value = ExtractorValueResolver.resolve(reader, ExtractorEntity(path: 'id', variableKey: 'userId'));

      expect(value, '1234567890123456789');
    });

    test('stringify prints a BigInt as digits, inside a container too', () {
      expect(ResponseReader.stringify(BigInt.parse('-1234567890123456789')), '-1234567890123456789');
      expect(ResponseReader.stringify(42), '42');
      expect(ResponseReader.stringify(1.5), '1.5');
    });
  });

  group('Set-Cookie through the reader', () {
    final cookies = [
      'sid=abc123; Path=/; HttpOnly',
      'theme=dark; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/',
      'sid=second; Path=/other',
    ];

    test('Set-Cookie[name] reads the value of one cookie, the first when it is set twice', () {
      final reader = ResponseReader(_response('{}', setCookies: cookies));

      expect(reader.header('Set-Cookie[sid]'), 'abc123');
      expect(reader.header('set-cookie[theme]'), 'dark');
      expect(reader.header(' Set-Cookie [ theme ] '), 'dark');
      expect(reader.header('Set-Cookie[missing]'), isNull);
    });

    test('the plain header still reads as one joined value, for the assertions that use it', () {
      final reader = ResponseReader(_response('{}', headers: {'set-cookie': cookies.join(', ')}, setCookies: cookies));

      expect(reader.header('Set-Cookie'), cookies.join(', '));
    });

    test('a response that only kept the joined header still gives its cookies apart', () {
      final reader = ResponseReader(_response('{}', headers: {'set-cookie': cookies.join(', ')}));

      expect(reader.setCookies, cookies);
      expect(reader.header('Set-Cookie[theme]'), 'dark');
    });

    test('a response with no cookies reads null, and so does an empty name', () {
      final reader = ResponseReader(_response('{}'));

      expect(reader.setCookies, isEmpty);
      expect(reader.header('Set-Cookie[sid]'), isNull);
      expect(ResponseReader(_response('{}', setCookies: cookies)).header('Set-Cookie[ ]'), isNull);
    });

    test('an extractor on a header path takes one cookie by name', () {
      final reader = ResponseReader(_response('{}', setCookies: cookies));

      final value = ExtractorValueResolver.resolve(
        reader,
        ExtractorEntity(source: ExtractorSource.header, path: 'Set-Cookie[sid]', variableKey: 'session'),
      );

      expect(value, 'abc123');
    });
  });
}
