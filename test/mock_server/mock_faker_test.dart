import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_faker.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_pattern.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_spec.dart';
import 'shop_openapi_fixture.dart';

Map<String, dynamic> _s(Map<String, dynamic> schema) => schema;

Object? _gen(Map<String, dynamic> schema, {String name = '', int seed = 1, int index = 0, MockSide side = MockSide.response, String path = r'$'}) =>
    MockFaker(seed: seed).generate(schema, name: name, index: index, side: side, path: path);

void main() {
  group('determinism', () {
    final user = {
      'type': 'object',
      'properties': {
        'id': {'type': 'integer'},
        'name': {'type': 'string'},
        'email': {'type': 'string', 'format': 'email'},
        'createdAt': {'type': 'string', 'format': 'date-time'},
        'tags': {'type': 'array', 'items': {'type': 'string'}},
        'score': {'type': 'number'},
      },
    };

    test('the same seed gives the same data, whatever was generated before', () {
      final a = MockFaker(seed: 7);
      final b = MockFaker(seed: 7);
      final first = a.generate(user, path: r'$.users[0]');
      // `b` generates something else first: the result for a position must not depend on it.
      b.generate(user, path: r'$.orders[4]');
      b.generate(user, path: r'$.users[1]');
      expect(b.generate(user, path: r'$.users[0]'), first);
      expect(jsonEncode(MockFaker(seed: 7).generate(user, path: r'$.users[0]')), jsonEncode(first));
    });

    test('another seed gives other data', () {
      expect(MockFaker(seed: 1).generate(user), isNot(MockFaker(seed: 2).generate(user)));
    });

    test('the output can be written as JSON', () {
      expect(() => jsonEncode(MockFaker(seed: 3).generate(user)), returnsNormally);
    });
  });

  group('what the document says comes first', () {
    test('example beats default beats enum', () {
      expect(_gen({'type': 'string', 'example': 'x', 'default': 'y', 'enum': ['z']}), 'x');
      expect(_gen({'type': 'string', 'default': 'y', 'enum': ['z']}), 'y');
      expect(_gen({'type': 'string', 'enum': ['z']}), 'z');
      expect(_gen({'const': 'fixed'}), 'fixed');
    });

    test('an enum value is one of the enum, and a list steps through it', () {
      final schema = {
        'type': 'array',
        'minItems': 6,
        'items': {
          'type': 'string',
          'enum': ['a', 'b', 'c'],
        },
      };
      final values = (_gen(schema) as List).cast<String>();
      expect(values, hasLength(6));
      expect(values.toSet(), everyElement(isIn(['a', 'b', 'c'])));
      // Three consecutive items cover the three values: the index rotates the choice.
      expect(values.take(3).toSet(), {'a', 'b', 'c'});
    });

    test('an example that is an object is copied, not shared', () {
      final example = {'k': [1, 2]};
      final value = _gen({'type': 'object', 'example': example}) as Map;
      (value['k'] as List).add(3);
      expect(example['k'], [1, 2]);
    });
  });

  group('formats and names', () {
    test('format email, uuid, date-time, date, time, uri', () {
      expect(_gen({'type': 'string', 'format': 'email'}), matches(RegExp(r'^[a-z]+\.[a-z]+@example\.com$')));
      expect(
        _gen({'type': 'string', 'format': 'uuid'}),
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
      final at = DateTime.parse(_gen({'type': 'string', 'format': 'date-time'}) as String);
      expect(at.isUtc, isTrue);
      expect(at.isAfter(DateTime.utc(2025, 12, 31)) && at.isBefore(DateTime.utc(2027)), isTrue);
      expect(_gen({'type': 'string', 'format': 'date'}), matches(RegExp(r'^2026-\d\d-\d\d$')));
      expect(_gen({'type': 'string', 'format': 'time'}), matches(RegExp(r'^([01]\d|2[0-3]):[0-5]\d:[0-5]\d$')));
      expect(_gen({'type': 'string', 'format': 'uri'}), startsWith('https://example.com/'));
    });

    test('field names without a format: email, phone, name, first name, city, url, price, age, id', () {
      expect(_gen({'type': 'string'}, name: 'email'), matches(RegExp(r'^[a-z]+\.[a-z]+@example\.com$')));
      expect(_gen({'type': 'string'}, name: 'contact_email'), contains('@example.com'));
      expect(_gen({'type': 'string'}, name: 'phone'), matches(RegExp(r'^\+1-555-\d{4}$')));
      expect(_gen({'type': 'string'}, name: 'name'), matches(RegExp(r'^[A-Z][a-z]+ [A-Z][a-z]+$')));
      expect(_gen({'type': 'string'}, name: 'firstName'), matches(RegExp(r'^[A-Z][a-z]+$')));
      expect(_gen({'type': 'string'}, name: 'last_name'), matches(RegExp(r'^[A-Z][a-z]+$')));
      expect(_gen({'type': 'string'}, name: 'website'), startsWith('https://example.com/'));
      expect(_gen({'type': 'string'}, name: 'avatarUrl'), endsWith('.jpg'));
      expect(_gen({'type': 'string'}, name: 'city'), matches(RegExp(r'^[A-Z][a-z]+$')));
      expect(_gen({'type': 'string'}, name: 'userId'), matches(RegExp(r'^[0-9a-f]{8}-')));
      // A createdAt string is a timestamp even without a format.
      expect(DateTime.tryParse(_gen({'type': 'string'}, name: 'createdAt') as String), isNotNull);
      expect(DateTime.tryParse(_gen({'type': 'string'}, name: 'updated_at') as String), isNotNull);
    });

    test('numbers by name: price is a two-decimal amount, age an adult age, page 1, limit 10', () {
      for (var seed = 1; seed <= 20; seed++) {
        final price = _gen({'type': 'number'}, name: 'price', seed: seed) as double;
        expect(price, inInclusiveRange(1, 999));
        expect((price * 100).roundToDouble(), closeTo(price * 100, 1e-6), reason: 'at most two decimals');
        expect(_gen({'type': 'integer'}, name: 'age', seed: seed), inInclusiveRange(18, 80));
        expect(_gen({'type': 'integer'}, name: 'quantity', seed: seed), inInclusiveRange(1, 20));
        expect(_gen({'type': 'number'}, name: 'latitude', seed: seed), inInclusiveRange(-90, 90));
      }
      expect(_gen({'type': 'integer'}, name: 'page'), 1);
      expect(_gen({'type': 'integer'}, name: 'limit'), 10);
    });

    test('a word that merely contains "age" is not an age', () {
      // `page` and `message` contain `age`; only the word age is an age.
      expect(_gen({'type': 'integer'}, name: 'page'), 1);
      final message = _gen({'type': 'string'}, name: 'message') as String;
      expect(message, endsWith('.'));
    });

    test('ids count up in a list, strings are uuids, a lone id is 1', () {
      final list = _gen({
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'id': {'type': 'integer'},
            'ref': {'type': 'string', 'format': 'uuid'},
          },
        },
      }) as List;
      expect(list.map((e) => (e as Map)['id']), [1, 2, 3]);
      expect(_gen({'type': 'integer'}, name: 'id'), 1);
      expect(_gen({'type': 'string'}, name: 'id'), matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-')));
    });

    test('booleans by name: active is true, deleted is false', () {
      for (var seed = 1; seed <= 10; seed++) {
        expect(_gen({'type': 'boolean'}, name: 'active', seed: seed), isTrue);
        expect(_gen({'type': 'boolean'}, name: 'isDeleted', seed: seed), isFalse);
      }
    });
  });

  group('limits', () {
    test('minimum, maximum, exclusive bounds and multipleOf', () {
      for (var seed = 1; seed <= 30; seed++) {
        expect(_gen({'type': 'integer', 'minimum': 5, 'maximum': 7}, seed: seed), inInclusiveRange(5, 7));
        final exclusive = _gen({'type': 'integer', 'exclusiveMinimum': 10, 'exclusiveMaximum': 13}, seed: seed) as int;
        expect(exclusive, inInclusiveRange(11, 12));
        final stepped = _gen({'type': 'number', 'minimum': 0, 'maximum': 10, 'multipleOf': 0.5}, seed: seed) as double;
        expect(stepped % 0.5, 0);
        expect(stepped, inInclusiveRange(0, 10));
      }
    });

    test('minLength and maxLength', () {
      expect((_gen({'type': 'string', 'minLength': 40}) as String).length, greaterThanOrEqualTo(40));
      expect((_gen({'type': 'string', 'maxLength': 4}) as String).length, lessThanOrEqualTo(4));
      expect((_gen({'type': 'string', 'minLength': 8, 'maxLength': 8}) as String), hasLength(8));
    });

    test('arrays have three items unless the limits say otherwise', () {
      final items = {'type': 'string'};
      expect(_gen({'type': 'array', 'items': items}), hasLength(3));
      expect(_gen({'type': 'array', 'items': items, 'minItems': 5}), hasLength(5));
      expect(_gen({'type': 'array', 'items': items, 'maxItems': 2}), hasLength(2));
      expect(_gen({'type': 'array', 'items': items, 'maxItems': 0}), isEmpty);
    });

    test('pattern: the value matches it', () {
      for (var seed = 1; seed <= 20; seed++) {
        expect(_gen({'type': 'string', 'pattern': r'^[A-Z]{3}-\d{4}$'}, seed: seed), matches(RegExp(r'^[A-Z]{3}-\d{4}$')));
        expect(_gen({'type': 'string', 'pattern': r'^(?:red|green|blue)$'}, seed: seed), isIn(['red', 'green', 'blue']));
      }
    });

    test('additionalProperties makes two entries', () {
      final value = _gen({'type': 'object', 'additionalProperties': {'type': 'integer'}}) as Map;
      expect(value.keys, ['key1', 'key2']);
      expect(value.values, everyElement(isA<int>()));
    });
  });

  group('required, nullable, read-only and write-only', () {
    final schema = {
      'type': 'object',
      'required': ['name', 'maybe'],
      'properties': {
        'id': {'type': 'integer', 'readOnly': true},
        'password': {'type': 'string', 'writeOnly': true},
        'name': {'type': 'string'},
        'nickname': {'type': 'string', 'nullable': true},
        'maybe': {'type': 'string', 'nullable': true},
      },
    };

    test('a response leaves out write-only properties, a request read-only ones', () {
      final response = _gen(schema) as Map;
      expect(response.containsKey('password'), isFalse);
      expect(response.containsKey('id'), isTrue);
      final request = _gen(schema, side: MockSide.request) as Map;
      expect(request.containsKey('id'), isFalse);
      expect(request.containsKey('password'), isTrue);
    });

    test('an optional nullable property is sometimes null; a required one never is', () {
      final nicknames = <Object?>[];
      for (var seed = 1; seed <= 60; seed++) {
        final value = _gen(schema, seed: seed) as Map;
        nicknames.add(value['nickname']);
        expect(value['maybe'], isNotNull, reason: 'required, so present and not null (seed $seed)');
        expect(value['name'], isNotNull);
      }
      expect(nicknames.where((n) => n == null), isNotEmpty);
      expect(nicknames.where((n) => n != null), isNotEmpty);
    });

    test('type [string, null] and anyOf with a null branch are nullable strings', () {
      expect(_gen({'type': ['string', 'null']}, name: 'email'), isA<String>());
      expect(
        _gen({
          'anyOf': [
            {'type': 'null'},
            {'type': 'integer', 'minimum': 4, 'maximum': 4},
          ],
        }),
        4,
      );
    });
  });

  group('with the references of a real document', () {
    test('allOf and \$ref are merged: a User has the Base properties and its own', () {
      final spec = MockSpec.parse(shopOpenApiJson);
      final faker = MockFaker(seed: 5, resolver: spec.resolver);
      final user = faker.generate({r'$ref': '#/components/schemas/User'}, name: 'user') as Map;
      expect(user['id'], isA<int>());
      expect(DateTime.tryParse(user['createdAt'] as String), isNotNull);
      expect(user['name'], isA<String>());
      expect(user['email'], contains('@'));
      expect(user['role'], isIn(['admin', 'member']));
      expect(user['age'], inInclusiveRange(18, 80));
      expect(user.containsKey('password'), isFalse, reason: 'write-only');
    });

    test('a schema that contains itself stops instead of running forever', () {
      final faker = MockFaker(seed: 1);
      // Built by hand: a node whose child is the node.
      final node = <String, dynamic>{'type': 'object', 'properties': <String, dynamic>{}};
      (node['properties'] as Map<String, dynamic>)['child'] = node;
      expect(() => jsonEncode(faker.generate(node)), returnsNormally);
    });
  });

  group('MockPattern', () {
    test('generates strings the pattern accepts', () {
      final random = Random(4);
      for (final pattern in [
        r'^[a-z]{2,5}$',
        r'^\+?\d{7,12}$',
        r'^[A-Z]{2}\d{2}[A-Z0-9]{4}$',
        r'^(foo|bar)-\d+$',
        r'^\w+@\w+\.com$',
        r'^[^0-9]{3}$',
        r'^a.c$',
      ]) {
        final value = MockPattern.generate(pattern, random);
        expect(value, isNotNull, reason: pattern);
        expect(RegExp(pattern).hasMatch(value!), isTrue, reason: '$pattern -> $value');
      }
    });

    test('gives up on what it cannot read', () {
      final random = Random(1);
      expect(MockPattern.generate(r'^(?=.*\d)[a-z0-9]+$', random), isNull);
      expect(MockPattern.generate(r'^(a)\1$', random), isNull);
      expect(MockPattern.generate(r'^\p{L}+$', random), isNull);
      expect(MockPattern.generate('(unclosed', random), isNull);
    });
  });

  test('typeOf reads a list of types and infers a missing one', () {
    expect(MockFaker.typeOf(_s({'type': ['null', 'integer']})), 'integer');
    expect(MockFaker.typeOf(_s({'properties': {}})), 'object');
    expect(MockFaker.typeOf(_s({'items': {}})), 'array');
    expect(MockFaker.typeOf(_s({})), isNull);
    expect(MockFaker.isNullable(_s({'nullable': true})), isTrue);
    expect(MockFaker.isNullable(_s({'type': ['string', 'null']})), isTrue);
    expect(MockFaker.isNullable(_s({'type': 'string'})), isFalse);
  });
}
