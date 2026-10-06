// ignore_for_file: depend_on_referenced_packages
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/dart_codegen/domain/services/dart_model_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/dart_names.dart';

void _expectParses(String code) {
  final parsed = parseString(content: code, throwIfDiagnostics: false);
  expect(parsed.errors, isEmpty, reason: '${parsed.errors.map((e) => e.message).join('; ')}\n$code');
}

void main() {
  const gen = DartModelGenerator();

  group('map-like objects', () {
    // Six numeric keys: a lookup table, not a record, so it becomes Map<String, V>.
    const sample = '''
{"byId": {
  "1001": {"name": "a", "age": 3},
  "1002": {"name": "b"},
  "1003": {"name": "c", "nick": "x", "meta": {"p": 1}},
  "1004": {"name": "d", "meta": {"q": "two"}},
  "1005": {"name": "e"},
  "1006": {"name": "f", "age": 9}
}}''';

    test('the value class is the merge of every entry; fields only some have are optional', () {
      final r = gen.generate([sample], rootName: 'Table');
      expect(r.code, contains('final Map<String, ByIdValue> byId;'));
      final value = r.code.substring(r.code.indexOf('class ByIdValue'));
      // `name` is in all six entries, the rest in some: reading an entry without them must not throw.
      expect(value, contains('final String name;'));
      expect(value, contains('final int? age;'));
      expect(value, contains('final String? nick;'));
      expect(value, contains('final Meta? meta;'));
      // Nested objects merge too: `meta` has `p` in one entry and `q` in another.
      final meta = r.code.substring(r.code.indexOf('class Meta'));
      expect(meta, contains('final int? p;'));
      expect(meta, contains('final String? q;'));
      _expectParses(r.code);
    });

    test('with everything optional, nothing is required either way', () {
      final r = gen.generate([sample], rootName: 'Table', options: const DartModelOptions(allNullable: true));
      expect(r.code, isNot(contains('required this')));
      _expectParses(r.code);
    });

    test('a field present in every entry stays required', () {
      const same = '{"m": {"1001": {"a": 1}, "1002": {"a": 2}, "1003": {"a": 3}, "1004": {"a": 4}, "1005": {"a": 5}, "1006": {"a": 6}}}';
      final r = gen.generate([same], rootName: 'T');
      expect(r.code, contains('final int a;'));
    });

    test('entries whose values are lists of different objects merge their items', () {
      const lists = '{"m": {"1001": [{"a": 1}], "1002": [{"b": "x"}], "1003": [], "1004": [{"a": 2}], "1005": [{"b": "y"}], "1006": [{"a": 3}]}}';
      final r = gen.generate([lists], rootName: 'T');
      expect(r.code, contains('final Map<String, List<MValue>> m;'));
      final item = r.code.substring(r.code.indexOf('class MValue'));
      expect(item, contains('final int? a;'));
      expect(item, contains('final String? b;'));
      _expectParses(r.code);
    });
  });

  group('names that collide with core types', () {
    const keys = '{"string":{"a":1},"list":{"b":2},"map":{"c":3},"dateTime":{"d":4},"object":{"e":5},'
        '"int":{"f":6},"bool":{"g":7},"set":{"h":8},"error":{"i":9},"type":{"j":1},"function":{"k":2}}';

    for (final style in DartModelStyle.values) {
      test('an object under such a key gets a safe class name (${style.name})', () {
        final r = gen.generate([keys], rootName: 'Root', options: DartModelOptions(style: style));
        for (final core in ['String', 'List', 'Map', 'DateTime', 'Object', 'Set', 'Error', 'Type', 'Function']) {
          expect(r.code, isNot(contains('class $core ')), reason: '$core must stay the core type');
          expect(r.code, contains('class ${core}Model'), reason: core);
        }
        expect(r.code, contains('Int'));
        _expectParses(r.code);
      });
    }

    test('plain output refers to the renamed classes and avoids fields named like types', () {
      final r = gen.generate([keys], rootName: 'Root');
      expect(r.code, contains('final StringModel string;'));
      expect(r.code, contains('final ListModel list;'));
      expect(r.code, contains('final DateTimeModel dateTime;'));
      expect(r.code, contains('final Int intValue;'));
      expect(r.code, contains('final Bool boolValue;'));
      expect(r.code, contains('intValue: Int.fromJson(json[\'int\'] as Map<String, dynamic>)'));
      expect(r.code, contains("'int': intValue.toJson()"));
      // Every nested class still has its own fromJson/toJson.
      expect('class '.allMatches(r.code).length, r.classCount);
    });

    test('a root class named like a core type is renamed too', () {
      final r = gen.generate(['{"a":1}'], rootName: 'List');
      expect(r.code, contains('class ListModel'));
      expect(r.code, isNot(contains('class List ')));
      _expectParses(r.code);
    });

    test('class names of the packages the file imports are avoided', () {
      final plain = gen.generate(['{"options":{"a":1}}'], rootName: 'Root');
      expect(plain.code, contains('class Options'), reason: 'only a caller that imports Dio asks for it to be avoided');
      final avoided = gen.generate(['{"options":{"a":1}}'], rootName: 'Root', options: const DartModelOptions(avoidClassNames: {'Options'}));
      expect(avoided.code, contains('class OptionsModel'));
      expect(avoided.code, isNot(contains('class Options ')));
      final freezed = gen.generate(['{"jsonKey":{"a":1},"freezed":{"b":1}}'], rootName: 'Root', options: const DartModelOptions(style: DartModelStyle.freezed));
      expect(freezed.code, contains('class JsonKeyModel'));
      expect(freezed.code, contains('class FreezedModel'));
    });

    test('a field called toJson, fromJson or copyWith does not collide with the generated members', () {
      final r = gen.generate(['{"toJson":1,"fromJson":2,"copyWith":3,"hashCode":4}'], rootName: 'Root', options: const DartModelOptions(allNullable: true));
      expect(r.code, contains('toJsonValue'));
      expect(r.code, contains('fromJsonValue'));
      expect(r.code, contains('copyWithValue'));
      expect(r.code, contains('hashCodeValue'));
      _expectParses(r.code);
    });
  });

  group('DartNames', () {
    test('className avoids core types and extra names only', () {
      expect(DartNames.className('string'), 'StringModel');
      expect(DartNames.className('date_time'), 'DateTimeModel');
      expect(DartNames.className('user_profile'), 'UserProfile');
      expect(DartNames.className('int'), 'Int');
      expect(DartNames.className('options'), 'Options');
      expect(DartNames.className('options', also: const {'Options'}), 'OptionsModel');
      expect(DartNames.className('', fallback: 'Root'), 'Root');
    });

    test('camel avoids words that would hide a type or clash with a generated member', () {
      for (final word in ['int', 'double', 'num', 'bool', 'dynamic', 'toJson', 'fromJson', 'copyWith', 'class', 'hashCode']) {
        expect(DartNames.camel(word), '${word}Value', reason: word);
      }
      expect(DartNames.camel('string'), 'string');
      expect(DartNames.camel('first name'), 'firstName');
    });

    test('quote escapes everything that ends or interpolates a string', () {
      expect(DartNames.quote("it's \$x \\ \n\r end"), r"'it\'s \$x \\ \n\r end'");
      expect(DartNames.escape(r'/odata/$metadata'), r'/odata/\$metadata');
    });
  });
}
