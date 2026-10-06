// The Flow tab, the strip above the response and the console lines, as a person sees them: light and dark, wide and
// phone width, and what each control writes to the request's settings.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/console/presentation/view_models/request_console_log.dart';
import 'package:postpilot/features/console/presentation/widgets/console_dialog.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_report.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/entities/pagination_settings.dart';
import 'package:postpilot/features/request_flow/presentation/view_models/request_flow_view_model.dart';
import 'package:postpilot/features/request_flow/presentation/widgets/flow_report_strip.dart';
import 'package:postpilot/features/request_flow/presentation/widgets/request_flow_tab.dart';
import 'package:postpilot/features/scripting/domain/entities/assertion_entity.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import '../settings/fakes/fake_settings_repositories.dart';
import 'flow_support.dart';

const _id = 7;

final _everythingOn = RequestSettings(
  verifySsl: false,
  flow: FlowSettings(
    retry: const RetryPolicy(enabled: true, statuses: ['5xx', '429', '409', '4xx']),
    poll: PollPolicy(enabled: true, until: [
      AssertionEntity(type: AssertionType.jsonPathEquals, path: 'data.status', expected: 'done'),
      AssertionEntity(type: AssertionType.headerEquals, path: 'X-Job-State', expected: 'finished'),
      AssertionEntity(type: AssertionType.jsonSchema, path: '', expected: '{"type":"object"}'),
    ]),
    runIf: RunIfPolicy(enabled: true, conditions: [
      RunCondition(kind: RunConditionKind.variableEquals, name: 'region', value: 'eu'),
      RunCondition(kind: RunConditionKind.environmentIsNot, name: 'Production'),
      RunCondition(kind: RunConditionKind.previousFailed),
      RunCondition(kind: RunConditionKind.variableNotEmpty),
    ]),
    alwaysRun: true,
  ),
  pagination: const PaginationSettings(
    enabled: true,
    kind: PaginationKind.offset,
    itemsPath: 'result.records',
    param: 'params.offset',
    limitParam: 'params.limit',
    totalPath: 'result.length',
    hasMorePath: 'has_more',
  ),
);

Widget _app(Widget child, {required bool dark}) => MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(12), child: child)),
    );

/// A 3-page Link-header API's first response, as the detector sees it.
final _linkedResponse = jsonResponse({'data': [1, 2]}, headers: const {'Link': '<https://api.test/items?page=2>; rel="next"'});

Finder _in(String key, Finder matching) => find.descendant(of: find.byKey(ValueKey(key)), matching: matching);

Finder _switchOf(String section) => _in(section, find.byType(Switch));

Finder _fieldOf(String key) => _in(key, find.byType(TextField));

void main() {
  late FakeRequestSettingsRepository repo;

  setUp(() => repo = FakeRequestSettingsRepository());
  tearDown(() => locator.reset());

  Future<void> pumpTab(
    WidgetTester tester, {
    bool dark = false,
    double width = 900,
    HttpMethod method = HttpMethod.get,
    RequestSettings? stored,
    bool withResponse = false,
    Object? responseJson,
  }) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (stored != null) repo.stored[_id] = stored;
    locator.registerFactory<RequestFlowViewModel>(() => RequestFlowViewModel(repo));
    await tester.pumpWidget(
      _app(
        RequestFlowTab(
          requestId: _id,
          method: method,
          request: withResponse ? flowRequest(method: method, id: _id) : null,
          response: withResponse ? (responseJson == null ? _linkedResponse : jsonResponse(responseJson)) : null,
        ),
        dark: dark,
      ),
    );
    await tester.pumpAndSettle();
  }

  RequestSettings saved() => repo.stored[_id]!;

  group('layout, in light and dark, wide and phone-sized', () {
    for (final dark in [false, true]) {
      for (final width in [1200.0, 420.0]) {
        final where = '${dark ? 'dark' : 'light'} at ${width.toInt()} px';

        testWidgets('a fresh request: four switched-off sections, nothing in the way ($where)', (tester) async {
          await pumpTab(tester, dark: dark, width: width);

          expect(tester.takeException(), isNull);
          for (final title in ['Flow', 'Retry', 'Poll until', 'Fetch all pages', 'Run if']) {
            expect(find.text(title), findsOneWidget, reason: title);
          }
          expect(tester.widgetList<Switch>(find.byType(Switch)).map((s) => s.value), [false, false, false, false]);
          expect(find.text('Retries (1 to 10)'), findsNothing, reason: 'an off section is only its header');
          expect(find.text('Always run, even after a failure'), findsOneWidget);
        });

        testWidgets('everything on and filled in lays out without overflow ($where)', (tester) async {
          await pumpTab(tester, dark: dark, width: width, method: HttpMethod.post, stored: _everythingOn);

          expect(tester.takeException(), isNull);
          expect(tester.widgetList<Switch>(find.byType(Switch)).map((s) => s.value), [true, true, true, true]);
          expect(find.text('Retries (1 to 10)'), findsOneWidget);
          expect(find.text('Items array (JSON path)'), findsOneWidget);
          expect(find.text('I know repeating this request is safe'), findsOneWidget);
          expect(find.byKey(const ValueKey('flow-repeat-warning')), findsOneWidget);
        });
      }
    }
  });

  group('what each control writes', () {
    testWidgets('switching Retry on stores it with the defaults, and shows its settings', (tester) async {
      await pumpTab(tester);

      await tester.tap(_switchOf('flow-retry'));
      await tester.pumpAndSettle();

      final retry = saved().flow.retry;
      expect((retry.enabled, retry.maxRetries, retry.backoff), (true, 3, BackoffKind.exponential));
      expect(retry.statuses, ['5xx', '429']);
      expect(find.text('Retries (1 to 10)'), findsOneWidget);
      expect(find.text('Up to 3 retries on network errors, 5xx and 429, exponential from 1 s'), findsOneWidget);
    });

    testWidgets('the number of retries is held to 1..10, the statuses and the wait style follow the chips and the buttons', (tester) async {
      await pumpTab(tester, stored: RequestSettings(flow: const FlowSettings(retry: RetryPolicy(enabled: true))));

      await tester.enterText(_fieldOf('retry-max'), '99');
      await tester.pump();
      expect(saved().flow.retry.maxRetries, 10);

      await tester.tap(find.byKey(const ValueKey('retry-status-5xx')));
      await tester.pump();
      expect(saved().flow.retry.statuses, ['429']);

      await tester.tap(find.byKey(const ValueKey('retry-status-408')));
      await tester.pump();
      expect(saved().flow.retry.statuses, ['429', '408']);

      await tester.enterText(_fieldOf('retry-other-statuses'), '409, nonsense 4xx');
      await tester.pump();
      expect(saved().flow.retry.statuses, ['429', '408', '409', '4xx']);

      await tester.tap(find.byKey(const ValueKey('retry-network')));
      await tester.pump();
      expect(saved().flow.retry.onNetworkError, isFalse);

      expect(find.text('Longest wait'), findsOneWidget);
      await tester.tap(find.text('Fixed'));
      await tester.pumpAndSettle();
      expect(saved().flow.retry.backoff, BackoffKind.fixed);
      expect(find.text('Longest wait'), findsNothing, reason: 'a fixed wait has no ceiling to set');

      await tester.tap(find.byKey(const ValueKey('retry-jitter')));
      await tester.pump();
      expect(saved().flow.retry.jitter, isFalse);
    });

    testWidgets('Poll until takes conditions like assertions, and its numbers', (tester) async {
      await pumpTab(tester);

      await tester.tap(_switchOf('flow-poll'));
      await tester.pumpAndSettle();
      expect(find.text('Add a condition to wait for'), findsOneWidget, reason: 'on, but nothing to wait for yet');
      await tester.tap(find.text('Add condition'));
      await tester.pumpAndSettle();

      expect(saved().flow.poll.enabled, isTrue);
      expect(saved().flow.poll.until, hasLength(1));
      expect(find.textContaining('Every 2 s until Status is 2xx'), findsOneWidget);
      await tester.enterText(_fieldOf('poll-interval'), '2500');
      await tester.enterText(_fieldOf('poll-attempts'), '12');
      await tester.pump();
      expect((saved().flow.poll.intervalMs, saved().flow.poll.maxAttempts), (2500, 12));
    });

    testWidgets('Run if: a condition per row, with what is missing said next to it, and its kinds change the fields', (tester) async {
      await pumpTab(tester);

      await tester.tap(_switchOf('flow-run-if'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add condition'));
      await tester.pumpAndSettle();

      expect(saved().flow.runIf.conditions, hasLength(1));
      expect(find.text('Enter a variable name'), findsOneWidget);

      await tester.tap(find.text('Variable is not empty'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Variable equals').last);
      await tester.pumpAndSettle();
      expect(saved().flow.runIf.conditions.single.kind, RunConditionKind.variableEquals);
      expect(find.byType(TextFormField), findsNWidgets(2), reason: 'a name and a value');

      await tester.enterText(find.byType(TextFormField).first, 'region');
      await tester.enterText(find.byType(TextFormField).last, 'eu');
      await tester.pump();
      expect(saved().flow.runIf.conditions.single.name, 'region');
      expect(saved().flow.runIf.conditions.single.value, 'eu');
      expect(find.text('Enter a variable name'), findsNothing);
    });

    testWidgets('a condition that needs no name (the previous request) shows no fields, and can be removed', (tester) async {
      await pumpTab(
        tester,
        stored: RequestSettings(
          flow: FlowSettings(runIf: RunIfPolicy(enabled: true, conditions: [RunCondition(kind: RunConditionKind.previousFailed)])),
        ),
      );

      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();

      expect(saved().flow.runIf.conditions, isEmpty);
    });

    testWidgets('Always run is a checkbox of its own, which Run if does not need', (tester) async {
      await pumpTab(tester);

      await tester.tap(find.byKey(const ValueKey('flow-always-run')));
      await tester.pump();

      expect(saved().flow.alwaysRun, isTrue);
      expect(saved().flow.runIf.enabled, isFalse);
    });

    testWidgets('Fetch all pages: the strategy and its paths are editable, and a strategy that is not filled in says what is missing', (tester) async {
      await pumpTab(tester);

      await tester.tap(_switchOf('flow-pages'));
      await tester.pumpAndSettle();
      expect(saved().pagination.enabled, isTrue);
      expect(find.text('Send the request once first.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pagination-kind-linkHeader')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cursor / token').last);
      await tester.pumpAndSettle();
      expect(saved().pagination.kind, PaginationKind.cursor);
      expect(find.text('Enter the JSON path of the next-page token'), findsOneWidget);

      await tester.enterText(_fieldOf('pagination-next'), 'nextPageToken');
      await tester.enterText(_fieldOf('pagination-param'), 'pageToken');
      await tester.enterText(_fieldOf('pagination-items'), 'data.items');
      await tester.enterText(_fieldOf('pagination-max-pages'), '99999');
      await tester.pump();

      final pagination = saved().pagination;
      expect((pagination.nextPath, pagination.param, pagination.itemsPath), ('nextPageToken', 'pageToken', 'data.items'));
      expect(pagination.maxPages, 500, reason: 'the page limit can never pass 500');
      expect(pagination.problem, isNull);
      expect(find.text('Enter the JSON path of the next-page token'), findsNothing);
    });

    testWidgets('"Detect" proposes the strategy for confirmation, and "Use this" turns it on', (tester) async {
      await pumpTab(tester, stored: const RequestSettings(pagination: PaginationSettings(enabled: true)), withResponse: true);

      await tester.tap(find.byKey(const ValueKey('pagination-detect')));
      await tester.pumpAndSettle();

      expect(find.text('Found: Link header (rel="next")'), findsOneWidget);
      expect(saved().pagination.kind, PaginationKind.linkHeader);

      await tester.tap(find.byKey(const ValueKey('pagination-use-detected')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pagination-detected')), findsNothing);
      expect(saved().pagination.enabled, isTrue);
      expect(saved().pagination.itemsPath, 'data', reason: 'the items array the detector found in the response');
    });

    testWidgets('"Detect" on a response with no sign of more pages says so, and changes nothing', (tester) async {
      await pumpTab(
        tester,
        stored: const RequestSettings(pagination: PaginationSettings(enabled: true, itemsPath: 'keep')),
        withResponse: true,
        responseJson: {'id': 1, 'name': 'Ada'},
      );

      await tester.tap(find.byKey(const ValueKey('pagination-detect')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pagination-nothing')), findsOneWidget);
      expect(saved().pagination.itemsPath, 'keep');
    });

    testWidgets('detecting an Odoo search_read over POST also ticks "repeating is safe"', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repo.stored[_id] = const RequestSettings(pagination: PaginationSettings(enabled: true));
      locator.registerFactory<RequestFlowViewModel>(() => RequestFlowViewModel(repo));
      await tester.pumpWidget(
        _app(
          RequestFlowTab(
            requestId: _id,
            method: HttpMethod.post,
            request: flowRequest(url: 'https://odoo.test/json/2/res.partner/search_read', method: HttpMethod.post, body: jsonBody({'domain': <Object>[], 'limit': 50}), id: _id),
            response: jsonResponse([{'id': 1}]),
          ),
          dark: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('flow-repeat-warning')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pagination-detect')));
      await tester.pumpAndSettle();
      expect(find.textContaining('This POST only reads'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pagination-use-detected')));
      await tester.pumpAndSettle();

      expect(saved().flow.repeatUnsafe, isTrue);
      expect(saved().pagination.location, PageParamLocation.body);
      expect(find.byKey(const ValueKey('flow-repeat-warning')), findsNothing);
    });

    testWidgets('a POST asks for the tick as soon as something would repeat it, and a GET never does', (tester) async {
      await pumpTab(tester, method: HttpMethod.post);
      expect(find.byKey(const ValueKey('flow-repeat-unsafe')), findsNothing, reason: 'nothing repeats it yet');

      await tester.tap(_switchOf('flow-retry'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('flow-repeat-unsafe')), findsOneWidget);
      expect(find.byKey(const ValueKey('flow-repeat-warning')), findsOneWidget);
      expect(find.textContaining('POST can create, change or delete something each time it is sent'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('flow-repeat-unsafe')));
      await tester.pumpAndSettle();

      expect(saved().flow.repeatUnsafe, isTrue);
      expect(find.byKey(const ValueKey('flow-repeat-warning')), findsNothing);
    });

    testWidgets('"Count the records first" is offered for the offset strategy only, and writes countTotal', (tester) async {
      await pumpTab(tester, stored: const RequestSettings(pagination: PaginationSettings(enabled: true, kind: PaginationKind.page, param: 'page')));
      expect(find.byKey(const ValueKey('pagination-count')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('pagination-kind-page')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Offset and limit').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pagination-count')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pagination-count')));
      await tester.pump();

      expect(saved().pagination.countTotal, isTrue);
      expect(saved().pagination.kind, PaginationKind.offset);
    });

    testWidgets('a GET never shows the tick', (tester) async {
      await pumpTab(tester, stored: _everythingOn);

      expect(find.byKey(const ValueKey('flow-repeat-unsafe')), findsNothing);
    });

    testWidgets('editing flow keeps the other settings of the request', (tester) async {
      await pumpTab(tester, stored: const RequestSettings(verifySsl: false, timeoutSeconds: 4));

      await tester.tap(_switchOf('flow-retry'));
      await tester.pumpAndSettle();

      expect(saved().verifySsl, isFalse);
      expect(saved().timeoutSeconds, 4);
      expect(saved().flow.retry.enabled, isTrue);
    });

    testWidgets('settings already stored are shown: what is on, and how it is set', (tester) async {
      await pumpTab(tester, stored: _everythingOn);

      expect(tester.widgetList<Switch>(find.byType(Switch)).map((s) => s.value), [true, true, true, true]);
      expect(find.textContaining('Up to 3 retries on network errors, 5xx, 429, 409 and 4xx'), findsOneWidget);
      expect(find.textContaining('Every 2 s until 3 conditions hold'), findsOneWidget);
      expect(find.textContaining('Only when {{region}} equals "eu" and the environment is not "Production"'), findsOneWidget);
    });

    testWidgets('a failed save is said under the controls', (tester) async {
      await pumpTab(tester);
      repo.saveFailure = StateError('disk full');

      await tester.tap(_switchOf('flow-retry'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't save this request's flow settings"), findsOneWidget);
    });
  });

  group('the strip above the response', () {
    FlowReport busy() => FlowReport(
          attempts: const [
            FlowAttempt(label: 'request', status: 503),
            FlowAttempt(label: 'attempt 2/3 after 1.2 s', status: 503),
            FlowAttempt(label: 'attempt 3/3 after 1.2 s', status: 200),
          ],
          retries: 2,
          polls: 5,
          pages: const PageSummary(pages: 4, items: 312, stop: PaginationStop.lastPage, strategy: 'Link header'),
        );

    for (final dark in [false, true]) {
      testWidgets('shows attempts, polls and the pages badge as one slim line, folded; a tap lists every try (${dark ? 'dark' : 'light'})', (tester) async {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app(FlowReportStrip(report: busy()), dark: dark));

        expect(tester.takeException(), isNull);
        expect(find.text('3 attempts'), findsOneWidget);
        expect(find.text('polled 5 times'), findsOneWidget);
        expect(find.text('4 pages, 312 items'), findsOneWidget);
        expect(find.textContaining('attempt 2/3 after 1.2 s'), findsNothing);

        await tester.tap(find.byKey(const ValueKey('flow-strip-toggle')));
        await tester.pump();

        expect(find.text('attempt 2/3 after 1.2 s: HTTP 503'), findsOneWidget);
        expect(find.text('attempt 3/3 after 1.2 s: HTTP 200'), findsOneWidget);
        expect(find.textContaining('all pages fetched'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a failure opens it up at once, and is said in words', (tester) async {
      const report = FlowReport(
        polls: 3,
        attempts: [FlowAttempt(label: 'request', status: 200)],
        failure: 'Polling gave up after 3 requests in 4 s. The last response is shown.',
      );

      await tester.pumpWidget(_app(const FlowReportStrip(report: report), dark: false));

      expect(find.text('failed'), findsOneWidget);
      expect(find.textContaining('Polling gave up after 3 requests'), findsOneWidget);
    });

    testWidgets('a page limit is a warning, not a failure', (tester) async {
      const report = FlowReport(
        pages: PageSummary(pages: 20, items: 400, stop: PaginationStop.maxPages, strategy: 'Link header'),
        notes: ['Stopped at the page limit; the server has more pages'],
      );

      await tester.pumpWidget(_app(const FlowReportStrip(report: report), dark: false));

      expect(find.text('20 pages, 400 items'), findsOneWidget);
      expect(find.text('failed'), findsNothing);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('a plain send has nothing to say', (tester) async {
      await tester.pumpWidget(_app(const FlowReportStrip(report: FlowReport()), dark: false));

      expect(find.byType(InkWell), findsNothing);
    });
  });

  group('the console', () {
    testWidgets('lists what the flow did under the request it explains, masked, and keeps it out of Errors', (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final log = RequestConsoleLog()..addNote('attempt 2/3 after 1.2 s');
      log.addNote('page 3 ?token=abcdef1234567890abcdef1234567890');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: ChangeNotifierProvider<RequestConsoleLog>.value(value: log, child: const ConsoleDialog())),
        ),
      );
      await tester.pump();

      expect(find.text('attempt 2/3 after 1.2 s'), findsOneWidget);
      expect(find.textContaining('abcdef1234567890'), findsNothing, reason: 'a credential in a note is masked');
      expect(log.errors, isEmpty);

      await tester.tap(find.text('Errors'));
      await tester.pump();
      expect(find.text('attempt 2/3 after 1.2 s'), findsNothing);
      expect(find.text('No errors'), findsOneWidget);
    });
  });
}
