import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/utils/dynamic_variables.dart';

final _now = DateTime.utc(2026, 9, 30, 12, 0, 0, 123);

DynamicVariables _generator([int seed = 1]) => DynamicVariables(random: Random(seed), clock: () => _now);

final _uuidV4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
final _isoInstant = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$');
final _sentence = r'[A-Z][a-z]*( [a-z]+){5,11}\.';

/// One row per built-in: the shape every draw must have.
final _formats = <String, RegExp>{
  r'$guid': _uuidV4,
  r'$randomUUID': _uuidV4,
  r'$timestamp': RegExp(r'^\d{10}$'),
  r'$isoTimestamp': _isoInstant,
  r'$randomInt': RegExp(r'^\d{1,4}$'),
  r'$randomBoolean': RegExp(r'^(true|false)$'),
  r'$randomAlphaNumeric': RegExp(r'^[a-z0-9]$'),
  r'$randomHexColor': RegExp(r'^#[0-9a-f]{6}$'),
  r'$randomColor': RegExp(r'^[a-z]+$'),
  r'$randomIP': RegExp(r'^\d{1,3}(\.\d{1,3}){3}$'),
  r'$randomIPV6': RegExp(r'^([0-9a-f]{4}:){7}[0-9a-f]{4}$'),
  r'$randomMACAddress': RegExp(r'^([0-9a-f]{2}:){5}[0-9a-f]{2}$'),
  r'$randomPassword': RegExp(r'^[A-Za-z0-9]{15}$'),
  r'$randomWord': RegExp(r'^[a-z]+$'),
  r'$randomLoremWord': RegExp(r'^[a-z]+$'),
  r'$randomLoremWords': RegExp(r'^[a-z]+( [a-z]+){2}$'),
  r'$randomLoremSentence': RegExp('^$_sentence\$'),
  r'$randomLoremParagraph': RegExp('^$_sentence( $_sentence){2}\$'),
  r'$randomFirstName': RegExp(r'^[A-Z][a-z]+$'),
  r'$randomLastName': RegExp(r'^[A-Z][a-z]+$'),
  r'$randomFullName': RegExp(r'^[A-Z][a-z]+ [A-Z][a-z]+$'),
  r'$randomUserName': RegExp(r'^[A-Z][a-z]+[._][A-Z][a-z]+\d{1,3}$'),
  r'$randomEmail': RegExp(r'^[a-z]+[._][a-z]+\d{1,3}@example\.(com|net|org)$'),
  r'$randomPhoneNumber': RegExp(r'^[2-9]\d{2}-\d{3}-\d{4}$'),
  r'$randomCity': RegExp(r'^[A-Z][a-z]+$'),
  r'$randomCountry': RegExp(r'^[A-Z][a-z]+( [A-Z][a-z]+)?$'),
  r'$randomCountryCode': RegExp(r'^[A-Z]{2}$'),
  r'$randomStreetName': RegExp(r'^[A-Z][a-z]+ [A-Z][a-z]+$'),
  r'$randomStreetAddress': RegExp(r'^[1-9]\d{0,3} [A-Z][a-z]+ [A-Z][a-z]+$'),
  r'$randomCompanyName': RegExp(r'^[A-Z][a-z]+ [A-Z][a-z]+$'),
  r'$randomJobTitle': RegExp(r'^[A-Z][A-Za-z]*( [A-Za-z]+)*$'),
  r'$randomDomainWord': RegExp(r'^[a-z]+$'),
  r'$randomDomainSuffix': RegExp(r'^[a-z]+$'),
  r'$randomDomainName': RegExp(r'^[a-z]+-[a-z]+\.[a-z]+$'),
  r'$randomUrl': RegExp(r'^https://[a-z]+-[a-z]+\.[a-z]+$'),
  r'$randomDateFuture': _isoInstant,
  r'$randomDatePast': _isoInstant,
  r'$randomDateRecent': _isoInstant,
};

void main() {
  group('formats', () {
    for (final entry in _formats.entries) {
      test('${entry.key} always looks like ${entry.value.pattern}', () {
        final generator = _generator();
        for (var i = 0; i < 300; i++) {
          expect(generator.resolve(entry.key), matches(entry.value));
        }
      });
    }

    test('a format is pinned for every supported name, and only those', () {
      expect(_formats.keys.toSet(), DynamicVariables.names.toSet());
    });
  });

  group('values', () {
    test(r'$timestamp is the clock in whole unix seconds', () {
      expect(_generator().resolve(r'$timestamp'), '${_now.millisecondsSinceEpoch ~/ 1000}');
    });

    test(r'$isoTimestamp is the clock as a UTC instant with milliseconds', () {
      expect(_generator().resolve(r'$isoTimestamp'), '2026-09-30T12:00:00.123Z');
    });

    test(r'$isoTimestamp drops the microseconds a native clock carries', () {
      final generator = DynamicVariables(clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 789));

      expect(generator.resolve(r'$isoTimestamp'), '2026-01-02T03:04:05.006Z');
    });

    test('the clock is read on every call', () {
      var current = _now;
      final generator = DynamicVariables(random: Random(1), clock: () => current);

      final first = int.parse(generator.resolve(r'$timestamp')!);
      current = current.add(const Duration(seconds: 90));

      expect(int.parse(generator.resolve(r'$timestamp')!), first + 90);
    });

    test(r'$randomInt stays within 0 and 1000', () {
      final generator = _generator();
      final values = [for (var i = 0; i < 2000; i++) int.parse(generator.resolve(r'$randomInt')!)];

      expect(values.every((v) => v >= 0 && v <= 1000), isTrue);
      expect(values.toSet().length, greaterThan(500));
    });

    test(r'$randomIP has four octets of 0-255 and never starts or ends with 0', () {
      final generator = _generator();
      for (var i = 0; i < 500; i++) {
        final octets = generator.resolve(r'$randomIP')!.split('.').map(int.parse).toList();

        expect(octets.every((o) => o >= 0 && o <= 255), isTrue);
        expect(octets.first, greaterThan(0));
        expect(octets.last, greaterThan(0));
      }
    });

    test(r'$randomDateFuture is up to a year after the clock', () {
      final generator = _generator();
      for (var i = 0; i < 200; i++) {
        final date = DateTime.parse(generator.resolve(r'$randomDateFuture')!);

        expect(date.isAfter(_now), isTrue);
        expect(date.isAfter(_now.add(const Duration(days: 365))), isFalse);
      }
    });

    test(r'$randomDatePast is up to a year before the clock', () {
      final generator = _generator();
      for (var i = 0; i < 200; i++) {
        final date = DateTime.parse(generator.resolve(r'$randomDatePast')!);

        expect(date.isBefore(_now), isTrue);
        expect(date.isBefore(_now.subtract(const Duration(days: 365))), isFalse);
      }
    });

    test(r'$randomDateRecent is within the day before the clock', () {
      final generator = _generator();
      for (var i = 0; i < 200; i++) {
        final date = DateTime.parse(generator.resolve(r'$randomDateRecent')!);

        expect(date.isAfter(_now), isFalse);
        expect(date.isBefore(_now.subtract(const Duration(days: 1))), isFalse);
      }
    });

    test('the two GUID names each draw a fresh, distinct value', () {
      final generator = _generator();
      final guids = {
        for (var i = 0; i < 200; i++) ...[generator.resolve(r'$guid'), generator.resolve(r'$randomUUID')],
      };

      expect(guids, hasLength(400));
    });

    test(r'$randomEmail and $randomUserName rarely repeat across many draws', () {
      final generator = _generator();

      expect({for (var i = 0; i < 300; i++) generator.resolve(r'$randomEmail')}.length, greaterThan(290));
    });
  });

  group('determinism', () {
    test('the same seed and clock give the same value for every name', () {
      final a = _generator(42);
      final b = _generator(42);

      for (final name in DynamicVariables.names) {
        expect(a.resolve(name), b.resolve(name), reason: name);
      }
    });

    test('a different seed gives different values', () {
      expect(_generator(1).resolve(r'$guid'), isNot(_generator(2).resolve(r'$guid')));
      expect(_generator(1).resolve(r'$randomPassword'), isNot(_generator(2).resolve(r'$randomPassword')));
    });

    test('the default generator is not repeatable', () {
      expect(DynamicVariables.shared.resolve(r'$guid'), isNot(DynamicVariables.shared.resolve(r'$guid')));
    });
  });

  group('names', () {
    test(r'are $-prefixed, unique and sorted', () {
      final names = DynamicVariables.names;

      expect(names.every((n) => n.startsWith(r'$')), isTrue);
      expect(names.toSet(), hasLength(names.length));
      expect(names, [...names]..sort());
    });

    test('cannot be edited by a caller', () {
      expect(() => DynamicVariables.names.add(r'$mine'), throwsUnsupportedError);
    });

    test('include every Postman built-in the app promises', () {
      expect(
        DynamicVariables.names,
        containsAll([
          r'$guid', r'$randomUUID', r'$timestamp', r'$isoTimestamp', r'$randomInt', r'$randomBoolean',
          r'$randomAlphaNumeric', r'$randomHexColor', r'$randomIP', r'$randomIPV6', r'$randomMACAddress',
          r'$randomPassword', r'$randomWord', r'$randomLoremWord', r'$randomLoremSentence', r'$randomFirstName',
          r'$randomLastName', r'$randomFullName', r'$randomUserName', r'$randomEmail', r'$randomPhoneNumber',
          r'$randomCity', r'$randomCountry', r'$randomStreetAddress', r'$randomCompanyName', r'$randomUrl',
          r'$randomDomainName', r'$randomColor', r'$randomDateFuture', r'$randomDatePast', r'$randomDateRecent',
        ]),
      );
    });

    test('all resolve to a value', () {
      final generator = _generator();

      for (final name in DynamicVariables.names) {
        expect(generator.resolve(name), isNotNull, reason: name);
      }
    });
  });

  test('a name that is not a built-in resolves to null', () {
    final generator = _generator();

    for (final name in [r'$nope', 'guid', r'$GUID', r'$guid ', ' \$guid', '', r'$']) {
      expect(generator.resolve(name), isNull, reason: '"$name"');
    }
  });
}
