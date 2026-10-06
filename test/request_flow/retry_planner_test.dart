import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_report.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/services/retry_planner.dart';
import 'flow_support.dart';

void main() {
  group('StatusTokens', () {
    test('accepts a code from 100 to 599 and the classes 4xx and 5xx, in any case', () {
      expect(StatusTokens.normalize('429'), '429');
      expect(StatusTokens.normalize(' 5XX '), '5xx');
      expect(StatusTokens.normalize('4xx'), '4xx');
      expect(StatusTokens.normalize('100'), '100');
      expect(StatusTokens.normalize('599'), '599');
    });

    test('refuses anything else', () {
      for (final text in ['', '99', '600', '2xx', '3xx', '5x', 'abc', '42 9', '5xxx']) {
        expect(StatusTokens.normalize(text), isNull, reason: '"$text"');
      }
    });

    test('a list is split on commas, spaces and semicolons, with duplicates and rubbish dropped', () {
      expect(StatusTokens.parseList('409, 425; 4xx  409 nonsense 5XX'), ['409', '425', '4xx', '5xx']);
      expect(StatusTokens.parseList(''), isEmpty);
    });

    test('a class matches its hundred, a code only itself', () {
      expect(StatusTokens.matches('5xx', 500), isTrue);
      expect(StatusTokens.matches('5xx', 599), isTrue);
      expect(StatusTokens.matches('5xx', 499), isFalse);
      expect(StatusTokens.matches('5xx', 600 - 101), isFalse);
      expect(StatusTokens.matches('429', 429), isTrue);
      expect(StatusTokens.matches('429', 430), isFalse);
    });
  });

  group('the wait before a retry (planned by hand: delay, doubling, ceiling, jitter)', () {
    const exponential = RetryPolicy(delayMs: 500, maxDelayMs: 3000, jitter: false);

    test('exponential doubles from the first wait and stops at the ceiling', () {
      final waits = [for (var n = 1; n <= 6; n++) RetryPlanner.plannedWait(exponential, n).inMilliseconds];

      // 500, 1000, 2000, then 4000 is above 3000, so 3000 from there on.
      expect(waits, [500, 1000, 2000, 3000, 3000, 3000]);
    });

    test('fixed is the same every time, whatever the ceiling', () {
      const fixed = RetryPolicy(backoff: BackoffKind.fixed, delayMs: 750, maxDelayMs: 100, jitter: false);

      expect([for (var n = 1; n <= 4; n++) RetryPlanner.plannedWait(fixed, n).inMilliseconds], [750, 750, 750, 750]);
    });

    test('jitter takes 50 to 100 percent of the planned wait', () {
      const jittered = RetryPolicy(delayMs: 1000, maxDelayMs: 30000);

      expect(RetryPlanner.plannedWait(jittered, 1, randomValue: 0).inMilliseconds, 500);
      expect(RetryPlanner.plannedWait(jittered, 1, randomValue: 0.5).inMilliseconds, 750);
      expect(RetryPlanner.plannedWait(jittered, 1, randomValue: 1).inMilliseconds, 1000);
      // The second retry plans 2000 ms first.
      expect(RetryPlanner.plannedWait(jittered, 2, randomValue: 0).inMilliseconds, 1000);
      expect(RetryPlanner.plannedWait(jittered, 2, randomValue: 0.25).inMilliseconds, 1250);
    });

    test('a first wait of 0 stays 0, however often it doubles', () {
      const none = RetryPolicy(delayMs: 0, jitter: false);

      expect(RetryPlanner.plannedWait(none, 5), Duration.zero);
    });
  });

  group('Retry-After', () {
    final now = DateTime.utc(2015, 10, 21, 7, 28);

    test('is a number of seconds', () {
      expect(RetryAfter.parse('120', now), const Duration(seconds: 120));
      expect(RetryAfter.parse(' 7 ', now), const Duration(seconds: 7));
      expect(RetryAfter.parse('0', now), Duration.zero);
    });

    test('is an HTTP date, counted from now', () {
      expect(RetryAfter.parse('Wed, 21 Oct 2015 07:28:30 GMT', now), const Duration(seconds: 30));
      expect(RetryAfter.parse('Wed, 21 Oct 2015 08:28:00 GMT', now), const Duration(hours: 1));
    });

    test('a date in the past is no wait', () {
      expect(RetryAfter.parse('Wed, 21 Oct 2015 07:27:00 GMT', now), Duration.zero);
    });

    test('anything unreadable is nothing, so the planned wait stands', () {
      for (final text in [null, '', '   ', '-5', '1.5', 'soon', 'Wed, 99 Foo 2015 07:28:00 GMT', '12345678901']) {
        expect(RetryAfter.parse(text, now), isNull, reason: '$text');
      }
    });
  });

  group('the decision after a try', () {
    final now = DateTime.utc(2026, 1, 1);
    RetryPlanner planner(RetryPolicy policy, [double randomValue = 1]) => RetryPlanner(policy, () => randomValue);

    RetryDecision decide(
      RetryPlanner planner,
      FlowExchange exchange, {
      int attempt = 1,
      Duration elapsed = Duration.zero,
    }) =>
        planner.decide(attempt: attempt, exchange: exchange, elapsed: elapsed, now: now);

    const policy = RetryPolicy(maxRetries: 2, delayMs: 100, jitter: false);

    test('retries a 5xx and a 429, after the planned wait', () {
      final p = planner(policy);

      expect((decide(p, responded(textResponse('', status: 503))) as RetryWait).wait, const Duration(milliseconds: 100));
      expect((decide(p, responded(textResponse('', status: 429)), attempt: 2) as RetryWait).wait, const Duration(milliseconds: 200));
    });

    test('does not retry a success, a 404 or a redirect', () {
      final p = planner(policy);

      for (final status in [200, 201, 302, 404, 401]) {
        final decision = decide(p, responded(textResponse('', status: status)));
        expect(decision, isA<RetryStop>(), reason: '$status');
        expect((decision as RetryStop).note, isNull);
      }
    });

    test('a network failure is retried only when the policy says so', () {
      expect(decide(planner(policy), failed()), isA<RetryWait>());
      expect(decide(planner(policy.copyWith(onNetworkError: false)), failed()), isA<RetryStop>());
    });

    test('custom codes and classes are honoured', () {
      final p = planner(policy.copyWith(statuses: const ['409', '4xx']));

      expect(decide(p, responded(textResponse('', status: 409))), isA<RetryWait>());
      expect(decide(p, responded(textResponse('', status: 418))), isA<RetryWait>());
      expect(decide(p, responded(textResponse('', status: 503))), isA<RetryStop>());
    });

    test('gives up after the last attempt and says so', () {
      final p = planner(policy); // 2 retries = 3 attempts

      final decision = decide(p, responded(textResponse('', status: 500)), attempt: 3);

      expect((decision as RetryStop).note, 'gave up after 3 attempts');
    });

    test('Retry-After replaces the planned wait, jitter or not', () {
      final p = planner(policy.copyWith(jitter: true, delayMs: 1000), 0);
      final answer = responded(textResponse('', status: 429, headers: const {'Retry-After': '5'}));

      expect((decide(p, answer) as RetryWait).wait, const Duration(seconds: 5));
    });

    test('Retry-After is looked up in any case of the header name', () {
      final answer = responded(textResponse('', status: 503, headers: const {'retry-after': '3'}));

      expect((decide(planner(policy), answer) as RetryWait).wait, const Duration(seconds: 3));
    });

    test('Retry-After is ignored when the policy does not honour it', () {
      final p = planner(policy.copyWith(honourRetryAfter: false));
      final answer = responded(textResponse('', status: 429, headers: const {'Retry-After': '30'}));

      expect((decide(p, answer) as RetryWait).wait, const Duration(milliseconds: 100));
    });

    test('a Retry-After past the time limit stops the retries instead of waiting', () {
      final p = planner(policy.copyWith(maxTotalSeconds: 60));
      final answer = responded(textResponse('', status: 429, headers: const {'Retry-After': '120'}));

      final decision = decide(p, answer, elapsed: const Duration(seconds: 10)) as RetryStop;

      expect(decision.note, contains('Retry-After'));
      expect(decision.note, contains('60 s time limit'));
    });

    test('a wait that would pass the time limit stops the retries', () {
      final p = planner(
        const RetryPolicy(maxRetries: 5, backoff: BackoffKind.fixed, delayMs: 40000, jitter: false, maxTotalSeconds: 60),
      );

      // 30 s used, 40 s to wait: 70 s is past the 60 s limit.
      final decision = decide(p, failed(), elapsed: const Duration(seconds: 30)) as RetryStop;

      expect(decision.note, contains('time limit'));
      // 15 s used: 55 s is inside it.
      expect(decide(p, failed(), elapsed: const Duration(seconds: 15)), isA<RetryWait>());
    });
  });

  group('RepeatSafety', () {
    test('GET, HEAD, OPTIONS and PUT are repeated freely; POST, PATCH and DELETE need a tick', () {
      for (final method in [HttpMethod.get, HttpMethod.head, HttpMethod.options, HttpMethod.put]) {
        expect(RepeatSafety.needsConfirmation(method), isFalse, reason: method.label);
        expect(RepeatSafety.blockedReason(method, const FlowSettings()), isNull, reason: method.label);
      }
      for (final method in [HttpMethod.post, HttpMethod.patch, HttpMethod.delete]) {
        expect(RepeatSafety.needsConfirmation(method), isTrue, reason: method.label);
        expect(RepeatSafety.blockedReason(method, const FlowSettings()), contains(method.label), reason: method.label);
        expect(RepeatSafety.blockedReason(method, const FlowSettings(repeatUnsafe: true)), isNull, reason: method.label);
      }
    });
  });
}
