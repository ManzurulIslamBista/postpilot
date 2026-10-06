import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/test_suggestions/domain/entities/baseline_snapshot.dart';
import 'package:postpilot/features/test_suggestions/domain/entities/drift_report.dart';
import 'package:postpilot/features/test_suggestions/domain/services/baseline_recorder.dart';
import 'package:postpilot/features/test_suggestions/domain/services/drift_accept.dart';
import 'package:postpilot/features/test_suggestions/domain/services/drift_detector.dart';
import 'package:postpilot/features/test_suggestions/domain/services/stability_probe.dart';
import 'response_fixtures.dart';

List<String> _summary(DriftReport report) => [for (final c in report.changes) '${c.kind.name}:${c.path}:${c.severity.name}'];

/// One drift case: what the report must say, and that accepting every change leaves nothing to report.
void _case(String name, ApiResponseEntity base, ApiResponseEntity current, List<String> expected) {
  test(name, () {
    final baseline = BaselineRecorder.record(base);
    final report = DriftDetector.compare(baseline, current);
    expect(_summary(report), expected);
    final accepted = DriftAccept.apply(baseline, current, report.changes);
    expect(_summary(DriftDetector.compare(accepted, current)), isEmpty, reason: 'accepting every change leaves the response clean');
  });
}

/// The same pair in both directions: [forward] is X recorded and Y received, [backward] Y recorded and X received.
void _both(String name, ApiResponseEntity x, ApiResponseEntity y, List<String> forward, List<String> backward) {
  _case('$name (X then Y)', x, y, forward);
  _case('$name (Y then X)', y, x, backward);
}

void main() {
  group('a response compared with its own baseline', () {
    test('is clean, whatever it holds', () {
      for (final body in <Object?>[
        ordersBody(),
        [1, 2, 3],
        'text',
        {'a': null, 'b': [], 'c': {}},
        '[{"id":1234567890123456789,"score":1,"label":"a"},{"id":1234567890123456790,"score":2.5,"label":7}]',
      ]) {
        final r = response(body);
        expect(DriftDetector.compare(BaselineRecorder.record(r), r).changes, isEmpty, reason: '$body');
      }
    });

    test('a second send of the same API, with only server-made values different, is clean', () {
      final baseline = BaselineRecorder.record(response(ordersBody()));
      final next = response(ordersBody(cursor: 'ZGlmZmVyZW50LWN1cnNvci0xMjM0NTY3ODkwYWJjZGVmZ2hp', requestId: 9007199254740999));
      expect(_summary(DriftDetector.compare(baseline, next)), isEmpty);
    });

    test('a value that is not volatile by its name, and changed, is reported as info', () {
      final baseline = BaselineRecorder.record(response(ordersBody()));
      expect(_summary(DriftDetector.compare(baseline, response(ordersBody(queueDepth: 15)))), ['valueChanged:queueDepth:info']);
    });
  });

  group('the classification matrix, every kind in both directions', () {
    _both('a field is removed or added', response({'a': 1, 'b': 'x'}), response({'a': 1}),
        ['fieldRemoved:b:breaking'], ['fieldAdded:b:nonBreaking']);

    _both('a field changes type', response({'n': 1}), response({'n': '1'}),
        ['typeChanged:n:breaking'], ['typeChanged:n:breaking']);

    // A whole number to a fraction widens the type (breaking); the other way is narrower, so only the value moved.
    _both('an integer becomes a number', response({'n': 1}), response({'n': 1.5}),
        ['typeChanged:n:breaking'], ['valueChanged:n:info']);

    _both('a required field becomes null, and a field that was always null gets a value', response({'v': 'a'}), response({'v': null}),
        ['becameNull:v:breaking'], ['nullFilled:v:nonBreaking']);

    _both(
      'null appears in some elements only',
      response({'items': [{'v': 'a'}, {'v': 'b'}]}),
      response({'items': [{'v': 'a'}, {'v': null}]}),
      ['becameNull:items[].v:breaking'],
      const [], // no longer null anywhere: narrower, not drift
    );

    _both(
      'a field of an array element stops being in every element',
      response({'items': [{'id': 1, 'n': 'a'}, {'id': 2, 'n': 'b'}]}),
      response({'items': [{'id': 1, 'n': 'a'}, {'id': 2}]}),
      ['becameOptional:items[].n:breaking'],
      const [], // always present now: not drift
    );

    _both(
      'an optional field is absent in the elements, or new there',
      response({'items': [{'id': 1, 'n': 'a'}, {'id': 2}]}),
      response({'items': [{'id': 1}, {'id': 2}]}),
      ['optionalFieldAbsent:items[].n:info'],
      ['fieldAdded:items[].n:nonBreaking'],
    );

    _both(
      'a required element field disappears or is added',
      response({'items': [{'id': 1, 'n': 'a'}, {'id': 2, 'n': 'b'}]}),
      response({'items': [{'id': 1}, {'id': 2}]}),
      ['fieldRemoved:items[].n:breaking'],
      ['fieldAdded:items[].n:nonBreaking'],
    );

    final fourStatuses = response({
      'items': [for (final s in ['a', 'b', 'a', 'b']) {'status': s}],
    });
    final onlyA = response({
      'items': [for (final s in ['a', 'a', 'a', 'a']) {'status': s}],
    });
    _both('an enumeration loses or gains a value', fourStatuses, onlyA,
        ['enumValueGone:items[].status:breaking'], ['enumValueAdded:items[].status:nonBreaking']);

    _case(
      'a new value in a different list of the same size',
      fourStatuses,
      response({
        'items': [for (final s in ['a', 'b', 'c', 'a']) {'status': s}],
      }),
      ['enumValueAdded:items[].status:nonBreaking'],
    );

    _case(
      'fewer values in a smaller sample is not a disappearance',
      fourStatuses,
      response({
        'items': [for (final s in ['a', 'b']) {'status': s}],
      }),
      const [],
    );

    // The status class decides everything: the body of an error is not compared with the body of a success.
    _both('the status changes class', response({'a': 1}), response({'error': 'x'}, status: 404),
        ['statusClassChanged::breaking'], ['statusClassChanged::breaking']);
    _both('the status changes within its class', response({'a': 1}), response({'a': 1}, status: 201),
        ['statusChanged::nonBreaking'], ['statusChanged::nonBreaking']);

    _both(
      'Content-Type changes',
      response({'a': 1}),
      response({'a': 1}, headers: const {'Content-Type': 'text/plain'}),
      ['contentTypeChanged:content-type:breaking'],
      ['contentTypeChanged:content-type:breaking'],
    );
    _both(
      'Content-Type goes missing, or appears',
      response({'a': 1}),
      response({'a': 1}, headers: const {}),
      ['contentTypeChanged:content-type:breaking'],
      ['headerChanged:content-type:info'],
    );
    _case(
      'only the charset of Content-Type differs',
      response({'a': 1}),
      response({'a': 1}, headers: const {'content-type': 'application/json'}),
      const [],
    );

    _both(
      'minor headers change',
      response({'a': 1}, headers: const {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store, max-age=0',
        'Deprecation': 'true',
      }),
      response({'a': 1}, headers: const {
        'Content-Type': 'application/json',
        'Cache-Control': 'public, max-age=60',
        'Sunset': 'Sat, 01 Jan 2028 00:00:00 GMT',
      }),
      ['headerChanged:cache-control:info', 'headerChanged:deprecation:info', 'headerChanged:sunset:info'],
      ['headerChanged:cache-control:info', 'headerChanged:sunset:info', 'headerChanged:deprecation:info'],
    );

    _both('the body stops being JSON, or becomes JSON', response({'a': 1}), response('oops'),
        ['bodyNotJson::breaking'], ['bodyNowJson::info']);
    _case('two non-JSON bodies are not compared', response('one'), response('two'), const []);

    _both(
      'an array is empty now, or was empty in the baseline',
      response({'items': [{'id': 1, 'name': 'a'}]}),
      response({'items': <Object?>[]}),
      ['elementsUnknown:items:info'],
      ['elementsUnknown:items:info'],
    );

    _both('a stable value changes', response({'currency': 'USD'}), response({'currency': 'EUR'}),
        ['valueChanged:currency:info'], ['valueChanged:currency:info']);

    _both('the body turns from an object into an array', response({'a': 1}), response([1]),
        ['typeChanged::breaking'], ['typeChanged::breaking']);

    _both(
      'slower than the baseline allows',
      response({'a': 1}, ms: 100),
      response({'a': 1}, ms: 600),
      ['slower::nonBreaking'],
      const [], // 600 ms recorded allows 1800 ms
    );
  });

  group('latency', () {
    final baseline = BaselineRecorder.record(response({'a': 1}, ms: 100));

    test('up to the limit (three times, never under 500 ms) is fine, one millisecond over is reported', () {
      expect(DriftDetector.compare(baseline, response({'a': 1}, ms: 500)).changes, isEmpty);
      expect(_summary(DriftDetector.compare(baseline, response({'a': 1}, ms: 501))), ['slower::nonBreaking']);
    });

    test('the message says how slow and what the baseline had', () {
      final change = DriftDetector.compare(baseline, response({'a': 1}, ms: 900)).changes.single;
      expect(change.message, 'The response took 900 ms; the baseline took 100 ms, and more than 500 ms is reported.');
    });
  });

  group('messages say what changed in words', () {
    test('field, type, null, enum and status messages', () {
      String message(ApiResponseEntity base, ApiResponseEntity now) => DriftDetector.compare(BaselineRecorder.record(base), now).changes.first.message;
      expect(message(response({'a': 1, 'b': 'x'}), response({'a': 1})), 'body.b was removed.');
      expect(message(response({'n': 1}), response({'n': '1'})), 'body.n changed from integer to string.');
      expect(message(response({'v': 'a'}), response({'v': null})), 'body.v is null; the baseline never had null here.');
      expect(message(response({'a': 1}), response({'a': 1, 'b': true})), 'body.b is new (boolean).');
      expect(message(response({'a': 1}), response({'a': 1}, status: 503)),
          'Status changed from 200 to 503 (2xx to 5xx). The rest of the response is not compared until the status is back in the same class.');
      expect(message(response({'a': 1}), response('')), 'The body is empty now; the baseline had a JSON body.');
    });

    test('an enumeration message lists the values', () {
      final base = response({
        'items': [for (final s in ['a', 'b', 'a', 'b']) {'status': s}],
      });
      final now = response({
        'items': [for (final s in ['a', 'a', 'a', 'a']) {'status': s}],
      });
      expect(DriftDetector.compare(BaselineRecorder.record(base), now).changes.single.message,
          '"b" no longer appears in body.items[*].status; the baseline had "a", "b".');
    });
  });

  group('volatile paths from a second response', () {
    final first = {'queueDepth': 12, 'requestId': 111, 'name': 'x'};
    final second = {'queueDepth': 15, 'requestId': 222, 'name': 'x'};

    test('without a probe, a counter that is not recognised by name is compared', () {
      final baseline = BaselineRecorder.record(response(first));
      expect(baseline.values.keys, containsAll(['queueDepth', 'name']));
      expect(baseline.values.containsKey('requestId'), isFalse, reason: 'recognised as an id');
      expect(_summary(DriftDetector.compare(baseline, response({...second, 'queueDepth': 99}))), ['valueChanged:queueDepth:info']);
    });

    test('with a probe, what changed between the two is never compared', () {
      final baseline = BaselineRecorder.record(response(first), stability: StabilityProbe.compare(first, second));
      expect(baseline.volatile, {'queueDepth', 'requestId'});
      expect(baseline.values.keys, ['name']);
      expect(DriftDetector.compare(baseline, response({...second, 'queueDepth': 99})).changes, isEmpty);
      expect(_summary(DriftDetector.compare(baseline, response({...second, 'name': 'y'}))), ['valueChanged:name:info']);
    });

    test('accepting keeps the volatile paths', () {
      final baseline = BaselineRecorder.record(response(first), stability: StabilityProbe.compare(first, second));
      final current = response({...second, 'name': 'y'});
      final accepted = DriftAccept.apply(baseline, current, DriftDetector.compare(baseline, current).changes);
      expect(accepted.volatile, baseline.volatile);
      expect(accepted.values['name'], 'y');
    });
  });

  group('a realistic API change', () {
    // Orders v2: total became a string, email left, discount arrived, "shipped" turned into "refunded".
    Map<String, dynamic> v2() {
      final body = ordersBody();
      final orders = ((body['data'] as Map)['orders'] as List).cast<Map<String, dynamic>>();
      for (final order in orders) {
        order['total'] = '${order['total']}';
        order.remove('email');
        order['discount'] = 0;
      }
      orders[2]['status'] = 'refunded';
      return body;
    }

    final baseline = BaselineRecorder.record(response(ordersBody()));
    final report = DriftDetector.compare(baseline, response(v2()));

    test('is told apart as breaking and non-breaking', () {
      expect(_summary(report), [
        'typeChanged:data.orders[].total:breaking',
        'fieldRemoved:data.orders[].email:breaking',
        'enumValueGone:data.orders[].status:breaking',
        'fieldAdded:data.orders[].discount:nonBreaking',
        'enumValueAdded:data.orders[].status:nonBreaking',
      ]);
      expect(report.breaking, 3);
      expect(report.nonBreaking, 2);
      expect(report.info, 0);
      expect(report.verdict, DriftVerdict.breaking);
      expect(report.changes.first.message, 'body.data.orders[*].total changed from integer or number to string.');
    });

    test('accepting one change leaves the others', () {
      final remaining = DriftAccept.apply(baseline, response(v2()), [report.changes[1]]); // the removed email
      expect(_summary(DriftDetector.compare(remaining, response(v2()))), [
        'typeChanged:data.orders[].total:breaking',
        'enumValueGone:data.orders[].status:breaking',
        'fieldAdded:data.orders[].discount:nonBreaking',
        'enumValueAdded:data.orders[].status:nonBreaking',
      ]);
    });

    test('accepting a new field takes it with everything below it', () {
      final body = {'a': 1, 'extra': {'deep': {'x': 1}, 'list': [1]}};
      final base = BaselineRecorder.record(response({'a': 1}));
      final report = DriftDetector.compare(base, response(body));
      expect(_summary(report), ['fieldAdded:extra:nonBreaking'], reason: 'one change for the new subtree, not one per path');
      final accepted = DriftAccept.apply(base, response(body), report.changes);
      expect(accepted.fields.keys, containsAll(['extra', 'extra.deep', 'extra.deep.x', 'extra.list', 'extra.list[]']));
    });

    test('accepting everything makes the response the baseline', () {
      final accepted = DriftAccept.apply(baseline, response(v2()), report.changes);
      expect(DriftDetector.compare(accepted, response(v2())).changes, isEmpty);
    });

    test('accepting a status class change takes the whole new answer, so there is no cascade of body changes', () {
      final error = response({'error': 'down'}, status: 503, ms: 80);
      final classChange = DriftDetector.compare(baseline, error);
      expect(_summary(classChange), ['statusClassChanged::breaking']);
      final accepted = DriftAccept.apply(baseline, error, classChange.changes);
      expect(accepted.status, 503);
      expect(accepted.fields.keys, ['', 'error']);
      expect(DriftDetector.compare(accepted, error).changes, isEmpty);
    });
  });

  group('reports', () {
    test('are ordered most serious first and counted by severity', () {
      final base = response({'a': 1, 'b': 'x', 'c': {'d': 1}}, ms: 100);
      final now = response({'a': '1', 'c': <String, Object?>{}}, status: 201, ms: 700);
      final report = DriftDetector.compare(BaselineRecorder.record(base), now);
      expect(_summary(report), [
        'typeChanged:a:breaking',
        'fieldRemoved:b:breaking',
        'fieldRemoved:c.d:breaking',
        'statusChanged::nonBreaking',
        'slower::nonBreaking',
      ]);
      expect((report.breaking, report.nonBreaking, report.info), (3, 2, 0));
      expect(report.ofSeverity(DriftSeverity.nonBreaking).map((c) => c.kind), [DriftKind.statusChanged, DriftKind.slower]);
      expect(DriftReport.clean.verdict, DriftVerdict.clean);
      expect(DriftReport.clean.isClean, isTrue);
    });

    test('accepting some of a mixed report leaves exactly the rest', () {
      final base = response({'a': 1, 'b': 'x', 'c': {'d': 1}}, ms: 100);
      final now = response({'a': '1', 'c': <String, Object?>{}}, status: 201, ms: 700);
      final baseline = BaselineRecorder.record(base);
      final report = DriftDetector.compare(baseline, now);
      final partly = DriftAccept.apply(baseline, now, report.changes.where((c) => c.kind == DriftKind.typeChanged));
      expect(_summary(DriftDetector.compare(partly, now)), [
        'fieldRemoved:b:breaking',
        'fieldRemoved:c.d:breaking',
        'statusChanged::nonBreaking',
        'slower::nonBreaking',
      ]);
      final rest = DriftAccept.apply(partly, now, DriftDetector.compare(partly, now).changes.where((c) => c.severity != DriftSeverity.breaking));
      expect(_summary(DriftDetector.compare(rest, now)), ['fieldRemoved:b:breaking', 'fieldRemoved:c.d:breaking']);
    });

    test('a change has a stable id', () {
      final report = DriftDetector.compare(BaselineRecorder.record(response({'a': 1})), response({}));
      expect(report.changes.single.id, 'fieldRemoved|a');
    });
  });

  group('the snapshot', () {
    test('survives being stored: every part reads back the same', () {
      final snapshot = BaselineRecorder.record(response(ordersBody(), headers: const {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store',
        'Deprecation': 'true',
      }));
      final back = BaselineSnapshot.decode(snapshot.encode())!;
      expect(jsonEncode(back.toJson()), jsonEncode(snapshot.toJson()));
      expect(back.fields['data.orders[].note'], const BaselineField({'null', 'string'}));
      expect(back.enums['data.orders[].status'], const BaselineEnum(['paid', 'shipped'], 4));
      expect(back.headers, {'content-type': 'application/json', 'cache-control': 'no-store', 'deprecation': 'present'});
      expect(back.values['currency'], 'USD');
      expect(back.values.containsKey('requestId'), isFalse);
    });

    test('what it keeps: stable scalars outside arrays, enumerations, no ids or tokens', () {
      final snapshot = BaselineRecorder.record(response(ordersBody()));
      expect(snapshot.values, {'data.page': 1, 'currency': 'USD', 'queueDepth': 12, 'ok': true});
      expect(snapshot.enums.keys, ['data.orders[].status']);
      expect(snapshot.timeMs, 120);
      expect(snapshot.status, 200);
      expect(snapshot.isJson, isTrue);
      expect(snapshot.summary, 'status 200 · 16 fields · 120 ms');
    });

    test('reading tolerates damage: wrong types fall back, garbage is no snapshot', () {
      expect(BaselineSnapshot.decode('not json'), isNull);
      expect(BaselineSnapshot.decode('[1,2]'), isNull);
      final odd = BaselineSnapshot.decode('{"status":"200","fields":{"a":{"t":"string"}},"values":{"x":[1],"y":2},"enums":{"e":{"values":"no"}}}')!;
      expect(odd.status, 0);
      expect(odd.fields['a']!.types, isEmpty);
      expect(odd.values, {'y': 2});
      expect(odd.enums, isEmpty);
    });

    test('a body that is not JSON records only status, headers and time', () {
      final snapshot = BaselineRecorder.record(response('<html></html>', headers: const {'Content-Type': 'text/html'}));
      expect(snapshot.isJson, isFalse);
      expect(snapshot.fields, isEmpty);
      expect(snapshot.headers, {'content-type': 'text/html'});
    });

    test('a very wide body is described by its first paths and flagged', () {
      final wide = {for (var i = 0; i < BaselineRecorder.maxPaths + 50; i++) 'k$i': i};
      final snapshot = BaselineRecorder.record(response(wide));
      expect(snapshot.fields.length, BaselineRecorder.maxPaths);
      expect(snapshot.shapeTruncated, isTrue);
    });
  });
}
