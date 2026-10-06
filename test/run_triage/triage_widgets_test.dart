// The triage pane, the run history and the monitor dialog opened for real, in a light and a dark theme on a desktop and a
// phone screen. Flutter turns a layout overflow into a test failure, so this proves they are usable, and the flows are
// driven through the widgets.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_repository.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/run_triage/domain/entities/monitor_config.dart';
import 'package:postpilot/features/run_triage/domain/entities/run_record_doc.dart';
import 'package:postpilot/features/run_triage/domain/repositories/monitor_config_store.dart';
import 'package:postpilot/features/run_triage/domain/repositories/run_record_repository.dart';
import 'package:postpilot/features/run_triage/domain/services/monitor_runner.dart';
import 'package:postpilot/features/run_triage/domain/services/triage_analysis.dart';
import 'package:postpilot/features/run_triage/presentation/monitor_dialog.dart';
import 'package:postpilot/features/run_triage/presentation/monitor_service.dart';
import 'package:postpilot/features/run_triage/presentation/monitor_status_panel.dart';
import 'package:postpilot/features/run_triage/presentation/run_history_dialog.dart';
import 'package:postpilot/features/run_triage/presentation/run_history_view_model.dart';
import 'package:postpilot/features/run_triage/presentation/triage_pane.dart';
import 'run_fixtures.dart';

final class _Records implements RunRecordRepository {
  final list = <StoredRun>[];
  final _changes = StreamController<List<StoredRun>>.broadcast();
  var _next = 1;

  StoredRun add(RunRecordDoc doc) {
    final stored = StoredRun(id: _next++, collectionId: 1, doc: doc);
    list.insert(0, stored);
    _changes.add(List.of(list));
    return stored;
  }

  @override
  Future<int> save(int collectionId, RunRecordDoc doc) async => add(doc).id;

  @override
  Future<List<StoredRun>> recent(int collectionId, {int limit = 50}) async => list.take(limit).toList();

  @override
  Stream<List<StoredRun>> watch(int collectionId, {int limit = 50}) async* {
    yield List.of(list);
    yield* _changes.stream;
  }

  @override
  Future<StoredRun?> byId(int id) async => list.where((r) => r.id == id).firstOrNull;

  @override
  Future<void> clear(int collectionId) async {
    list.clear();
    _changes.add(const []);
  }
}

/// 80 requests: 12 rejected with 401 and 3 timing out against one host; Payments is also flaky, Search got slow.
RunRecordDoc _bigRun({DateTime? at}) => run(
      [
        for (var i = 1; i <= 80; i++)
          switch (i) {
            <= 12 => entry('Orders $i', folder: 'Orders', url: 'https://api.shop.test/orders/$i', status: 401, passed: false, requestId: i),
            20 || 21 || 22 => entry('Reports $i', status: null, ms: null, passed: false, requestId: i, error: 'The server at db.shop.test did not answer within 30 seconds. Raise the "Request timeout" in Settings if the server is just slow.'),
            30 => entry('Payments', method: 'POST', status: 500, passed: false, requestId: 30),
            31 => entry('Search', ms: 900, requestId: 31),
            _ => entry('Request $i', requestId: i),
          },
      ],
      at: at ?? DateTime.utc(2026, 10, 6, 12),
    );

List<RunRecordDoc> _earlierRuns() => [
      for (var k = 1; k <= 4; k++)
        run(
          [
            for (var i = 1; i <= 80; i++)
              switch (i) {
                31 => entry('Search', ms: 100 + k * 10, requestId: 31),
                30 => k.isOdd ? entry('Payments', method: 'POST', requestId: 30) : entry('Payments', method: 'POST', status: 500, passed: false, requestId: 30),
                <= 12 => entry('Orders $i', folder: 'Orders', url: 'https://api.shop.test/orders/$i', requestId: i),
                _ => entry('Request $i', requestId: i),
              },
          ],
          at: DateTime.utc(2026, 10, 6, 12).subtract(Duration(hours: k)),
        ),
    ];

Future<void> _show(WidgetTester tester, Widget Function(BuildContext) builder, {required Size size, required bool dark, bool asDialog = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: Scaffold(
      body: Builder(
        builder: (context) => asDialog
            ? Center(child: FilledButton(onPressed: () => showDialog<Object>(context: context, builder: builder), child: const Text('open')))
            : builder(context),
      ),
    ),
  ));
  if (asDialog) {
    await tester.tap(find.text('open'));
  }
  await tester.pumpAndSettle();
}

void main() {
  group('TriagePane', () {
    Future<void> showPane(WidgetTester tester, TriageAnalysis? analysis, {required Size size, required bool dark, bool busy = false, ValueChanged<List<int>>? onRerun}) =>
        _show(tester, (_) => Scaffold(body: TriagePane(analysis: analysis, busy: busy, onRerunFailed: onRerun)), size: size, dark: dark, asDialog: false);

    for (final dark in [false, true]) {
      for (final size in const [Size(1200, 900), Size(420, 800)]) {
        final label = '${dark ? 'dark' : 'light'} ${size.width.toInt()}px';

        testWidgets('groups the failures by cause, biggest first, with a hint each ($label)', (tester) async {
          final a = TriageAnalysis.of(_bigRun(), _earlierRuns());
          await showPane(tester, a, size: size, dark: dark, onRerun: (_) {});

          expect(find.text('16 failures, 3 causes'), findsOneWidget);
          expect(find.text('HTTP 401 Unauthorized'), findsOneWidget);
          expect(find.text('12 requests'), findsOneWidget);
          expect(find.text('Timeout (db.shop.test)'), findsOneWidget);
          expect(find.text('HTTP 500 Internal Server Error'), findsOneWidget);
          expect(find.textContaining('12 requests failed with 401 (Unauthorized): the token or API key was probably rejected or has expired.'), findsOneWidget);
          expect(find.textContaining('3 requests timed out waiting for db.shop.test'), findsOneWidget);
          expect(find.textContaining('First: GET https://api.shop.test/orders/1'), findsOneWidget);
          expect(find.text('Re-run failed only (16)'), findsOneWidget);
        });

        testWidgets('compares with the run before and names the flaky and slow requests ($label)', (tester) async {
          final a = TriageAnalysis.of(_bigRun(), _earlierRuns());
          await showPane(tester, a, size: size, dark: dark);
          expect(find.textContaining('Since the run before (2026-10-06 11:00 UTC)'), findsOneWidget);
          // The run before (11:00) had Orders and Payments passing and no Reports requests at all: all 16 failures are new.
          expect(find.text('16 new'), findsOneWidget);
          expect(find.text('0 fixed'), findsOneWidget);
          expect(find.text('0 still failing'), findsOneWidget);
          expect(find.text('Flaky requests'.toUpperCase()), findsOneWidget);
          expect(find.textContaining('Payments: passed 2 times and failed 3 of the last 5 runs'), findsOneWidget);
          expect(find.text('Slower than usual'.toUpperCase()), findsOneWidget);
          expect(find.textContaining('Search: took 900 ms, usually about 125 ms'), findsOneWidget);
        });
      }
    }

    testWidgets('opening a group lists its requests with the flaky and slow markers', (tester) async {
      final a = TriageAnalysis.of(_bigRun(), _earlierRuns());
      await showPane(tester, a, size: const Size(1200, 2000), dark: false);
      await tester.ensureVisible(find.text('Show the request'));
      await tester.tap(find.text('Show the request'));
      await tester.pumpAndSettle();
      expect(find.text('Payments'), findsWidgets);
      expect(find.text('Flaky'), findsOneWidget);
      await tester.ensureVisible(find.text('Show all 12 requests'));
      await tester.tap(find.text('Show all 12 requests'));
      await tester.pumpAndSettle();
      expect(find.text('Orders / Orders 1'), findsOneWidget);
    });

    testWidgets('Re-run failed only hands over the ids of the failed requests, once each', (tester) async {
      List<int>? asked;
      final a = TriageAnalysis.of(_bigRun(), const []);
      await showPane(tester, a, size: const Size(1200, 900), dark: false, onRerun: (ids) => asked = ids);
      await tester.tap(find.text('Re-run failed only (16)'));
      await tester.pump();
      expect(asked, [...List.generate(12, (i) => i + 1), 20, 21, 22, 30]);
    });

    testWidgets('failures that cannot be matched with a request cannot be re-run, and the button says why', (tester) async {
      final doc = run([failedWith('A', 500), failedWith('B', 500)]);
      await showPane(tester, TriageAnalysis.of(doc, const []), size: const Size(1200, 900), dark: false, onRerun: (_) {});
      final button = tester.widget<ButtonStyleButton>(find.ancestor(of: find.text('Re-run failed only'), matching: find.bySubtype<ButtonStyleButton>()));
      expect(button.onPressed, isNull);
      expect(find.byTooltip('None of the failed requests could be matched with a request of this collection.'), findsOneWidget);
    });

    testWidgets('Copy as GitHub issue copies masked Markdown', (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await showPane(tester, TriageAnalysis.of(_bigRun(), const []), size: const Size(1200, 900), dark: false);
      await tester.tap(find.text('Copy as GitHub issue'));
      await tester.pumpAndSettle();
      expect(clipboard, startsWith('## PostPilot: 16 of 80 requests failed in Shop (Staging)'));
      expect(clipboard, contains('### 3 causes'));
    });

    testWidgets('nothing failed, no run yet, and waiting for a run', (tester) async {
      await showPane(tester, TriageAnalysis.of(run([entry('A')]), const []), size: const Size(420, 800), dark: false);
      expect(find.text('Nothing failed'), findsWidgets);
      await showPane(tester, null, size: const Size(420, 800), dark: false);
      expect(find.text('No run to look at yet'), findsOneWidget);
      await _show(tester, (_) => const Scaffold(body: TriagePane(analysis: null, busy: true)), size: const Size(420, 800), dark: true, asDialog: false);
      expect(find.textContaining('appears when the run has finished'), findsOneWidget);
    });
  });

  group('RunHistoryDialog', () {
    late _Records records;

    setUp(() {
      records = _Records();
      for (final doc in _earlierRuns().reversed) {
        records.add(doc);
      }
      records.add(_bigRun());
    });

    RunHistoryViewModel vm() => RunHistoryViewModel(
          records: records,
          collectionId: 1,
          collectionName: 'Shop',
          loadRequests: () async => [for (var i = 1; i <= 80; i++) RequestSummaryEntity(id: i, folderId: null, name: 'Request $i', method: HttpMethod.get)],
          loadFolders: () async => const <FolderEntity>[],
        );

    Future<void> open(WidgetTester tester, {required Size size, bool dark = false, Future<String?> Function()? pick, List<int>? Function()? popped}) =>
        _show(tester, (context) => RunHistoryDialog(collectionId: 1, collectionName: 'Shop', viewModel: vm(), pickFile: pick), size: size, dark: dark);

    for (final dark in [false, true]) {
      for (final size in const [Size(1200, 900), Size(420, 800)]) {
        final label = '${dark ? 'dark' : 'light'} ${size.width.toInt()}px';

        testWidgets('lists the runs, newest first, and opens one to see its triage ($label)', (tester) async {
          await open(tester, size: size, dark: dark);
          expect(find.text('Run history'), findsOneWidget);
          expect(find.byType(ListTile), findsNWidgets(5));
          expect(find.textContaining('64 passed · 16 failed'), findsOneWidget);

          await tester.tap(find.byKey(ValueKey('run-${records.list.first.id}')));
          await tester.pumpAndSettle();
          expect(find.text('16 failures, 3 causes'), findsOneWidget);
          expect(find.textContaining('Since the run before'), findsOneWidget);
        });
      }
    }

    testWidgets('on a phone the detail replaces the list and Back returns to it', (tester) async {
      await open(tester, size: const Size(420, 800));
      await tester.tap(find.byKey(ValueKey('run-${records.list.first.id}')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back to the list'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      await tester.tap(find.byTooltip('Back to the list'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(5));
    });

    testWidgets('an empty history explains where runs come from', (tester) async {
      records.list.clear();
      await open(tester, size: const Size(1200, 900));
      expect(find.text('No runs yet'), findsOneWidget);
      expect(find.textContaining('--records-dir'), findsOneWidget);
    });

    testWidgets('Re-run failed only closes the history with the ids to run', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      List<int>? result;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showDialog<List<int>>(context: context, builder: (_) => RunHistoryDialog(collectionId: 1, collectionName: 'Shop', viewModel: vm())),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('run-${records.list.first.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Re-run failed only (16)'));
      await tester.pumpAndSettle();
      expect(result, [...List.generate(12, (i) => i + 1), 20, 21, 22, 30]);
    });

    testWidgets('importing a command-line run adds it, matched with the requests of the collection', (tester) async {
      final text = '{"format":"postpilot-run-record","version":1,"source":"cli","trigger":"cli","collection":"Shop","environment":"Staging",'
          '"startedAt":"2026-10-07T08:00:00.000Z","passed":1,"failed":1,"skipped":0,"results":['
          '{"name":"Request 5","method":"GET","passed":true,"status":200},'
          '{"name":"Request 6","method":"GET","passed":false,"status":503}]}';
      await open(tester, size: const Size(1200, 900), pick: () async => text);
      await tester.tap(find.text('Import CLI run…'));
      await tester.pumpAndSettle();
      expect(records.list, hasLength(6));
      expect(find.textContaining('Imported the run: 1 failure in 2 results'), findsOneWidget);
      final imported = records.list.firstWhere((r) => r.doc.source == 'cli');
      expect(imported.doc.results.map((r) => r.requestId), [5, 6]);
      expect(find.text('CLI'), findsWidgets);
      // The same file again is the same run.
      await tester.tap(find.text('Import CLI run…'));
      await tester.pumpAndSettle();
      expect(records.list, hasLength(6));
      expect(find.textContaining('imported before'), findsOneWidget);
    });

    testWidgets('a file that is not a run record is refused with the reason', (tester) async {
      await open(tester, size: const Size(1200, 900), pick: () async => '{"hello": 1}');
      await tester.tap(find.text('Import CLI run…'));
      await tester.pumpAndSettle();
      expect(records.list, hasLength(5));
      expect(find.textContaining('Could not import the file: This file is not a PostPilot run record'), findsOneWidget);
    });

    testWidgets('closing the file chooser changes nothing', (tester) async {
      await open(tester, size: const Size(1200, 900), pick: () async => null);
      await tester.tap(find.text('Import CLI run…'));
      await tester.pumpAndSettle();
      expect(records.list, hasLength(5));
    });

    testWidgets('Clear history asks first, then forgets the runs', (tester) async {
      await open(tester, size: const Size(1200, 900));
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Forget all 5 stored runs of "Shop"?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(records.list, hasLength(5));
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(records.list, isEmpty);
      expect(find.text('No runs yet'), findsOneWidget);
    });
  });

  group('the monitor', () {
    late _Records records;
    late MonitorService service;
    late _MemoryStore store;
    late _OneShotRun runner;

    setUp(() {
      records = _Records();
      store = _MemoryStore();
      runner = _OneShotRun();
      service = MonitorService(
        store: store,
        collections: _TwoCollections(),
        records: records,
        runner: runner,
        // Timers never fire here: a test starts a run by hand.
        timerFactory: (delay, callback) => _InertTimer(),
      );
    });

    tearDown(() => service.dispose());

    Future<void> openDialog(WidgetTester tester, {required Size size, bool dark = false}) => _show(
          tester,
          (_) => MonitorDialog(collectionId: 1, collectionName: 'Shop', service: service, records: records, environments: _Envs()),
          size: size,
          dark: dark,
        );

    for (final dark in [false, true]) {
      for (final size in const [Size(1200, 900), Size(420, 800)]) {
        final label = '${dark ? 'dark' : 'light'} ${size.width.toInt()}px';

        testWidgets('turn it on, choose the interval and the environment, save ($label)', (tester) async {
          await openDialog(tester, size: size, dark: dark);
          expect(find.text('Monitor'), findsOneWidget);
          expect(find.textContaining('Production is never changed'), findsOneWidget);
          expect(find.textContaining('PostPilot does not send desktop notifications'), findsOneWidget);
          expect(find.text('The monitor is off.'), findsOneWidget);

          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
          final field = find.widgetWithText(TextField, 'Every (minutes)');
          await tester.ensureVisible(field);
          await tester.enterText(field, '5');
          await tester.pump();
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect(service.configOf(1), const MonitorConfig(enabled: true, everyMinutes: 5));
          expect(find.text('Saved: every 5 min while PostPilot is open.'), findsOneWidget);
          expect(store.saved[1]?.everyMinutes, 5);
        });

        testWidgets('an interval outside 1 to 1440 is refused where it is typed and Save waits ($label)', (tester) async {
          await openDialog(tester, size: size, dark: dark);
          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
          final field = find.widgetWithText(TextField, 'Every (minutes)');
          await tester.ensureVisible(field);
          await tester.enterText(field, '0');
          await tester.pump();
          expect(find.textContaining('Enter a whole number of minutes from 1 to 1440'), findsOneWidget);
          expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
          await tester.enterText(field, '1440');
          await tester.pump();
          expect(find.textContaining('Enter a whole number'), findsNothing);
          expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNotNull);
        });
      }
    }

    testWidgets('turning it off and saving stops the monitor', (tester) async {
      await tester.runAsync(() async {
        await service.start();
        await service.setConfig(1, const MonitorConfig(enabled: true, everyMinutes: 30));
      });
      await openDialog(tester, size: const Size(1200, 900));
      expect(find.text('Saved: every 30 min while PostPilot is open.'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(service.configOf(1), isNull);
      expect(find.text('The monitor is off.'), findsOneWidget);
    });

    testWidgets('lists the recent monitor runs, not the manual ones, and shows the status', (tester) async {
      records.add(run([entry('A'), failedWith('B', 500)], trigger: 'monitor', at: DateTime.utc(2026, 10, 6, 9)));
      records.add(run([entry('A'), entry('B')], trigger: 'manual', at: DateTime.utc(2026, 10, 6, 8)));
      records.add(run([entry('A'), entry('B')], trigger: 'monitor', at: DateTime.utc(2026, 10, 6, 7)));
      await openDialog(tester, size: const Size(1200, 900));
      expect(find.textContaining('1 passed, 1 failed'), findsOneWidget);
      expect(find.textContaining('2 passed, 0 failed'), findsOneWidget);
      expect(find.textContaining('RECENT MONITOR RUNS'), findsOneWidget);
    });

    testWidgets('a collection that is being monitored shows its failing state and Run now starts a run', (tester) async {
      runner.next = MonitorRunResult(doc: run([failedWith('A', 500), failedWith('B', 500)], trigger: 'monitor'), recordId: 1, skippedByLock: 1, ranNothing: false);
      await tester.runAsync(() async {
        await service.start();
        await service.setConfig(1, const MonitorConfig(enabled: true, everyMinutes: 10));
      });
      await openDialog(tester, size: const Size(1200, 900));
      await tester.tap(find.text('Run now'));
      await tester.pumpAndSettle();
      expect(runner.calls, greaterThanOrEqualTo(1));
      expect(find.text('Failing: 2 requests'), findsOneWidget);
      expect(find.textContaining('1 data-changing request was left out by the production lock'), findsOneWidget);
    });

    testWidgets('Run now before the monitor is saved says to save it first', (tester) async {
      await openDialog(tester, size: const Size(1200, 900));
      // The button is disabled while nothing is saved.
      final button = tester.widget<ButtonStyleButton>(find.ancestor(of: find.text('Run now'), matching: find.bySubtype<ButtonStyleButton>()));
      expect(button.onPressed, isNull);
    });
  });

  group('MonitorStatusPanel', () {
    late MonitorService service;
    late _OneShotRun runner;

    setUp(() {
      runner = _OneShotRun();
      service = MonitorService(
        store: _MemoryStore(),
        collections: _TwoCollections(),
        records: _Records(),
        runner: runner,
        timerFactory: (delay, callback) => _InertTimer(),
      );
    });

    tearDown(() => service.dispose());

    Future<void> showPanel(WidgetTester tester, {required Size size, bool dark = false}) => _show(
          tester,
          (_) => Material(child: Align(alignment: Alignment.topLeft, child: SizedBox(width: size.width < 600 ? size.width : 280, child: MonitorStatusPanel(service: service)))),
          size: size,
          dark: dark,
          asDialog: false,
        );

    for (final dark in [false, true]) {
      for (final size in const [Size(1200, 900), Size(420, 800)]) {
        final label = '${dark ? 'dark' : 'light'} ${size.width.toInt()}px';

        testWidgets('shows nothing while no collection is monitored ($label)', (tester) async {
          await showPanel(tester, size: size, dark: dark);
          expect(find.textContaining('Monitor'), findsNothing);
        });

        testWidgets('Monitor: on while passing; Monitor: 1 failing with a banner once a run fails ($label)', (tester) async {
          await showPanel(tester, size: size, dark: dark);
          await tester.runAsync(() async {
            await service.start();
            await service.setConfig(1, const MonitorConfig(enabled: true, everyMinutes: 10));
            await service.setConfig(2, const MonitorConfig(enabled: true, everyMinutes: 10));
            runner.next = MonitorRunResult(doc: run([entry('A')], trigger: 'monitor'), recordId: 1, skippedByLock: 0, ranNothing: false);
            await service.runNow(1);
          });
          await tester.pump();
          expect(find.text('Monitor: on'), findsOneWidget);

          await tester.runAsync(() async {
            runner.next = MonitorRunResult(doc: run([failedWith('A', 500), failedWith('B', 500)], trigger: 'monitor'), recordId: 2, skippedByLock: 0, ranNothing: false);
            await service.runNow(2);
          });
          await tester.pump();
          expect(find.text('Monitor: 1 failing'), findsOneWidget);
          expect(find.text('Billing started failing'), findsOneWidget);
          expect(find.textContaining('2 requests failed in the last monitor run.'), findsOneWidget);

          await tester.tap(find.byTooltip('Dismiss'));
          await tester.pump();
          expect(find.text('Billing started failing'), findsNothing);
          expect(find.text('Monitor: 1 failing'), findsOneWidget, reason: 'dismissing the banner does not hide that it is failing');
        });
      }
    }

    testWidgets('the chip lists the monitored collections and their state', (tester) async {
      await showPanel(tester, size: const Size(1200, 900));
      await tester.runAsync(() async {
        await service.start();
        await service.setConfig(1, const MonitorConfig(enabled: true, everyMinutes: 10));
        runner.next = MonitorRunResult(doc: run([failedWith('A', 500)], trigger: 'monitor'), recordId: 1, skippedByLock: 0, ranNothing: false);
        await service.runNow(1);
      });
      await tester.pump();
      await tester.tap(find.text('Monitor: 1 failing'));
      await tester.pumpAndSettle();
      expect(find.text('Shop: failing (1)'), findsOneWidget);
    });

    testWidgets('a panel without a monitor (the app has none wired) draws nothing and does not crash', (tester) async {
      await _show(tester, (_) => const Material(child: MonitorStatusPanel()), size: const Size(420, 800), dark: false, asDialog: false);
      expect(find.byType(MonitorStatusPanel), findsOneWidget);
      expect(find.textContaining('Monitor'), findsNothing);
    });
  });
}

final class _MemoryStore implements MonitorConfigStore {
  Map<int, MonitorConfig> saved = {};

  @override
  Future<Map<int, MonitorConfig>> load() async => Map.of(saved);

  @override
  Future<void> save(Map<int, MonitorConfig> configs) async => saved = Map.of(configs);
}

final class _TwoCollections implements CollectionRepository {
  @override
  Stream<List<CollectionEntity>> watchCollections() => Stream.value(const [CollectionEntity(id: 1, name: 'Shop'), CollectionEntity(id: 2, name: 'Billing')]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _Envs implements EnvironmentRepository {
  @override
  Stream<List<EnvironmentEntity>> watchAll() => Stream.value(const [
        EnvironmentEntity(id: 1, name: 'Staging', isActive: true),
        EnvironmentEntity(id: 2, name: 'Production', isActive: false),
      ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

final class _InertTimer implements MonitorTimer {
  @override
  void cancel() {}
}

final class _OneShotRun implements MonitorRun {
  MonitorRunResult next = MonitorRunResult(doc: _monitorRun([entry('A')]), recordId: 1, skippedByLock: 0, ranNothing: false);
  int calls = 0;

  @override
  Future<MonitorRunResult> run(int collectionId, MonitorConfig config, {cancelToken}) async {
    calls++;
    return next;
  }
}

/// A monitor run for a test; top level because `_OneShotRun.run` hides the fixture's `run`.
RunRecordDoc _monitorRun(List<RunResultEntry> results) => run(results, trigger: 'monitor');
