import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/response_tools/domain/services/response_history.dart';

ApiResponseEntity _response(int bytes, {int status = 200}) => ApiResponseEntity(
      statusCode: status,
      statusMessage: 'OK',
      headers: const {},
      bodyBytes: Uint8List(bytes),
      duration: Duration.zero,
    );

void main() {
  test('keeps eight responses per request, newest first, and counts their bytes', () {
    final history = ResponseHistory(maxTotalBytes: 1 << 30);
    final all = [for (var i = 0; i < 10; i++) _response(10 + i)];
    for (final r in all) {
      history.record(1, r);
    }
    expect(history.of(1), all.reversed.take(8).toList());
    // 10 + 11 are gone; 12..19 remain: 12+13+14+15+16+17+18+19.
    expect(history.totalBytes, 124);
  });

  test('the same response recorded twice is stored and counted once', () {
    final history = ResponseHistory();
    final r = _response(100);
    history.record(1, r);
    history.record(1, r);
    expect(history.of(1), hasLength(1));
    expect(history.totalBytes, 100);
  });

  test('over the byte limit the oldest responses of any request go first', () {
    final history = ResponseHistory(maxTotalBytes: 100);
    final a1 = _response(40);
    final b1 = _response(40);
    final a2 = _response(40);
    history
      ..record(1, a1)
      ..record(2, b1);
    expect(history.totalBytes, 80);
    history.record(1, a2); // 120 > 100: the oldest overall (a1) is dropped, not request 2's.
    expect(history.of(1), [a2]);
    expect(history.of(2), [b1]);
    expect(history.totalBytes, 80);
    expect(history.receivedAt(a1), isNull);
  });

  test('a response larger than the whole limit is kept alone, after everything older is dropped', () {
    final history = ResponseHistory(maxTotalBytes: 100)
      ..record(1, _response(30))
      ..record(2, _response(30));
    final huge = _response(500);
    history.record(3, huge);
    expect(history.of(3), [huge]);
    expect(history.of(1), isEmpty);
    expect(history.of(2), isEmpty);
    expect(history.totalBytes, 500);
    // The next response pushes the huge one out.
    final small = _response(10);
    history.record(3, small);
    expect(history.of(3), [small]);
    expect(history.totalBytes, 10);
  });

  test('forget gives the bytes back', () {
    final history = ResponseHistory()
      ..record(1, _response(70))
      ..record(1, _response(30))
      ..record(2, _response(5));
    history.forget(1);
    expect(history.of(1), isEmpty);
    expect(history.of(2), hasLength(1));
    expect(history.totalBytes, 5);
    history.forget(1); // nothing left: harmless
    history.forget(99);
    expect(history.totalBytes, 5);
  });

  test('retainOnly forgets every request that is not open any more', () {
    final history = ResponseHistory()
      ..record(1, _response(10))
      ..record(2, _response(20))
      ..record(3, _response(30));
    history.retainOnly([1, 3, 42]);
    expect(history.of(1), hasLength(1));
    expect(history.of(2), isEmpty);
    expect(history.of(3), hasLength(1));
    expect(history.totalBytes, 40);
    history.retainOnly(const []);
    expect(history.totalBytes, 0);
    expect(history.of(1), isEmpty);
  });

  test('the default limit is 64 MB', () {
    expect(ResponseHistory().maxTotalBytes, 64 * 1024 * 1024);
  });
}
