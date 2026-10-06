import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/test_suggestions/domain/services/baseline_check.dart';
import 'package:postpilot/features/test_suggestions/domain/services/baseline_file.dart';
import 'package:postpilot/features/test_suggestions/domain/services/baseline_recorder.dart';
import 'response_fixtures.dart';

void main() {
  group('the baseline result row of a run', () {
    final baseline = BaselineRecorder.record(response({'a': 1, 'b': 'x', 'c': true, 'd': [1]}));

    test('passes, saying so, when the response matches', () {
      final row = BaselineCheck.evaluate(baseline, response({'a': 1, 'b': 'x', 'c': true, 'd': [1]}));
      expect(row.name, 'Baseline: 0 breaking changes');
      expect(row.passed, isTrue);
      expect(row.actual, 'Matches the baseline');
    });

    test('passes with the count of lesser changes when nothing breaks', () {
      final row = BaselineCheck.evaluate(baseline, response({'a': 1, 'b': 'y', 'c': true, 'd': [1], 'e': 1}));
      expect(row.name, 'Baseline: 0 breaking changes');
      expect(row.passed, isTrue);
      expect(row.actual, '1 non-breaking, 1 info');
    });

    test('fails on one breaking change, in the singular, with the reason', () {
      final row = BaselineCheck.evaluate(baseline, response({'a': 1, 'b': 'x', 'c': true}));
      expect(row.name, 'Baseline: 1 breaking change');
      expect(row.passed, isFalse);
      expect(row.actual, 'body.d was removed.');
    });

    test('fails on several, listing the first three', () {
      final row = BaselineCheck.evaluate(baseline, response({'a': 'x'}));
      expect(row.name, 'Baseline: 4 breaking changes');
      expect(row.passed, isFalse);
      expect(row.actual, 'body.a changed from integer to string. body.b was removed. body.c was removed. (and 1 more)');
    });

    test('a missing baseline fails: enforcement was asked for and cannot be done', () {
      final row = BaselineCheck.evaluate(null, response({'a': 1}));
      expect(row.name, 'Baseline: none recorded');
      expect(row.passed, isFalse);
      expect(row.actual, contains('Record one'));
      expect(BaselineCheck.evaluate(null, response({}), missingHint: 'Pass --baseline-file.').actual, 'Pass --baseline-file.');
    });

    test('a status that changed class is one breaking change, whatever the body says', () {
      final row = BaselineCheck.evaluate(baseline, response({'error': 'down'}, status: 503));
      expect(row.name, 'Baseline: 1 breaking change');
      expect(row.passed, isFalse);
    });
  });

  group('the baseline file', () {
    final a = BaselineRecorder.record(response({'a': 1}));
    final b = BaselineRecorder.record(response([1, 2]));
    final file = BaselineFile([
      BaselineFileEntry(collection: 'Shop', folder: 'Orders/Admin', name: 'List orders', method: 'GET', snapshot: a, recordedAt: DateTime.utc(2026, 10, 6, 12)),
      BaselineFileEntry(collection: 'Shop', folder: '', name: 'Ping', method: 'GET', snapshot: b),
    ]);

    test('names the format and version, and reads back what was written', () {
      final text = file.encode(exportedAt: DateTime.utc(2026, 10, 6, 13));
      final json = jsonDecode(text) as Map<String, dynamic>;
      expect(json['format'], 'postpilot-baselines');
      expect(json['version'], 1);
      expect(json['exportedAt'], '2026-10-06T13:00:00.000Z');
      final back = BaselineFile.parse(text);
      expect(back.entries.map((e) => '${e.collection}|${e.folder}|${e.name}|${e.method}'), ['Shop|Orders/Admin|List orders|GET', 'Shop||Ping|GET']);
      expect(back.entries.first.recordedAt, DateTime.utc(2026, 10, 6, 12));
      expect(back.entries.last.recordedAt, isNull);
      expect(jsonEncode(back.entries.first.snapshot.toJson()), jsonEncode(a.toJson()));
    });

    test('finds a request by collection, folder, name and method', () {
      final back = BaselineFile.parse(file.encode());
      expect(back.find(collection: 'Shop', folder: 'Orders/Admin', name: 'List orders', method: 'get'), isNotNull);
      expect(back.find(collection: 'Shop', folder: '', name: 'Ping', method: 'GET'), isNotNull);
      expect(back.find(collection: 'Shop', folder: 'Orders', name: 'List orders', method: 'GET'), isNull, reason: 'another folder');
      expect(back.find(collection: 'Shop', folder: 'Orders/Admin', name: 'List orders', method: 'POST'), isNull, reason: 'another method');
      expect(back.find(collection: 'Other', folder: '', name: 'Ping', method: 'GET'), isNull);
    });

    test('says what is wrong with a file that is not one', () {
      expect(() => BaselineFile.parse('not json'), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('not valid JSON'))));
      expect(() => BaselineFile.parse('{"hello":1}'), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('not a PostPilot baseline file'))));
      expect(() => BaselineFile.parse('[1]'), throwsA(isA<FormatException>()));
      expect(
        () => BaselineFile.parse('{"format":"postpilot-baselines","version":99,"baselines":[]}'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('version 99'))),
      );
    });

    test('skips an entry that is damaged instead of refusing the file', () {
      final text = jsonEncode({
        'format': 'postpilot-baselines',
        'version': 1,
        'baselines': [
          {'collection': 'Shop', 'name': 'Good', 'snapshot': a.toJson()},
          {'collection': 'Shop', 'snapshot': a.toJson()},
          {'collection': 'Shop', 'name': 'NoSnapshot'},
          'junk',
        ],
      });
      expect(BaselineFile.parse(text).entries.map((e) => e.name), ['Good']);
    });

    test('an empty file has no entries', () {
      expect(BaselineFile.empty.entries, isEmpty);
      expect(BaselineFile.parse(BaselineFile.empty.encode()).entries, isEmpty);
    });
  });
}
