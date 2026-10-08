// Where the user finds the refactoring tools: two command palette entries and a keyboard shortcut. The shortcut had to
// be Ctrl+Shift+F, because Ctrl+Shift+H already opens the history.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/shortcuts/app_shortcuts.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/command_palette/presentation/palette_items.dart';
import 'package:postpilot/features/workspace_refactor/domain/entities/refactor_receipt.dart';
import 'package:postpilot/features/workspace_refactor/domain/services/refactor_applier.dart';
import 'package:postpilot/features/workspace_refactor/presentation/view_models/workspace_refactor_view_model.dart';

import 'refactor_fakes.dart';
import 'refactor_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the command palette', () {
    final items = {for (final item in PaletteItems.tools()) item.id: item};

    test('has "Find and replace in workspace", showing its shortcut', () {
      final item = items['refactor.findReplace']!;
      expect(item.title, 'Find and replace in workspace');
      expect(item.shortcut, AppShortcut.findReplaceInWorkspace.keyLabel);
      expect(item.keywords, containsAll(['find', 'replace', 'regex']));
    });

    test('has "Rename a variable everywhere", which also answers to "unused"', () {
      final item = items['refactor.rename']!;
      expect(item.title, 'Rename a variable everywhere');
      expect(item.keywords, containsAll(['rename', 'variable', 'unused', 'undefined']));
    });

    test('each is listed once, and no other entry has the same title', () {
      final all = PaletteItems.tools();
      for (final id in ['refactor.findReplace', 'refactor.rename']) {
        expect(all.where((i) => i.id == id), hasLength(1), reason: id);
        final title = items[id]!.title;
        expect(all.where((i) => i.title == title), hasLength(1), reason: title);
      }
    });

    group('opening them', () {
      late FixedSource source;

      setUp(() async {
        await locator.reset();
        source = FixedSource(acmeWorkspace());
        locator.registerFactory<WorkspaceRefactorViewModel>(
          () => WorkspaceRefactorViewModel(source, RefactorApplier(source, RecordingWriter()), RefactorUndoStore(), searchDelay: Duration.zero),
        );
      });
      tearDown(() => locator.reset());

      Future<void> run(WidgetTester tester, String id) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const Scaffold(body: SizedBox())));
        items[id]!.run(tester.element(find.byType(Scaffold)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }

      testWidgets('find and replace opens on its own tab', (tester) async {
        await run(tester, 'refactor.findReplace');
        expect(find.text('Refactor the workspace'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Find'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('rename opens on the rename tab', (tester) async {
        await run(tester, 'refactor.rename');
        expect(find.text('Refactor the workspace'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Variable to rename'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('the shortcut', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('is Ctrl+Shift+F, or Cmd+Shift+F on a Mac, and takes nothing from the others', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(AppShortcut.findReplaceInWorkspace.keyLabel, 'Ctrl+Shift+F');
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(AppShortcut.findReplaceInWorkspace.keyLabel, 'Cmd+Shift+F');

      // Ctrl+Shift+H is the history, so find-and-replace could not have it.
      expect(AppShortcut.openHistory.key, LogicalKeyboardKey.keyH);
      expect(AppShortcut.openHistory.shift, isTrue);
      final clashes = [
        for (final s in AppShortcut.values)
          if (s != AppShortcut.findReplaceInWorkspace && s.key == AppShortcut.findReplaceInWorkspace.key && s.shift == AppShortcut.findReplaceInWorkspace.shift) s,
      ];
      expect(clashes, isEmpty);
    });

    testWidgets('fires its handler from a focused text field, and Ctrl+F alone still finds in the response', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final fired = <String>[];
      void nothing() {}
      await tester.pumpWidget(
        MaterialApp(
          home: AppShortcuts(
            handlers: ShortcutHandlers(
              sendRequest: nothing,
              newRequest: nothing,
              focusSearch: nothing,
              closeRequest: nothing,
              openHistory: () => fired.add('history'),
              toggleSidebar: nothing,
              findInResponse: () => fired.add('findInResponse'),
              findReplaceInWorkspace: () => fired.add('findReplace'),
            ),
            child: const Scaffold(body: TextField(autofocus: true)),
          ),
        ),
      );
      await tester.pump();

      Future<void> chord(LogicalKeyboardKey key, {bool shift = false}) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      await chord(LogicalKeyboardKey.keyF, shift: true);
      await chord(LogicalKeyboardKey.keyF);
      await chord(LogicalKeyboardKey.keyH, shift: true);

      expect(fired, ['findReplace', 'findInResponse', 'history']);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
