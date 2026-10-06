// The flow and pagination keys of a request's settings: what is stored, what is read back, and what a damaged or
// newer file does to them.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/entities/pagination_settings.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';

FlowSettings _everything() => FlowSettings(
      retry: const RetryPolicy(
        enabled: true,
        maxRetries: 5,
        onNetworkError: false,
        statuses: ['5xx', '409', '4xx'],
        backoff: BackoffKind.fixed,
        delayMs: 250,
        maxDelayMs: 4000,
        jitter: false,
        honourRetryAfter: false,
        maxTotalSeconds: 90,
      ),
      poll: PollPolicy(
        enabled: true,
        until: [
          AssertionEntity(type: AssertionType.jsonPathEquals, path: 'status', expected: 'done'),
          AssertionEntity(type: AssertionType.headerExists, path: 'X-Result'),
          AssertionEntity(type: AssertionType.statusEquals, expected: '200'),
        ],
        intervalMs: 750,
        maxAttempts: 12,
        maxSeconds: 45,
      ),
      runIf: RunIfPolicy(enabled: true, conditions: [
        RunCondition(kind: RunConditionKind.variableEquals, name: 'region', value: 'eu'),
        RunCondition(kind: RunConditionKind.variableNotEmpty, name: 'id'),
        RunCondition(kind: RunConditionKind.environmentIsNot, name: 'Production'),
        RunCondition(kind: RunConditionKind.previousFailed),
      ]),
      alwaysRun: true,
      repeatUnsafe: true,
    );

const _pagination = PaginationSettings(
  enabled: true,
  kind: PaginationKind.offset,
  itemsPath: 'result.records',
  nextPath: 'next',
  hasMorePath: 'has_more',
  param: 'params.offset',
  location: PageParamLocation.body,
  limitParam: 'params.limit',
  totalPath: 'result.length',
  firstPage: 0,
  maxPages: 40,
  delayMs: 150,
  stopOnEmpty: false,
  maxMegabytes: 10,
  countTotal: true,
);

/// Through the same text a database row or a backup file holds.
RequestSettings _roundTrip(RequestSettings settings) =>
    RequestSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>);

void main() {
  group('a request that sets nothing stores nothing', () {
    test('no flow, no pagination: no key at all', () {
      expect(RequestSettings.none.toJson(), isEmpty);
      expect(FlowSettings.none.toJson(), isEmpty);
      expect(FlowSettings.none.isEmpty, isTrue);
      expect(PaginationSettings.none.isEmpty, isTrue);
      expect(RequestSettings.none.isEmpty, isTrue);
      expect(RequestSettings.none.hasOverrides, isFalse);
    });

    test('switching a feature off keeps what was typed but is not what a fresh request has', () {
      final off = const FlowSettings().copyWith(retry: const RetryPolicy(maxRetries: 7));

      expect(off.isEmpty, isFalse, reason: 'the 7 is worth keeping for when it is switched on again');
      expect(off.toJson().keys, ['retry']);
      expect(_roundTrip(RequestSettings(flow: off)).flow.retry.maxRetries, 7);
    });

    test('the defaults of each policy are not written', () {
      expect(const FlowSettings(retry: RetryPolicy(), poll: PollPolicy(), runIf: RunIfPolicy()).toJson(), isEmpty);
      expect(const FlowSettings(alwaysRun: true).toJson(), {'alwaysRun': true});
      expect(const FlowSettings(repeatUnsafe: true).toJson(), {'repeatUnsafe': true});
    });
  });

  group('round trip', () {
    test('every field of flow and pagination survives JSON', () {
      final settings = RequestSettings(flow: _everything(), pagination: _pagination);

      final back = _roundTrip(settings);

      expect(back, settings);
      expect(back.flow.retry.statuses, ['5xx', '409', '4xx']);
      expect(back.flow.poll.until.map((a) => (a.type, a.path, a.expected)), [
        (AssertionType.jsonPathEquals, 'status', 'done'),
        (AssertionType.headerExists, 'X-Result', ''),
        (AssertionType.statusEquals, '', '200'),
      ]);
      expect(back.flow.runIf.conditions.map((c) => (c.kind, c.name, c.value)), [
        (RunConditionKind.variableEquals, 'region', 'eu'),
        (RunConditionKind.variableNotEmpty, 'id', ''),
        (RunConditionKind.environmentIsNot, 'Production', ''),
        (RunConditionKind.previousFailed, '', ''),
      ]);
      expect(back.pagination.location, PageParamLocation.body);
      expect(back.hashCode, settings.hashCode);
    });

    test('the four overrides of the global settings travel with them', () {
      final settings = RequestSettings(
        followRedirects: false,
        verifySsl: false,
        timeoutSeconds: 3,
        sendNoCacheHeader: true,
        flow: _everything(),
        pagination: _pagination,
      );

      expect(_roundTrip(settings), settings);
    });

    test('the keys are `flow` and `pagination` next to the old ones, as plain JSON', () {
      final json = RequestSettings(verifySsl: false, flow: _everything(), pagination: _pagination).toJson();

      expect(json.keys, ['verifySsl', 'flow', 'pagination']);
      final flow = json['flow'] as Map;
      expect(flow.keys, containsAll(['retry', 'poll', 'runIf', 'alwaysRun', 'repeatUnsafe']));
      expect((flow['retry'] as Map)['backoff'], 'fixed');
      expect(((flow['poll'] as Map)['until'] as List).first, {'type': 'jsonPathEquals', 'path': 'status', 'expected': 'done'});
      expect(((flow['runIf'] as Map)['all'] as List).first, {'kind': 'variableEquals', 'name': 'region', 'value': 'eu'});
      expect((json['pagination'] as Map)['kind'], 'offset');
      expect(() => jsonEncode(json), returnsNormally);
    });

    test('changing a classic override leaves flow and pagination alone', () {
      final settings = RequestSettings(flow: _everything(), pagination: _pagination);

      for (final changed in [
        settings.withFollowRedirects(false),
        settings.withVerifySsl(false),
        settings.withTimeoutSeconds(5),
        settings.withSendNoCacheHeader(true),
      ]) {
        expect(changed.flow, settings.flow);
        expect(changed.pagination, settings.pagination);
      }
      expect(settings.withFlow(const FlowSettings()).pagination, settings.pagination);
      expect(settings.withPagination(PaginationSettings.none).flow, settings.flow);
    });

    test('"use global for everything" drops the four overrides and keeps flow and pagination', () {
      final settings = RequestSettings(verifySsl: false, timeoutSeconds: 3, flow: _everything(), pagination: _pagination);

      final reset = settings.withoutOverrides();

      expect(reset.hasOverrides, isFalse);
      expect(reset.isEmpty, isFalse);
      expect((reset.flow, reset.pagination), (settings.flow, settings.pagination));
    });

    test('a request with only a flow or only a pagination is not empty', () {
      expect(RequestSettings(flow: _everything()).isEmpty, isFalse);
      expect(const RequestSettings(pagination: _pagination).isEmpty, isFalse);
      expect(RequestSettings(flow: _everything()).hasOverrides, isFalse);
    });
  });

  group('reading what is damaged, hand-edited or from a newer build', () {
    test('the wrong type of a value falls back to the default instead of failing', () {
      final settings = RequestSettings.fromJson({
        'flow': {
          'retry': {'enabled': 'yes', 'maxRetries': 'many', 'backoff': 'quadratic', 'statuses': 'all', 'jitter': 1},
          'poll': 'later',
          'runIf': [1, 2],
          'alwaysRun': 'sure',
        },
        'pagination': 'all',
      });

      expect(settings.flow, const FlowSettings());
      expect(settings.pagination, PaginationSettings.none);
    });

    test('numbers are held to their ranges: too big is capped, too small reads as unset', () {
      final retry = RetryPolicy.fromJson({
        'maxRetries': 99,
        'delayMs': 99999999,
        'maxDelayMs': -5,
        'maxSeconds': 100000,
      });

      expect(retry.maxRetries, RetryPolicy.maxRetriesLimit);
      expect(retry.delayMs, RetryPolicy.maxDelayLimitMs);
      expect(retry.maxDelayMs, const RetryPolicy().maxDelayMs);
      expect(retry.maxTotalSeconds, RetryPolicy.maxTotalLimitSeconds);
      expect(RetryPolicy.fromJson({'maxRetries': 0}).maxRetries, 3);

      final poll = PollPolicy.fromJson({'intervalMs': 1, 'maxAttempts': 100000, 'maxSeconds': 0});
      expect(poll.intervalMs, const PollPolicy().intervalMs);
      expect(poll.maxAttempts, PollPolicy.maxAttemptsLimit);
      expect(poll.maxSeconds, const PollPolicy().maxSeconds);

      final pages = PaginationSettings.fromJson({'maxPages': 5000, 'maxMegabytes': 5000, 'delayMs': 99999999});
      expect(pages.maxPages, 500);
      expect(pages.maxMegabytes, 100);
      expect(pages.delayMs, PaginationSettings.maxDelayMs);
    });

    test('unknown status tokens are dropped and the rest normalised', () {
      final retry = RetryPolicy.fromJson({
        'statuses': ['5XX', '429', 'teapot', '99', '2xx', ' 503 ', 7, '429'],
      });

      expect(retry.statuses, ['5xx', '429', '503']);
    });

    test('an unknown condition kind is left out, the known ones stay', () {
      final runIf = RunIfPolicy.fromJson({
        'enabled': true,
        'all': [
          {'kind': 'moonPhase', 'name': 'x'},
          {'kind': 'variableExists', 'name': 'token'},
          'junk',
        ],
      });

      expect(runIf.conditions.map((c) => (c.kind, c.name)), [(RunConditionKind.variableExists, 'token')]);
    });

    test('keys a newer build added are ignored, and the known ones still read', () {
      final settings = RequestSettings.fromJson({
        'verifySsl': false,
        'flow': {
          'alwaysRun': true,
          'fanOut': {'to': 4},
          'retry': {'enabled': true, 'maxRetries': 2, 'circuitBreaker': true},
        },
        'pagination': {'enabled': true, 'kind': 'graphqlRelay', 'itemsPath': 'edges'},
        'somethingNew': 1,
      });

      expect(settings.verifySsl, isFalse);
      expect(settings.flow.alwaysRun, isTrue);
      expect(settings.flow.retry.maxRetries, 2);
      expect(settings.pagination.enabled, isTrue);
      expect(settings.pagination.kind, PaginationKind.linkHeader, reason: 'an unknown strategy reads as the first one');
      expect(settings.pagination.itemsPath, 'edges');
    });

    test('an older row with none of the new keys reads as no flow', () {
      final settings = RequestSettings.decode('{"verifySsl":false,"timeoutSeconds":5}');

      expect(settings, const RequestSettings(verifySsl: false, timeoutSeconds: 5));
      expect(settings.flow, FlowSettings.none);
    });

    test('unreadable stored text reads as nothing', () {
      for (final stored in ['{oops', '', '[]', '"x"', 'null']) {
        expect(RequestSettings.decode(stored), RequestSettings.none, reason: stored);
      }
    });
  });

  group('what the editor shows about it', () {
    test('the retry summary says what it does', () {
      expect(const RetryPolicy(enabled: true, maxRetries: 3, delayMs: 1000).summary, 'Up to 3 retries on network errors, 5xx and 429, exponential from 1 s');
      expect(
        const RetryPolicy(maxRetries: 1, onNetworkError: false, statuses: ['503'], backoff: BackoffKind.fixed, delayMs: 500).summary,
        'Up to 1 retry on 503, 500 ms apart',
      );
      expect(const RetryPolicy(onNetworkError: false, statuses: []).summary, contains('nothing selected'));
    });

    test('a poll or a run if with nothing in it asks for a condition', () {
      expect(const PollPolicy(enabled: true).summary, 'Add a condition to wait for');
      expect(const PollPolicy(enabled: true).isActive, isFalse);
      expect(const RunIfPolicy(enabled: true).summary, 'Add a condition');
      expect(const RunIfPolicy(enabled: true).isActive, isFalse);
    });

    test('a condition reads as a sentence, and one that is not filled in says what is missing', () {
      expect(RunCondition(kind: RunConditionKind.variableEquals, name: '{{region}}', value: 'eu').text, '{{region}} equals "eu"');
      expect(RunCondition(kind: RunConditionKind.environmentIs, name: ' Staging ').text, 'the environment is "Staging"');
      expect(RunCondition(kind: RunConditionKind.variableExists).error, 'Enter a variable name');
      expect(RunCondition(kind: RunConditionKind.environmentIs).error, 'Enter an environment name');
      expect(RunCondition(kind: RunConditionKind.previousPassed).error, isNull);
    });

    test('the pagination summary names the strategy, the items and the limit', () {
      expect(
        const PaginationSettings(kind: PaginationKind.linkHeader, itemsPath: 'data').summary,
        'Link header (rel="next") · items at data · up to 20 pages',
      );
      expect(_pagination.summary, contains('offset in body params.offset'));
      expect(_pagination.summary, contains('total at result.length'));
    });

    test('each strategy says what it still needs', () {
      expect(const PaginationSettings(kind: PaginationKind.linkHeader).problem, isNull);
      expect(const PaginationSettings(kind: PaginationKind.nextUrl).problem, contains('next-page URL'));
      expect(const PaginationSettings(kind: PaginationKind.cursor, nextPath: 'c').problem, contains('parameter'));
      expect(const PaginationSettings(kind: PaginationKind.cursor, param: 'c').problem, contains('token'));
      expect(const PaginationSettings(kind: PaginationKind.page).problem, contains('page parameter'));
      expect(const PaginationSettings(kind: PaginationKind.offset).problem, contains('offset parameter'));
      expect(const PaginationSettings(kind: PaginationKind.offset, param: 'offset').problem, isNull);
    });

    test('copyWith keeps every number inside its range', () {
      const retry = RetryPolicy();

      expect(retry.copyWith(maxRetries: 50).maxRetries, 10);
      expect(retry.copyWith(maxRetries: 0).maxRetries, 1);
      expect(const PollPolicy().copyWith(maxAttempts: 1).maxAttempts, 2);
      expect(const PaginationSettings().copyWith(maxPages: 0).maxPages, 1);
    });
  });
}
