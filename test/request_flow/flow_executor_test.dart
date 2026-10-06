// Retry and poll through the engine, on a fake server and a clock that only moves when the engine waits.
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/errors/app_exception.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_report.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/entities/pagination_settings.dart';
import 'package:postpilot/features/request_flow/domain/services/flow_clock.dart';
import 'package:postpilot/features/request_flow/domain/services/flow_executor.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'flow_support.dart';

AssertionEntity _statusIsDone([String expected = 'done']) =>
    AssertionEntity(type: AssertionType.jsonPathEquals, path: 'status', expected: expected);

void main() {
  late FakeFlowClock clock;
  late FlowExecutor executor;
  late List<String> notes;

  setUp(() {
    clock = FakeFlowClock();
    executor = FlowExecutor(clock: clock, random: () => 1);
    notes = [];
  });

  Future<FlowOutcome> run(
    FakeServer server, {
    FlowSettings flow = const FlowSettings(),
    PaginationSettings pagination = const PaginationSettings(),
    HttpMethod method = HttpMethod.get,
    Map<String, String> variables = const {},
  }) =>
      executor.execute(
        request: flowRequest(method: method),
        flow: flow,
        pagination: pagination,
        send: server.send,
        context: flowContext(variables: variables, notes: notes),
      );

  group('retry', () {
    const retry = RetryPolicy(enabled: true, maxRetries: 2, backoff: BackoffKind.fixed, delayMs: 1200, jitter: false);
    const flow = FlowSettings(retry: retry);

    test('sends again after a 503 until it works, and says "attempt 2/3 after 1.2 s"', () async {
      final server = FakeServer((url, request, call) => call < 3 ? responded(textResponse('', status: 503)) : responded(jsonResponse({'ok': true})));

      final outcome = await run(server, flow: flow);

      expect(outcome.response!.statusCode, 200);
      expect(outcome.error, isNull);
      expect(server.requests, hasLength(3));
      expect(clock.waits, [1200, 1200]);
      expect(outcome.report.retries, 2);
      expect([for (final a in outcome.report.attempts) a.label], ['request', 'attempt 2/3 after 1.2 s', 'attempt 3/3 after 1.2 s']);
      expect([for (final a in outcome.report.attempts) a.status], [503, 503, 200]);
      expect(outcome.report.summary, '3 attempts');
      // The console hears about every try after the first, before it is sent.
      expect(notes, ['attempt 2/3 after 1.2 s', 'attempt 3/3 after 1.2 s']);
    });

    test('exponential waits double: 500, 1000, 2000 ms', () async {
      final server = FakeServer((url, request, call) => call < 4 ? failed() : responded(jsonResponse({})));
      const policy = RetryPolicy(enabled: true, maxRetries: 3, delayMs: 500, maxDelayMs: 30000, jitter: false);

      final outcome = await run(server, flow: const FlowSettings(retry: policy));

      expect(clock.waits, [500, 1000, 2000]);
      expect(outcome.response!.statusCode, 200);
      expect([for (final a in outcome.report.attempts) a.label], [
        'request',
        'attempt 2/4 after 500 ms',
        'attempt 3/4 after 1 s',
        'attempt 4/4 after 2 s',
      ]);
    });

    test('the report in words names the retries, and cuts a long list after three', () async {
      final server = FakeServer((url, request, call) => responded(textResponse('', status: 503)));
      const policy = RetryPolicy(enabled: true, maxRetries: 5, backoff: BackoffKind.fixed, delayMs: 100, jitter: false);

      final outcome = await run(server, flow: const FlowSettings(retry: policy));

      expect(outcome.report.summary, '6 attempts');
      expect(
        outcome.report.detailed,
        '6 attempts: attempt 2/6 after 100 ms, attempt 3/6 after 100 ms, attempt 4/6 after 100 ms, …',
      );
      expect([for (final a in outcome.report.attempts) a.isRetry], [false, true, true, true, true, true]);
    });

    test('jitter takes 50 to 100 percent of each planned wait (random drawn at 0.5 here)', () async {
      executor = FlowExecutor(clock: clock, random: () => 0.5);
      final server = FakeServer((url, request, call) => call < 3 ? failed() : responded(jsonResponse({})));
      const policy = RetryPolicy(enabled: true, maxRetries: 3, delayMs: 1000, jitter: true);

      await run(server, flow: const FlowSettings(retry: policy));

      // 1000 * 0.75 and 2000 * 0.75.
      expect(clock.waits, [750, 1500]);
    });

    test('gives up after the last attempt: the last response comes back with a note', () async {
      final server = FakeServer((url, request, call) => responded(textResponse('', status: 500)));

      final outcome = await run(server, flow: flow);

      expect(outcome.response!.statusCode, 500);
      expect(outcome.error, isNull);
      expect(server.requests, hasLength(3));
      expect(outcome.report.notes, ['gave up after 3 attempts']);
      expect(outcome.report.failure, isNull, reason: 'the 500 itself fails the request, as without a retry');
    });

    test('a request that never gets an answer ends with the same error a plain send throws', () async {
      final error = StateError('connection refused');
      final server = FakeServer((url, request, call) => FlowFailed(error, 'connection refused'));

      final outcome = await run(server, flow: flow);

      expect(outcome.response, isNull);
      expect(identical(outcome.error, error), isTrue);
      expect(outcome.report.attempts, hasLength(3));
      expect(outcome.report.attempts.last.error, 'connection refused');
    });

    test('a 404 is an answer, not a failure to retry', () async {
      final server = FakeServer((url, request, call) => responded(textResponse('', status: 404)));

      final outcome = await run(server, flow: flow);

      expect(server.requests, hasLength(1));
      expect(outcome.report.retries, 0);
      expect(clock.sleeps, isEmpty);
    });

    test('Retry-After decides the wait', () async {
      final server = FakeServer((url, request, call) => call == 1
          ? responded(textResponse('', status: 429, headers: const {'Retry-After': '5'}))
          : responded(jsonResponse({})));

      await run(server, flow: flow);

      expect(clock.waits, [5000]);
    });

    test('a total time limit ends the retries early', () async {
      final server = FakeServer((url, request, call) => responded(textResponse('', status: 503)));
      const policy = RetryPolicy(
        enabled: true,
        maxRetries: 10,
        backoff: BackoffKind.fixed,
        delayMs: 2000,
        jitter: false,
        maxTotalSeconds: 3,
      );

      final outcome = await run(server, flow: const FlowSettings(retry: policy));

      // Try 1, wait 2 s, try 2 (2 s used); another 2 s wait would be 4 s, past 3 s.
      expect(server.requests, hasLength(2));
      expect(outcome.report.notes.single, contains('3 s time limit'));
    });

    test('POST, PATCH and DELETE are sent once, with a note, unless the person said repeating is safe', () async {
      for (final method in [HttpMethod.post, HttpMethod.patch, HttpMethod.delete]) {
        final server = FakeServer((url, request, call) => responded(textResponse('', status: 503)));

        final outcome = await run(server, flow: flow, method: method);

        expect(server.requests, hasLength(1), reason: method.label);
        expect(outcome.report.notes.single, contains(method.label), reason: method.label);
        expect(outcome.report.notes.single, contains('I know repeating this request is safe'), reason: method.label);

        final ticked = FakeServer((url, request, call) => responded(textResponse('', status: 503)));
        await run(ticked, flow: flow.copyWith(repeatUnsafe: true), method: method);
        expect(ticked.requests, hasLength(3), reason: '${method.label} ticked');
      }
    });

    test('PUT and GET are repeated without a tick', () async {
      for (final method in [HttpMethod.put, HttpMethod.get, HttpMethod.head]) {
        final server = FakeServer((url, request, call) => responded(textResponse('', status: 503)));

        await run(server, flow: flow, method: method);

        expect(server.requests, hasLength(3), reason: method.label);
      }
    });

    test('a retry that is off does nothing at all', () async {
      final server = FakeServer((url, request, call) => responded(textResponse('', status: 503)));

      final outcome = await run(server, flow: FlowSettings(retry: retry.copyWith(enabled: false)));

      expect(server.requests, hasLength(1));
      expect(outcome.report.isNoteworthy, isFalse);
    });

    test('Stop during a wait ends the flow as a cancelled request', () async {
      final token = ApiCancelToken();
      final cancelling = _CancelOnSleep(token);
      executor = FlowExecutor(clock: cancelling);
      final server = FakeServer((url, request, call) => responded(textResponse('', status: 503)));

      final result = executor.execute(
        request: flowRequest(),
        flow: flow,
        pagination: const PaginationSettings(),
        send: server.send,
        context: flowContext(cancel: token),
      );

      await expectLater(
        result,
        throwsA(isA<NetworkException>().having((e) => e.kind, 'kind', NetworkErrorKind.cancelled)),
      );
      expect(server.requests, hasLength(1), reason: 'no second try after Stop');
    });

    test('a request that cannot be sent at all (blocked) is not retried and ends the flow', () async {
      var calls = 0;

      final result = executor.execute(
        request: flowRequest(),
        flow: flow,
        pagination: const PaginationSettings(),
        send: (request) async {
          calls++;
          throw const FlowBlocked('Refused by the production lock');
        },
        context: flowContext(),
      );

      await expectLater(result, throwsA(isA<FlowBlocked>()));
      expect(calls, 1);
    });
  });

  group('poll until', () {
    PollPolicy poll({
      List<AssertionEntity>? until,
      int intervalMs = 2000,
      int maxAttempts = 30,
      int maxSeconds = 120,
    }) =>
        PollPolicy(enabled: true, until: until ?? [_statusIsDone()], intervalMs: intervalMs, maxAttempts: maxAttempts, maxSeconds: maxSeconds);

    FakeServer job(List<String> states) => FakeServer((url, request, call) {
          final state = states[(call - 1).clamp(0, states.length - 1)];
          return responded(jsonResponse({'status': state}));
        });

    test('asks again every interval until the condition holds, and counts the polls', () async {
      final server = job(['queued', 'running', 'done']);

      final outcome = await run(server, flow: FlowSettings(poll: poll()));

      expect(server.requests, hasLength(3));
      expect(clock.waits, [2000, 2000]);
      expect(outcome.report.polls, 3);
      expect(outcome.report.pollSatisfied, isTrue);
      expect(outcome.report.failure, isNull);
      expect(outcome.report.summary, 'polled 3 times');
      expect([for (final a in outcome.report.attempts) a.label], ['request', 'poll 2/30 after 2 s', 'poll 3/30 after 2 s']);
      expect(notes, ['poll 2/30 after 2 s', 'poll 3/30 after 2 s']);
      expect(outcome.response!.bodyBytes, isNotEmpty);
    });

    test('the response is the final one', () async {
      final server = job(['running', 'done']);

      final outcome = await run(server, flow: FlowSettings(poll: poll()));

      expect(String.fromCharCodes(outcome.response!.bodyBytes), '{"status":"done"}');
    });

    test('a condition that holds at once means no waiting and one request', () async {
      final server = job(['done']);

      final outcome = await run(server, flow: FlowSettings(poll: poll()));

      expect(server.requests, hasLength(1));
      expect(clock.sleeps, isEmpty);
      expect(outcome.report.polls, 1);
      expect(outcome.report.pollSatisfied, isTrue);
      expect(outcome.report.summary, 'condition held on the first try');
      expect(outcome.report.isNoteworthy, isFalse, reason: 'nothing to show beyond a plain send');
    });

    test('gives up after the allowed number of requests, with the last response and what it waited for', () async {
      final server = job(['running']);

      final outcome = await run(server, flow: FlowSettings(poll: poll(maxAttempts: 3)));

      expect(server.requests, hasLength(3));
      expect(clock.waits, [2000, 2000]);
      expect(outcome.report.polls, 3);
      expect(outcome.report.pollSatisfied, isFalse);
      final failure = outcome.report.failure!;
      expect(failure, contains('Polling gave up after 3 requests'));
      expect(failure, contains('status equals done (got running)'));
      expect(failure, contains('The last response is shown'));
      expect(String.fromCharCodes(outcome.response!.bodyBytes), '{"status":"running"}');
      expect(outcome.failed, isTrue);
    });

    test('gives up when the next wait would pass the time limit', () async {
      final server = job(['running']);

      final outcome = await run(server, flow: FlowSettings(poll: poll(maxSeconds: 5)));

      // Polls at 0 s, 2 s and 4 s; after the third, 4 s + 2 s is past 5 s.
      expect(server.requests, hasLength(3));
      expect(outcome.report.failure, contains('in 4 s'));
      expect(outcome.report.failure, contains('5 s'));
    });

    test('values of a condition can use {{variables}}', () async {
      final server = job(['running', 'finished']);

      final outcome = await run(
        server,
        flow: FlowSettings(poll: poll(until: [_statusIsDone('{{target}}')])),
        variables: const {'target': 'finished'},
      );

      expect(outcome.report.pollSatisfied, isTrue);
      expect(server.requests, hasLength(2));
    });

    test('every condition has to hold', () async {
      final server = FakeServer((url, request, call) => responded(jsonResponse({'status': 'done', 'rows': call < 3 ? 0 : 5})));
      final until = [
        _statusIsDone(),
        AssertionEntity(type: AssertionType.jsonPathEquals, path: 'rows', expected: '5'),
      ];

      final outcome = await run(server, flow: FlowSettings(poll: poll(until: until)));

      expect(server.requests, hasLength(3));
      expect(outcome.report.pollSatisfied, isTrue);
    });

    test('a failed status check polls on, since the condition simply does not hold yet', () async {
      final server = FakeServer((url, request, call) => call < 3
          ? responded(textResponse('not ready', status: 202))
          : responded(jsonResponse({'status': 'done'})));

      final outcome = await run(server, flow: FlowSettings(poll: poll()));

      expect(outcome.report.polls, 3);
      expect(outcome.report.pollSatisfied, isTrue);
    });

    test('each poll is retried on its own when retry is on, without counting as another poll', () async {
      final server = FakeServer((url, request, call) => switch (call) {
            1 => responded(jsonResponse({'status': 'running'})),
            2 => responded(textResponse('', status: 503)),
            _ => responded(jsonResponse({'status': 'done'})),
          });
      const retry = RetryPolicy(enabled: true, maxRetries: 3, backoff: BackoffKind.fixed, delayMs: 1000, jitter: false);

      final outcome = await run(server, flow: FlowSettings(poll: poll(), retry: retry));

      expect(server.requests, hasLength(3));
      expect(outcome.report.polls, 2);
      expect(outcome.report.retries, 1);
      expect(clock.waits, [2000, 1000]);
      expect([for (final a in outcome.report.attempts) a.label], [
        'request',
        'poll 2/30 after 2 s',
        'poll 2/30 after 2 s, attempt 2/4 after 1 s',
      ]);
    });

    test('a poll with no condition is left out, with a note', () async {
      final server = job(['running']);

      final outcome = await run(server, flow: const FlowSettings(poll: PollPolicy(enabled: true)));

      expect(server.requests, hasLength(1));
      expect(outcome.report.notes.single, contains('no condition'));
    });

    test('a network failure while polling ends the flow with that error', () async {
      final error = StateError('reset');
      final server = FakeServer((url, request, call) =>
          call == 1 ? responded(jsonResponse({'status': 'running'})) : FlowFailed(error, 'reset'));

      final outcome = await run(server, flow: FlowSettings(poll: poll()));

      expect(outcome.response, isNull);
      expect(identical(outcome.error, error), isTrue);
      expect(outcome.report.polls, 2);
    });

    test('a POST is not polled without the tick', () async {
      final server = job(['running', 'done']);

      final outcome = await run(server, flow: FlowSettings(poll: poll()), method: HttpMethod.post);

      expect(server.requests, hasLength(1));
      expect(outcome.report.notes.single, contains('POST'));
      expect(outcome.report.polls, 0);
    });

    test('Stop during the wait between polls ends the flow as a cancelled request', () async {
      final token = ApiCancelToken();
      executor = FlowExecutor(clock: _CancelOnSleep(token));
      final server = job(['running']);

      final result = executor.execute(
        request: flowRequest(),
        flow: FlowSettings(poll: poll()),
        pagination: const PaginationSettings(),
        send: server.send,
        context: flowContext(cancel: token),
      );

      await expectLater(result, throwsA(isA<NetworkException>()));
      expect(server.requests, hasLength(1));
    });
  });
}

/// A clock whose first wait is when the person presses Stop.
final class _CancelOnSleep implements FlowClock {
  final ApiCancelToken token;
  _CancelOnSleep(this.token);

  @override
  DateTime now() => DateTime.utc(2026);

  @override
  Future<void> sleep(Duration duration, {ApiCancelToken? cancel}) async => token.cancel();
}
