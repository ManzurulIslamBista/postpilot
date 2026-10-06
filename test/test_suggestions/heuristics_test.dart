import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/test_suggestions/domain/services/body_shape.dart';
import 'package:postpilot/features/test_suggestions/domain/services/enum_rules.dart';
import 'package:postpilot/features/test_suggestions/domain/services/response_time_bound.dart';
import 'package:postpilot/features/test_suggestions/domain/services/stability_probe.dart';
import 'package:postpilot/features/test_suggestions/domain/services/value_formats.dart';
import 'package:postpilot/features/test_suggestions/domain/services/volatility.dart';

void main() {
  group('ResponseTimeBound: three times the measurement, rounded up, never under 500 ms', () {
    // Worked by hand: raw = ms x 3; step 100 below 5000, 500 below 30000, else 1000; round up to the step.
    const cases = <(int, int)>[
      (0, 500), // 0 -> 0, raised to the floor
      (120, 500), // 360 -> 400, raised to the floor
      (166, 500), // 498 -> 500
      (167, 600), // 501 -> 600
      (200, 600), // 600
      (201, 700), // 603 -> 700
      (1234, 3800), // 3702 -> 3800
      (1700, 5500), // 5100 -> step 500 -> 5500
      (9999, 30000), // 29997 -> step 500 -> 30000
      (10000, 30000), // 30000 -> step 1000
      (40000, 120000),
      (-5, 500),
    ];
    for (final (measured, limit) in cases) {
      test('$measured ms -> $limit ms', () => expect(ResponseTimeBound.forMeasured(measured), limit));
    }
  });

  group('Volatility', () {
    test('words splits camelCase, snake_case and kebab-case alike', () {
      expect(Volatility.words('createdAt'), ['created', 'at']);
      expect(Volatility.words('created_at'), ['created', 'at']);
      expect(Volatility.words('x-request-id'), ['x', 'request', 'id']);
      expect(Volatility.words('userID'), ['user', 'id']);
      expect(Volatility.words(''), isEmpty);
    });

    test('names that change by themselves', () {
      expect(Volatility.reason('id', 5), 'it is an id');
      expect(Volatility.reason('userId', 'abc'), 'it is an id');
      expect(Volatility.reason('uuid', 'x'), 'it is an id');
      expect(Volatility.reason('access_token', 'x'), 'it is a token or hash');
      expect(Volatility.reason('etag', 'x'), 'it is a token or hash');
      expect(Volatility.reason('retry_count', 3), 'it is a counter');
      expect(Volatility.reason('total', 3), 'it is a counter');
      expect(Volatility.reason('randomSeed', 3), 'it is random');
      expect(Volatility.reason('updated_at', 'x'), 'it is a date or time');
      expect(Volatility.reason('timestamp', 1), 'it is a date or time');
    });

    test('values that look like something that changes by itself', () {
      expect(Volatility.reason('x', '2026-10-06T09:15:30Z'), 'it looks like a date or time');
      expect(Volatility.reason('x', '2026-10-06'), 'it looks like a date or time');
      expect(Volatility.reason('x', 'b1f4c2a0-5e1d-4b8e-9d57-0a1b2c3d4e5f'), 'it looks like a UUID');
      expect(Volatility.reason('x', 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc'), 'it looks like a token or id');
      expect(Volatility.reason('x', 'a3f9c2d4e5b6a7f8c9d0e1f2a3b4'), 'it looks like a token or id');
      expect(Volatility.reason('x', 1700000000), 'it looks like a Unix timestamp');
      expect(Volatility.reason('x', 1700000000000), 'it looks like a Unix timestamp');
      expect(Volatility.reason('x', 1700000000000000), 'it looks like a Unix timestamp');
      expect(Volatility.reason('x', 9007199254740993), 'it is a very large number, like a generated id');
      expect(Volatility.reason('x', 1234567890123456789), 'it is a very large number, like a generated id');
    });

    test('ordinary values are stable', () {
      for (final (key, value) in <(String, Object?)>[
        ('currency', 'USD'),
        ('page', 1),
        ('name', 'Widget'),
        ('price', 19.99),
        ('active', true),
        ('version', '2.1.0'),
        ('limit', 50),
        ('nothing', null),
        ('population', 1500000), // a large number that is not a timestamp
        ('ratio', 1700000000.5), // looks like a timestamp but has decimals
      ]) {
        expect(Volatility.reason(key, value), isNull, reason: '$key: $value');
      }
    });
  });

  group('ValueFormats', () {
    test('recognises ids, emails, urls, dates and tokens', () {
      expect(ValueFormats.of('b1f4c2a0-5e1d-4b8e-9d57-0a1b2c3d4e5f'), ValueFormat.uuid);
      expect(ValueFormats.of('ann@example.com'), ValueFormat.email);
      expect(ValueFormats.of('https://example.com/a?b=1'), ValueFormat.url);
      expect(ValueFormats.of('2026-10-06T09:15:30Z'), ValueFormat.dateTime);
      expect(ValueFormats.of('2026-10-06 09:15'), ValueFormat.dateTime);
      expect(ValueFormats.of('2026-10-06'), ValueFormat.date);
      expect(ValueFormats.of('eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig'), ValueFormat.jwt);
      expect(ValueFormats.of('a3f9c2d4e5b6a7f8c9d0'), ValueFormat.opaqueId);
      expect(ValueFormats.of('01ARZ3NDEKTSV4RRFFQ69G5FAV'), ValueFormat.opaqueId, reason: 'a ULID');
    });

    test('ordinary text and impossible dates are nothing', () {
      expect(ValueFormats.of('hello world'), isNull);
      expect(ValueFormats.of('USD'), isNull);
      expect(ValueFormats.of(''), isNull);
      expect(ValueFormats.of('2026-13-45'), isNull);
      expect(ValueFormats.of('not-an-email@'), isNull);
      expect(ValueFormats.of('ftp://example.com'), isNull);
    });

    test('commonFormat needs every value to be a string of one kind', () {
      expect(ValueFormats.commonFormat(['a@b.co', 'c@d.org']), ValueFormat.email);
      expect(ValueFormats.commonFormat(['a@b.co', 'plain']), isNull);
      expect(ValueFormats.commonFormat(['a@b.co', 2026]), isNull);
      expect(ValueFormats.commonFormat(const []), isNull);
    });

    test('idPattern describes how ids are built, and every value matches it', () {
      final digits = ValueFormats.idPattern(['123', '4567'])!;
      expect(digits.regex, r'^\d+$');
      final prefixed = ValueFormats.idPattern(['usr_8f3a9c', 'usr_77aa11'])!;
      expect(prefixed.regex, r'^usr_[A-Za-z0-9]+$');
      expect(prefixed.phrase, 'starts with "usr_" and ends in letters or digits');
      expect(RegExp(prefixed.regex).hasMatch('usr_8f3a9c'), isTrue);
      expect(RegExp(prefixed.regex).hasMatch('ord_8f3a9c'), isFalse);
      final hex = ValueFormats.idPattern(['0123456789ab', 'ba9876543210'])!;
      expect(hex.regex, r'^[0-9a-f]{12}$');
      expect(hex.phrase, 'is 12 lower-case hex characters');
      expect(ValueFormats.idPattern(['abc']), isNull);
      expect(ValueFormats.idPattern(['usr_aaaa', 'ord_bbbb']), isNull, reason: 'two prefixes are no pattern');
      expect(ValueFormats.idPattern(const []), isNull);
    });
  });

  group('EnumRules', () {
    FieldShape field(List<Object?> values, {String key = 'status'}) {
      final shape = BodyShape.of([for (final v in values) {key: v}]);
      return shape['[].$key']!;
    }

    test('a few values repeated many times are an enumeration', () {
      expect(EnumRules.valuesOf('[].status', field(['a', 'b', 'a', 'b'])), ['a', 'b']);
      expect(EnumRules.valuesOf('[].status', field(['a', null, 'a', null, 'a', 'b'])), ['a', 'b'], reason: 'nulls are not counted');
      expect(EnumRules.valuesOf('[].status', field(['a', 'a', 'a', 'a'])), ['a']);
    });

    test('too few values, too many kinds, or values that hardly repeat are not', () {
      expect(EnumRules.valuesOf('[].status', field(['a', 'a', 'a'])), isNull, reason: 'three values prove nothing');
      expect(EnumRules.valuesOf('[].status', field(['a', 'b', 'c', 'a'])), isNull, reason: '3 kinds in 4 values');
      expect(EnumRules.valuesOf('[].status', field(['a', 'b', 'c', 'd', 'e', 'f', 'a', 'b', 'c', 'd', 'e', 'f'])), isNull, reason: 'six kinds');
      expect(EnumRules.valuesOf('[].status', field([null, null, null, null, 'x'])), isNull);
    });

    test('whole numbers count only when the name says they are codes', () {
      expect(EnumRules.valuesOf('[].status', field([1, 2, 1, 2])), [1, 2]);
      expect(EnumRules.valuesOf('[].qty', field([1, 2, 1, 2], key: 'qty')), isNull);
    });

    test('fields that change by themselves are never enumerations', () {
      expect(EnumRules.valuesOf('[].created', field(['x', 'x', 'x', 'x'], key: 'created')), isNull);
      expect(EnumRules.valuesOf('[].status', field(['2026-10-06', '2026-10-06', '2026-10-06', '2026-10-06'])), isNull);
      expect(EnumRules.valuesOf('[].status', field([('x' * 41), ('x' * 41), ('x' * 41), ('x' * 41)])), isNull);
    });
  });

  group('StabilityProbe', () {
    test('values that differ are marked, element by element, as a column', () {
      final a = {
        'k': 1,
        'items': [
          {'x': 1},
          {'x': 2},
        ],
      };
      final b = {
        'k': 2,
        'items': [
          {'x': 1},
          {'x': 3},
          {'x': 9},
        ],
      };
      final report = StabilityProbe.compare(a, b);
      expect(report.changing, {'k', 'items[].x'});
      expect(report.changingLength, {'items'});
      expect(report.unstablePresence, isEmpty);
      expect(report.isStable('k'), isFalse);
      expect(report.isStable('items[].x'), isFalse);
      expect(report.isStable('other'), isTrue);
    });

    test('a key in one response only is unstable presence, not a changed value', () {
      final report = StabilityProbe.compare({'p': 1, 'q': 2}, {'p': 1});
      expect(report.unstablePresence, {'q'});
      expect(report.changing, isEmpty);
      expect(report.volatilePaths, {'q'});
      final reverse = StabilityProbe.compare({'p': 1}, {'p': 1, 'q': 2});
      expect(reverse.unstablePresence, {'q'});
    });

    test('a changed type is a changed value; 1 and 1.0 are the same', () {
      expect(StabilityProbe.compare({'v': 1}, {'v': '1'}).changing, {'v'});
      expect(StabilityProbe.compare({'v': 1}, {'v': 1.0}).changing, isEmpty);
      expect(StabilityProbe.compare({'v': null}, {'v': 'x'}).changing, {'v'});
      expect(StabilityProbe.compare({'v': {'a': 1}}, {'v': [1]}).changing, {'v'});
    });

    test('identical bodies have nothing volatile', () {
      final body = {
        'a': [1, 2, 3],
        'b': {'c': 'd'},
      };
      expect(StabilityProbe.compare(body, body).isEmpty, isTrue);
    });

    test('notComparable trusts nothing', () {
      expect(StabilityReport.notComparable.isStable('anything'), isFalse);
    });
  });

  group('BodyShape', () {
    test('paths, types, how often each appears, and which fields are optional', () {
      final shape = BodyShape.of({
        'items': [
          {'id': 1, 'note': null, 'price': 2.5},
          {'id': 2, 'price': 3},
          {'id': 3, 'note': 'x', 'price': 4},
        ],
        'meta': {'count': 3},
      });
      expect(shape.fields.keys, ['', 'items', 'items[]', 'items[].id', 'items[].note', 'items[].price', 'meta', 'meta.count']);
      expect(shape['items[].id']!.types, {'integer'});
      expect(shape['items[].id']!.optional, isFalse);
      expect(shape['items[].note']!.types, {'null', 'string'});
      expect(shape['items[].note']!.optional, isTrue, reason: 'missing from the second element');
      expect(shape['items[].note']!.seen, 2);
      expect(shape['items[].note']!.nonNull, 1);
      expect(shape['items[].price']!.types, {'number', 'integer'});
      expect(shape['meta.count']!.optional, isFalse);
      expect(shape.hasElements('items'), isTrue);
    });

    test('an empty array has no element shape', () {
      final shape = BodyShape.of({'items': <Object?>[]});
      expect(shape['items']!.types, {'array'});
      expect(shape.hasElements('items'), isFalse);
    });

    test('a whole-valued double is an integer, a fraction a number, big ints stay integers', () {
      expect(BodyShape.typeOf(100.0), 'integer');
      expect(BodyShape.typeOf(1.5), 'number');
      expect(BodyShape.typeOf(9007199254740993), 'integer');
      expect(BodyShape.typeOf(null), 'null');
      expect(BodyShape.typeOf(true), 'boolean');
    });

    test('distinct values are kept in order, up to a cap', () {
      final shape = BodyShape.of([for (var i = 0; i < 20; i++) {'v': 'v${i % 15}'}]);
      final field = shape['[].v']!;
      expect(field.distinct.take(3), ['v0', 'v1', 'v2']);
      expect(field.manyDistinct, isTrue);
      expect(field.distinct.length, BodyShape.maxDistinct + 1);
    });

    test('a very large body is cut and flagged', () {
      final shape = BodyShape.of([for (var i = 0; i < BodyShape.maxArrayItems + 5; i++) i]);
      expect(shape.truncated, isTrue);
      expect(shape['[]']!.seen, BodyShape.maxArrayItems);
    });
  });
}
