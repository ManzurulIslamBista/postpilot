// The screens of the cleanup ledger: the dialog the command palette opens, and the panel a finished collection run shows.
// Each is opened for real in a light and a dark theme at a desktop and a phone width (Flutter turns a layout overflow into
// a test failure), and the buttons are pressed: a delete, a delete of everything, forgetting, keeping, the production
// warning.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/cleanup_ledger/domain/entities/cleanup_entry.dart';
import 'package:postpilot/features/cleanup_ledger/domain/entities/cleanup_settings.dart';
import 'package:postpilot/features/cleanup_ledger/domain/services/cleanup_executor.dart';
import 'package:postpilot/features/cleanup_ledger/presentation/view_models/cleanup_ledger.dart';
import 'package:postpilot/features/cleanup_ledger/presentation/widgets/auto_cleanup_option.dart';
import 'package:postpilot/features/cleanup_ledger/presentation/widgets/cleanup_ledger_dialog.dart';
import 'package:postpilot/features/cleanup_ledger/presentation/widgets/run_cleanup_panel.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_response_entity.dart';
import 'package:postpilot/features/request_flow/domain/entities/flow_settings.dart';
import 'package:postpilot/features/request_flow/domain/entities/sent_request.dart';
import 'package:postpilot/features/safety/data/safety_prefs.dart';
import 'package:postpilot/features/safety/domain/services/production_guard.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'cleanup_support.dart';

const _on = RequestSettings(flow: FlowSettings(cleanup: CleanupSettings(enabled: true)));

SentRequest _sent(String name, Object? answer, {String? environment = 'Staging', String url = '{{baseUrl}}/partners'}) => SentRequest(
      request: createRequest(name: name, url: url),
      response: ApiResponseEntity(
        statusCode: 200,
        statusMessage: 'OK',
        headers: const {},
        bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(answer))),
        duration: const Duration(milliseconds: 5),
      ),
      settings: _on,
      dataVariables: const {},
      environment: environment,
    );

/// Sends nothing: answers each delete as told, and holds one back while a test looks at the busy state.
final class _FakeSender implements CleanupSender {
  final Set<String> failNames;
  final String failReason;
  Completer<void>? gate;
  final List<int> sent = [];

  _FakeSender({this.failNames = const {}, this.failReason = 'HTTP 404: Record does not exist.'});

  @override
  Future<CleanupPrepared> prepare(CleanupEntry entry) async => CleanupPrepared.ready(entry, entry.plan.request ?? createRequest());

  @override
  Future<CleanupResult> send(CleanupPrepared prepared) async {
    sent.add(prepared.entry.id);
    final hold = gate;
    if (hold != null) await hold.future;
    return failNames.contains(prepared.entry.requestName)
        ? CleanupResult(prepared.entry, CleanupState.failed, failReason)
        : CleanupResult(prepared.entry, CleanupState.deleted);
  }
}

final class _Environments implements EnvironmentRepository {
  final String name;
  _Environments(this.name);

  @override
  Stream<EnvironmentEntity?> watchActive() => Stream.value(EnvironmentEntity(id: 1, name: name, isActive: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A ledger holding a created, not deleted, failed, not cleaned up and deleted entry.
Future<(CleanupLedger, _FakeSender)> _mixedLedger() async {
  final sender = _FakeSender(failNames: {'Create C'}, failReason: 'HTTP 404: Record does not exist, and this is a long explanation the server gave so that it has to wrap onto more than one line');
  final ledger = CleanupLedger(sender);
  await ledger.recordSend(_sent('Create A', {'id': 1}));
  await ledger.recordSend(_sent('Create B', {'id': 2}, url: '{{odooUrl}}/json/2/res.partner/create'));
  await ledger.recordSend(_sent('Create C', {'id': 3}));
  await ledger.recordSend(_sent('Create D', {'ok': true}));
  await ledger.recordSend(_sent('Create E', {'id': 5}));
  await ledger.cleanup([ledger.entries[2], ledger.entries[4]]);
  return (ledger, sender);
}

Future<void> _open(WidgetTester tester, Widget Function(BuildContext) dialog, {required double width, ThemeData? theme, double height = 900}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: theme ?? AppTheme.light, home: const Scaffold(body: SizedBox.expand())));
  unawaited(showDialog<void>(context: tester.element(find.byType(Scaffold)), builder: dialog));
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, Widget child, {required double width, ThemeData? theme, double height = 900}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: theme ?? AppTheme.light, home: Scaffold(body: Padding(padding: const EdgeInsets.all(12), child: child))));
  await tester.pump();
}

void main() {
  tearDown(() => locator.reset());

  group('the ledger dialog', () {
    for (final (themeName, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
      for (final width in [1200.0, 420.0]) {
        testWidgets('shows every state without overflowing, $themeName, ${width.toInt()} px wide', (tester) async {
          final (ledger, _) = await _mixedLedger();
          await _open(tester, (_) => CleanupLedgerDialog(ledger: ledger), width: width, theme: theme);

          expect(find.text('Cleanup ledger'), findsOneWidget);
          expect(find.text('Records created in this session'), findsOneWidget);
          expect(find.text('Kept until you close PostPilot'), findsOneWidget);
          expect(find.text('Delete all pending (3)'), findsOneWidget, reason: 'A, B and the failed C can still be deleted');
          expect(find.text('Clear finished'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // The list is long: each entry is found by scrolling to it, and none of them overflows on the way.
          for (final (text, why) in [
            ('Create E', 'deleted'),
            ('No id found in the response', 'not cleaned up'),
            ('HTTP 404: Record does not exist', 'failed, with the reason'),
            ('Retry', 'the failed one can be tried again'),
            ('Odoo unlink res.partner [2]', 'an Odoo create'),
            ('DELETE {{baseUrl}}/partners/1', 'a REST create'),
          ]) {
            await tester.scrollUntilVisible(find.textContaining(text), 120, scrollable: find.byType(Scrollable).first);
            expect(find.textContaining(text), findsOneWidget, reason: why);
            expect(tester.takeException(), isNull, reason: why);
          }
        });
      }
    }

    testWidgets('is an empty page that says how to get entries when nothing was created', (tester) async {
      final ledger = CleanupLedger(_FakeSender());
      await _open(tester, (_) => CleanupLedgerDialog(ledger: ledger), width: 900);

      expect(find.text('Nothing was created yet'), findsOneWidget);
      expect(find.textContaining('Clean up what this request creates'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete all pending (0)')).onPressed, isNull);
      expect(find.text('Clear finished'), findsNothing);
    });

    testWidgets('Delete on one entry deletes only it; its tile then says Deleted and offers no delete', (tester) async {
      final sender = _FakeSender();
      final ledger = CleanupLedger(sender);
      await ledger.recordSend(_sent('Create A', {'id': 1}));
      await ledger.recordSend(_sent('Create B', {'id': 2}));
      await _open(tester, (_) => CleanupLedgerDialog(ledger: ledger), width: 900);

      await tester.tap(find.byKey(const ValueKey('cleanup-delete-1')));
      await tester.pumpAndSettle();

      expect(sender.sent, [1]);
      expect(ledger.byId(1)!.state, CleanupState.deleted);
      expect(ledger.byId(2)!.state, CleanupState.pending);
      expect(find.byKey(const ValueKey('cleanup-delete-1')), findsNothing);
      expect(find.byKey(const ValueKey('cleanup-delete-2')), findsOneWidget);
      expect(find.text('Delete all pending (1)'), findsOneWidget);
    });

    testWidgets('Delete all pending goes newest first, shows its label and a spinner while it works, and ends with every entry settled', (tester) async {
      final sender = _FakeSender()..gate = Completer<void>();
      final ledger = CleanupLedger(sender);
      for (final name in ['Create A', 'Create B', 'Create C']) {
        await ledger.recordSend(_sent(name, {'id': 1}));
      }
      await _open(tester, (_) => CleanupLedgerDialog(ledger: ledger), width: 900);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete all pending (3)'));
      await tester.pump();

      expect(find.text('Deleting…'), findsWidgets, reason: 'the button keeps its words while it works');
      expect(find.descendant(of: find.byType(FilledButton), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed, isNull, reason: 'not twice');
      expect(sender.sent, [3], reason: 'the first one is out, the gate holds it');

      sender.gate!.complete();
      await tester.pumpAndSettle();

      expect(sender.sent, [3, 2, 1]);
      expect(ledger.entries.map((e) => e.state), everyElement(CleanupState.deleted));
      expect(find.text('Everything this session created has been dealt with.'), findsOneWidget);
    });

    testWidgets('Forget removes an entry without deleting anything, and Clear finished removes the dealt-with ones', (tester) async {
      final (ledger, sender) = await _mixedLedger();
      final sentBefore = sender.sent.length;
      await _open(tester, (_) => CleanupLedgerDialog(ledger: ledger), width: 900);

      await tester.tap(find.byKey(ValueKey('cleanup-forget-${ledger.entries.last.id}'))); // Create E, deleted
      await tester.pumpAndSettle();
      expect(ledger.entries.map((e) => e.requestName), ['Create A', 'Create B', 'Create C', 'Create D']);
      expect(sender.sent, hasLength(sentBefore), reason: 'forgetting sends nothing');

      await tester.tap(find.text('Clear finished'));
      await tester.pumpAndSettle();
      expect(ledger.entries.map((e) => e.requestName), ['Create A', 'Create B', 'Create C'], reason: 'Create D was not cleaned up: nothing more to do');
      expect(find.text('Clear finished'), findsNothing);
    });

    testWidgets('a failed delete shows the reason on its tile and can be retried', (tester) async {
      final sender = _FakeSender(failNames: {'Create A'});
      final ledger = CleanupLedger(sender);
      await ledger.recordSend(_sent('Create A', {'id': 1}));
      await _open(tester, (_) => CleanupLedgerDialog(ledger: ledger), width: 900);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('HTTP 404: Record does not exist.'), findsOneWidget);
      expect(find.textContaining('Failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('the panel under a finished run', () {
    Future<(CleanupLedger, _FakeSender, int)> runWith(List<String> names, {_FakeSender? sender}) async {
      final fake = sender ?? _FakeSender();
      final ledger = CleanupLedger(fake);
      await ledger.recordSend(_sent('Before the run', {'id': 99}));
      final mark = ledger.mark;
      for (final (i, name) in names.indexed) {
        await ledger.recordSend(_sent(name, {'id': 10 + i}));
      }
      return (ledger, fake, mark);
    }

    for (final (themeName, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
      for (final width in [1200.0, 420.0]) {
        testWidgets('says what the run created and lists it newest first, $themeName, ${width.toInt()} px wide', (tester) async {
          final (ledger, _, mark) = await runWith(['Create A', 'Create B', 'Create C']);
          await ledger.recordSend(_sent('No id one', {'ok': true}));
          await _show(tester, Column(children: [const Spacer(), RunCleanupPanel(since: mark, ledger: ledger)]), width: width, theme: theme);
          final narrow = width < 480;

          expect(find.text('3 records were created by this run'), findsOneWidget);
          expect(find.text('Delete them'), findsOneWidget);
          expect(find.text('Keep'), findsOneWidget);
          expect(find.textContaining('Before the run'), findsNothing, reason: 'made before the run started');
          if (narrow) {
            // A narrow dialog has no room for the list beside the results: the panel stays a short bar, Review opens the list.
            expect(find.text('Review'), findsOneWidget);
            expect(find.textContaining('Create C'), findsNothing);
            expect(find.textContaining('1 create cannot be undone'), findsOneWidget);
            expect(tester.getSize(find.byKey(const ValueKey('run-cleanup-panel'))).height, lessThan(220), reason: 'a short bar (title, buttons, one warning line): the list is not part of it');
            await tester.tap(find.text('Review'));
            await tester.pumpAndSettle();
            expect(find.text('What this run created'), findsOneWidget);
            expect(find.text('Delete them (3)'), findsOneWidget);
          } else {
            expect(find.text('Review'), findsNothing);
          }
          expect(find.textContaining('Nothing is deleted until you press Delete them'), findsOneWidget, reason: 'in the panel, or in Review');
          expect(find.textContaining('No id one: No id found'), findsOneWidget, reason: 'a create that cannot be undone is said, not hidden');
          final order = [for (final name in ['Create C', 'Create B', 'Create A']) tester.getTopLeft(find.textContaining(name)).dy];
          expect(order, orderedEquals([...order]..sort()), reason: 'newest first');
          expect(tester.widgetList<Checkbox>(find.byType(Checkbox)).map((c) => c.value), [true, true, true]);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('in a narrow dialog Review is where the ticks are taken off, and its Delete them deletes what is ticked', (tester) async {
      final (ledger, sender, mark) = await runWith(['Create A', 'Create B', 'Create C']);
      await _show(tester, RunCleanupPanel(since: mark, ledger: ledger), width: 420);

      await tester.tap(find.byKey(const ValueKey('run-cleanup-review')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('run-cleanup-row-${mark + 1}'))); // untick Create A
      await tester.pump();
      expect(find.text('Delete them (2)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('run-cleanup-review-delete')));
      await tester.pumpAndSettle();

      expect(sender.sent, [mark + 3, mark + 2], reason: 'newest first, the unticked one stays');
      expect(ledger.byId(mark + 1)!.state, CleanupState.pending);
      expect(find.text('Delete them (0)'), findsOneWidget, reason: 'Create A stays unticked, so nothing more is on offer');
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('run-cleanup-review-delete'))).onPressed, isNull);
      await tester.tap(find.text('Close').first);
      await tester.pumpAndSettle();
      expect(find.text('What this run created'), findsNothing);
      expect(find.text('Delete them'), findsOneWidget);
    });

    testWidgets('shows nothing when the run created nothing', (tester) async {
      final (ledger, _, _) = await runWith([]);
      await _show(tester, RunCleanupPanel(since: ledger.mark, ledger: ledger), width: 900);

      expect(find.byKey(const ValueKey('run-cleanup-panel')), findsNothing);
    });

    testWidgets('Delete them deletes the ticked entries only, then says what it did', (tester) async {
      final (ledger, sender, mark) = await runWith(['Create A', 'Create B', 'Create C']);
      await _show(tester, RunCleanupPanel(since: mark, ledger: ledger), width: 900);

      await tester.tap(find.byKey(ValueKey('run-cleanup-row-${mark + 2}'))); // untick Create B
      await tester.pump();
      expect(tester.widgetList<Checkbox>(find.byType(Checkbox)).map((c) => c.value), [true, false, true]);
      await tester.tap(find.byKey(const ValueKey('run-cleanup-delete')));
      await tester.pumpAndSettle();

      expect(sender.sent, [mark + 3, mark + 1], reason: 'newest first, the unticked one stays');
      expect(ledger.byId(mark + 2)!.state, CleanupState.pending);
      expect(find.text('Delete them'), findsOneWidget, reason: 'one is still left to delete');
    });

    testWidgets('keeps its label and shows a spinner while it deletes; Keep is unavailable meanwhile', (tester) async {
      final sender = _FakeSender()..gate = Completer<void>();
      final (ledger, _, mark) = await runWith(['Create A', 'Create B'], sender: sender);
      await _show(tester, RunCleanupPanel(since: mark, ledger: ledger), width: 900);

      await tester.tap(find.byKey(const ValueKey('run-cleanup-delete')));
      await tester.pump();

      expect(find.text('Deleting…'), findsOneWidget);
      expect(find.text('Deleting what this run created…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(tester.widget<TextButton>(find.byKey(const ValueKey('run-cleanup-keep'))).onPressed, isNull);

      sender.gate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('2 records were created by this run, and deleted'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.byKey(const ValueKey('run-cleanup-delete')), findsNothing);
    });

    testWidgets('a failed delete is shown on its row with the reason, the others are deleted, and it can be tried again', (tester) async {
      final sender = _FakeSender(failNames: {'Create B'});
      final (ledger, _, mark) = await runWith(['Create A', 'Create B', 'Create C'], sender: sender);
      await _show(tester, RunCleanupPanel(since: mark, ledger: ledger), width: 900);

      await tester.tap(find.byKey(const ValueKey('run-cleanup-delete')));
      await tester.pumpAndSettle();

      expect(sender.sent, hasLength(3), reason: 'one failure does not stop the others');
      expect(find.textContaining('HTTP 404: Record does not exist.'), findsOneWidget);
      expect(find.text('Delete them'), findsOneWidget, reason: 'the failed one is still on offer');
      expect(tester.widgetList<Checkbox>(find.byType(Checkbox)), hasLength(1));
    });

    testWidgets('Keep closes the panel and leaves every record pending in the ledger', (tester) async {
      final (ledger, sender, mark) = await runWith(['Create A']);
      await _show(tester, RunCleanupPanel(since: mark, ledger: ledger), width: 900);

      await tester.tap(find.byKey(const ValueKey('run-cleanup-keep')));
      await tester.pump();

      expect(find.byKey(const ValueKey('run-cleanup-panel')), findsNothing);
      expect(sender.sent, isEmpty);
      expect(ledger.deletableCount, 2);
    });

    testWidgets('"Auto clean up after the run" deletes by itself when the panel appears, newest first', (tester) async {
      final (ledger, sender, mark) = await runWith(['Create A', 'Create B']);
      ledger.autoCleanup = true;

      await _show(tester, RunCleanupPanel(since: mark, ledger: ledger), width: 900);
      await tester.pumpAndSettle();

      expect(sender.sent, [mark + 2, mark + 1]);
      expect(find.text('2 records were created by this run, and deleted'), findsOneWidget);
    });

    testWidgets('on Production the guard asks first: Cancel sends nothing, Send anyway deletes', (tester) async {
      locator.registerSingleton<ProductionGuard>(ProductionGuard(_Environments('Production'), SafetyPrefs()));
      final (ledger, sender, mark) = await runWith(['Create A']);
      await _show(tester, Builder(builder: (context) => Column(children: [RunCleanupPanel(since: mark, ledger: ledger)])), width: 900);

      await tester.tap(find.byKey(const ValueKey('run-cleanup-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Send to Production?'), findsOneWidget);
      expect(find.textContaining('1 of them deletes data'), findsOneWidget);
      expect(find.textContaining('Deleting data is always asked about'), findsOneWidget);
      expect(find.textContaining("Don't ask again"), findsNothing, reason: 'a delete is never silenced');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(sender.sent, isEmpty);
      expect(ledger.byId(mark + 1)!.state, CleanupState.pending);
      expect(find.text('Nothing was deleted.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('run-cleanup-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send anyway'));
      await tester.pumpAndSettle();

      expect(sender.sent, [mark + 1]);
      expect(ledger.byId(mark + 1)!.state, CleanupState.deleted);
    });

    testWidgets('on Staging nothing is asked', (tester) async {
      locator.registerSingleton<ProductionGuard>(ProductionGuard(_Environments('Staging'), SafetyPrefs()));
      final (ledger, sender, mark) = await runWith(['Create A']);
      await _show(tester, RunCleanupPanel(since: mark, ledger: ledger), width: 900);

      await tester.tap(find.byKey(const ValueKey('run-cleanup-delete')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Send to'), findsNothing);
      expect(sender.sent, [mark + 1]);
    });
  });

  group('the runner tick', () {
    testWidgets('"Auto clean up after the run" is a plain checkbox that follows the ledger', (tester) async {
      final ledger = CleanupLedger(_FakeSender());
      await _show(tester, Wrap(children: [AutoCleanupOption(ledger: ledger)]), width: 420);

      expect(tester.widget<Checkbox>(find.byKey(const ValueKey('auto-cleanup'))).value, isFalse);
      await tester.tap(find.byKey(const ValueKey('auto-cleanup')));
      await tester.pump();
      expect(ledger.autoCleanup, isTrue);
      expect(tester.widget<Checkbox>(find.byKey(const ValueKey('auto-cleanup'))).value, isTrue);
      await tester.tap(find.text('Auto clean up after the run'));
      await tester.pump();
      expect(ledger.autoCleanup, isFalse);
    });

    testWidgets('shows nothing where there is no ledger', (tester) async {
      await _show(tester, const Wrap(children: [AutoCleanupOption()]), width: 420);

      expect(find.byType(Checkbox), findsNothing);
    });
  });
}
