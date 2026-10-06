import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/auth_type.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/defaults/domain/services/defaults_codec.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/scripting/domain/entities/extractor_entity.dart';

void main() {
  group('columns', () {
    test('headers are written as a versioned object and read back with their enabled flag', () {
      final json = DefaultsCodec.encodeHeaders([
        KeyValueItem(key: 'X-Api-Version', value: '2'),
        KeyValueItem(key: 'X-Off', value: '', enabled: false),
      ]);
      expect(jsonDecode(json), {
        'v': 1,
        'items': [
          {'key': 'X-Api-Version', 'value': '2', 'enabled': true},
          {'key': 'X-Off', 'value': '', 'enabled': false},
        ],
      });
      final back = DefaultsCodec.decodeHeaders(json);
      expect([for (final h in back) (h.key, h.value, h.enabled)], [('X-Api-Version', '2', true), ('X-Off', '', false)]);
    });

    test('the bare list a column defaults to reads like the object, an enabled flag defaults to on', () {
      final rows = DefaultsCodec.decodeHeaders('[{"key":"A","value":"1"}]');
      expect([for (final h in rows) (h.key, h.value, h.enabled)], [('A', '1', true)]);
      expect(DefaultsCodec.decodeHeaders('[]'), isEmpty);
    });

    test('a column that is missing, empty, damaged or of another shape is an empty level, never an error', () {
      for (final damaged in [null, '', '   ', 'not json', '{"v":1}', '{"items":"x"}', '42', 'null', '[1,"a",null]']) {
        expect(DefaultsCodec.decodeHeaders(damaged), isEmpty, reason: '$damaged');
        expect(DefaultsCodec.decodeVariables(damaged), isEmpty, reason: '$damaged');
        expect(DefaultsCodec.decodeAuth(damaged), isNull, reason: '$damaged');
        expect(DefaultsCodec.decodeScripts(damaged).assertions, isEmpty, reason: '$damaged');
        expect(DefaultsCodec.decodeScripts(damaged).extractors, isEmpty, reason: '$damaged');
      }
    });

    test('items of the wrong shape are skipped, the good ones around them are kept', () {
      final rows = DefaultsCodec.decodeHeaders('{"v":1,"items":[7,{"value":"no key"},{"key":"Ok","value":"1"},"x"]}');
      expect(rows.map((h) => h.key), ['Ok']);
    });

    test('a newer version is read as far as it matches', () {
      final rows = DefaultsCodec.decodeHeaders('{"v":9,"items":[{"key":"A","value":"1","future":true}],"extra":1}');
      expect(rows.single.key, 'A');
    });

    test('variables keep their secret flag and write it only when set', () {
      final json = DefaultsCodec.encodeVariables([
        DefaultVariable(key: 'plain', value: 'a'),
        DefaultVariable(key: 'token', value: 'b', isSecret: true),
        DefaultVariable(key: 'off', value: 'c', enabled: false),
      ]);
      final items = (jsonDecode(json) as Map)['items'] as List;
      expect(items[0], {'key': 'plain', 'value': 'a', 'enabled': true});
      expect(items[1], {'key': 'token', 'value': 'b', 'secret': true, 'enabled': true});
      expect(DefaultsCodec.decodeVariables(json), [
        DefaultVariable(key: 'plain', value: 'a'),
        DefaultVariable(key: 'token', value: 'b', isSecret: true),
        DefaultVariable(key: 'off', value: 'c', enabled: false),
      ]);
    });

    test('auth: an unset auth is {}, "inherit" is unset too, any other type round-trips', () {
      expect(DefaultsCodec.encodeAuth(null), '{}');
      expect(DefaultsCodec.encodeAuth(const RequestAuth(type: AuthType.inherit)), '{}');
      expect(DefaultsCodec.decodeAuth('{}'), isNull);
      expect(DefaultsCodec.decodeAuth('{"type":"inherit"}'), isNull);

      const bearer = RequestAuth(type: AuthType.bearer, bearerToken: 'abc');
      final back = DefaultsCodec.decodeAuth(DefaultsCodec.encodeAuth(bearer))!;
      expect(back.type, AuthType.bearer);
      expect(back.bearerToken, 'abc');

      final none = DefaultsCodec.decodeAuth(DefaultsCodec.encodeAuth(const RequestAuth(type: AuthType.none)));
      expect(none?.type, AuthType.none, reason: 'No Auth on a folder is a setting, not "unset"');
    });

    test('tests keep the item shapes the request tests have', () {
      final json = DefaultsCodec.encodeScripts(
        [AssertionEntity(type: AssertionType.statusEquals, expected: '200'), AssertionEntity(type: AssertionType.jsonPathExists, path: r'$.id')],
        [ExtractorEntity(path: r'$.token', variableKey: 'sessionToken', scope: ExtractorScope.global)],
      );
      final map = jsonDecode(json) as Map;
      expect(map['v'], 1);
      expect(map['assertions'], [
        {'type': 'statusEquals', 'path': '', 'expected': '200'},
        {'type': 'jsonPathExists', 'path': r'$.id', 'expected': ''},
      ]);
      final back = DefaultsCodec.decodeScripts(json);
      expect(back.assertions.map((a) => a.type), [AssertionType.statusEquals, AssertionType.jsonPathExists]);
      expect(back.extractors.single.variableKey, 'sessionToken');
      expect(back.extractors.single.scope, ExtractorScope.global);
    });
  });

  group('documents', () {
    test('a level that sets nothing writes no keys', () {
      expect(DefaultsCodec.toDoc(LevelDefaults.empty), isEmpty);
    });

    test('a folder writes headers, variables, auth and tests under the keys the Git docs and the backup use', () {
      final doc = DefaultsCodec.toDoc(LevelDefaults(
        headers: [KeyValueItem(key: 'X-A', value: '1')],
        variables: [DefaultVariable(key: 'v', value: '2', isSecret: true)],
        auth: const RequestAuth(type: AuthType.bearer, bearerToken: 't'),
        assertions: [AssertionEntity(type: AssertionType.statusIn2xx)],
      ));
      expect(doc.keys.toSet(), {'headers', 'variables', 'auth', 'tests'});
      expect(doc['headers'], [
        {'key': 'X-A', 'value': '1', 'enabled': true},
      ]);
      expect((doc['auth'] as Map)['type'], 'bearer');
      expect((doc['tests'] as Map).keys.toSet(), {'assertions', 'extractors'});

      final back = DefaultsCodec.fromDoc(doc);
      expect(back.headers.single.key, 'X-A');
      expect(back.variables.single, DefaultVariable(key: 'v', value: '2', isSecret: true));
      expect(back.auth?.bearerToken, 't');
      expect(back.assertions.single.type, AssertionType.statusIn2xx);
    });

    test('a collection leaves its own variables and auth out: they have their own keys in its document', () {
      final doc = DefaultsCodec.toDoc(
        LevelDefaults(
          headers: [KeyValueItem(key: 'X-A', value: '1')],
          variables: [DefaultVariable(key: 'v')],
          auth: const RequestAuth(type: AuthType.bearer),
        ),
        includeVariablesAndAuth: false,
      );
      expect(doc.keys, ['headers']);

      final read = DefaultsCodec.fromDoc({
        'headers': doc['headers'],
        'variables': [
          {'key': 'collection-variable', 'value': 'x'},
        ],
        'auth': {'type': 'bearer'},
      }, includeVariablesAndAuth: false);
      expect(read.variables, isEmpty);
      expect(read.auth, isNull);
      expect(read.headers.single.key, 'X-A');
    });

    test('a document with none of the keys is an empty level', () {
      expect(DefaultsCodec.fromDoc({'name': 'x', 'description': 'd'}).isEmpty, isTrue);
    });
  });
}
