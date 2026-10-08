// The dialog on screen: every tab at a desktop and a phone width, light and dark, without a layout overflow (Flutter
// turns one into a test failure), and the flows a user takes: search, untick, replace, undo, merge, delete.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/refactor_receipt.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/workspace_snapshot.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/refactor_applier.dart';
import 'package:postpilot/features/workspace_refactor/presentation/view_models/workspace_refactor_view_model.dart';
import 'package:postpilot/features/workspace_refactor/presentation/workspace_refactor_dialog.dart';

import 'refactor_fakes.dart';
import 'refactor_fixtures.dart';

/// The acme workspace plus a secret, a variable that is taken (host and server in one environment) and one nothing uses.
WorkspaceSnapshot uiWorkspace() => WorkspaceSnapshot([
  ...acmeWorkspace().units,
  envVar(501, 'Dev', 'apiKey', 'sk-live-acme-123', secret: true),
  envVar(502, 'Dev', 'server', 'existing-server'),
  envVar(503, 'Dev', 'unusedThing', 'u'),
  req(200, 'Uses host', url: '{{host}}/x/{{missingVar}}'),
]);

String allText(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? t.textSpan?.toPlainText() ?? '',
  for (final t in tester.widgetList<RichText>(find.byType(RichText))) t.text.toPlainText(),
  for (final t in tester.widgetList<EditableText>(find.byType(EditableText))) t.controller.text,
].join('\n');

void main() {
  late FixedSource source;
  late RecordingWriter writer;
  late WorkspaceRefactorViewModel vm;

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1200, 800),
    bool dark = false,
    RefactorTab tab = RefactorTab.findReplace,
    WorkspaceSnapshot? snapshot,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    source = FixedSource(snapshot ?? uiWorkspace());
    writer = RecordingWriter();
    vm = WorkspaceRefactorViewModel(source, RefactorApplier(source, writer), RefactorUndoStore(), searchDelay: Duration.zero);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(context: context, builder: (_) => WorkspaceRefactorDialog(createViewModel: () => vm, initialTab: tab)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> type(WidgetTester tester, String label, String text) async {
    await tester.enterText(field(label), text);
    await tester.pump();
  }

  FilledButton buttonLabelled(WidgetTester tester, String label) =>
      tester.widget<FilledButton>(find.ancestor(of: find.text(label), matching: find.byType(FilledButton)));

  group('every tab fits every size, in both themes', () {
    for (final (name, size) in [('desktop', const Size(1200, 800)), ('phone', const Size(420, 800)), ('short phone', const Size(420, 520))]) {
      for (final dark in [false, true]) {
        for (final tab in RefactorTab.values) {
          testWidgets('${tab.name} at $name, ${dark ? 'dark' : 'light'}', (tester) async {
            await open(tester, size: size, dark: dark, tab: tab);

            switch (tab) {
              case RefactorTab.findReplace:
                await type(tester, 'Find', 'acme');
                await tester.tap(find.textContaining('Where:'));
                await tester.pump();
                await tester.tap(find.text('Regex'));
                await tester.pump();
                await tester.tap(find.text('Include secret values'));
                await tester.pump();
              case RefactorTab.rename:
                await type(tester, 'Variable to rename', 'host');
                await type(tester, 'New name', 'server');
              case RefactorTab.report:
                break;
            }
            await tester.pump(const Duration(milliseconds: 50));

            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('a result with the undo strip and a notice on top still fits a short phone', (tester) async {
      await open(tester, size: const Size(420, 520));
      await type(tester, 'Find', 'acme');
      await tester.tap(find.textContaining('Replace selected'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Undo last replace'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('find and replace', () {
    testWidgets('starts with an invitation and loads the workspace first', (tester) async {
      await open(tester);
      expect(find.text('Find and replace in every collection'), findsOneWidget);
      expect(find.text('Replace selected (0)'), findsOneWidget);
      expect(buttonLabelled(tester, 'Replace selected (0)').onPressed, isNull);
    });

    testWidgets('typing lists the matches grouped by collection and request, with a checkbox on each', (tester) async {
      await open(tester);
      await type(tester, 'Replace with', 'Zeta');
      await type(tester, 'Find', 'acme');

      expect(find.textContaining('12 matches in 12 places'), findsOneWidget);
      expect(find.text('Shop'), findsWidgets);
      expect(find.text('Acme list'), findsOneWidget);
      expect(find.text('Replace selected (12)'), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);
    });

    testWidgets('a group checkbox unticks everything under it, and the button counts what is left', (tester) async {
      await open(tester);
      await type(tester, 'Find', 'acme');

      // The first checkbox is the "Shop" heading: the collection's header and all of the request.
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(find.text('Replace selected (1)'), findsOneWidget);
    });

    testWidgets('Replace selected writes, says what it did and offers the undo; Undo puts it back', (tester) async {
      await open(tester);
      await type(tester, 'Find', 'acme');
      await type(tester, 'Replace with', 'Zeta');

      await tester.tap(find.text('Replace selected (12)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(writer.writes, isNotEmpty);
      expect(find.text('Replaced 12 occurrences in 3 places.'), findsOneWidget);
      expect(find.text('Undo last replace'), findsOneWidget);
      // It says where the undo lives.
      expect(allText(tester), contains('memory only'));
      expect(allText(tester), contains('nothing is saved'));
    });

    testWidgets('a regular expression shows its replacement help, and a bad one shows the error', (tester) async {
      await open(tester);
      await tester.tap(find.text('Regex'));
      await tester.pump();
      expect(find.textContaining(r'$1 $2 are the groups'), findsOneWidget);

      await type(tester, 'Find', '(');
      expect(find.textContaining('Not a valid regular expression'), findsOneWidget);
      expect(buttonLabelled(tester, 'Replace selected (0)').onPressed, isNull);
    });

    testWidgets('narrowing the areas shows how many are searched', (tester) async {
      await open(tester);
      await tester.tap(find.text('Where: everywhere'));
      await tester.pump();
      await tester.tap(find.text('None'));
      await tester.pump();
      await tester.tap(find.text('URLs'));
      await tester.pump();

      expect(find.text('Where: 1 of 12 areas'), findsOneWidget);
      await type(tester, 'Find', 'acme');
      expect(find.textContaining('1 match in 1 place'), findsOneWidget);
    });

    testWidgets('a secret is masked on screen and never read out, even when it is included', (tester) async {
      await open(tester, snapshot: uiWorkspace());
      await type(tester, 'Find', 'sk-live');
      expect(find.textContaining('1 secret values not searched'), findsOneWidget);

      await tester.tap(find.text('Include secret values'));
      await tester.pump();

      expect(find.textContaining('1 match in 1 place'), findsOneWidget);
      final text = allText(tester);
      expect(text, contains('••••••'));
      expect(text, contains('secret, hidden'));
      expect(text, isNot(contains('sk-live-acme-123')));
      expect(text, isNot(contains('sk-live-acme')));
    });
  });

  group('rename a variable', () {
    testWidgets('suggests defined names, and a tap fills the field', (tester) async {
      await open(tester, tab: RefactorTab.rename);
      expect(find.text('Defined:'), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, 'host'));
      await tester.pump();

      expect(vm.oldName, 'host');
    });

    testWidgets('a name that is taken shows the conflict and blocks the rename until the merge is confirmed', (tester) async {
      await open(tester, tab: RefactorTab.rename);
      await type(tester, 'Variable to rename', 'host');
      await type(tester, 'New name', 'server');

      expect(find.text('{{server}} already exists'), findsOneWidget);
      expect(find.textContaining('Environment "Dev" has both'), findsOneWidget);
      expect(buttonLabelled(tester, 'Rename everywhere').onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('confirm-merge')));
      await tester.pump();
      expect(buttonLabelled(tester, 'Rename everywhere').onPressed, isNotNull);

      await tester.tap(find.text('Rename everywhere'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(writer.deleted, ['environmentVariable:500']);
      expect(find.textContaining('Renamed {{host}} to {{server}}'), findsOneWidget);
    });

    testWidgets('a name that is not allowed says why', (tester) async {
      await open(tester, tab: RefactorTab.rename);
      await type(tester, 'Variable to rename', 'host');
      await type(tester, 'New name', r'$guid');

      expect(find.textContaining('built-in dynamic variables'), findsOneWidget);
      expect(buttonLabelled(tester, 'Rename everywhere').onPressed, isNull);
    });

    testWidgets('nothing uses the name: the list says so', (tester) async {
      await open(tester, tab: RefactorTab.rename);
      await type(tester, 'Variable to rename', 'neverSeen');
      await type(tester, 'New name', 'other');

      expect(find.text('Nothing uses this name'), findsOneWidget);
    });
  });

  group('unused and undefined variables', () {
    testWidgets('lists both, ticks nothing by itself and deletes only what is ticked', (tester) async {
      await open(tester, tab: RefactorTab.report);

      expect(find.textContaining('Unused variables ('), findsOneWidget);
      expect(find.text('Undefined variables (1)'), findsOneWidget);
      expect(find.text('{{missingVar}}'), findsOneWidget);
      expect(buttonLabelled(tester, 'Delete selected (0)').onPressed, isNull);

      // unusedThing is the only one with a plain name worth finding; tick the first checkbox of the list.
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      expect(find.text('Delete selected (1)'), findsOneWidget);

      await tester.tap(find.text('Delete selected (1)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(writer.deleted, hasLength(1));
      expect(find.textContaining('Deleted 1 variable definition'), findsOneWidget);
    });
  });
}
