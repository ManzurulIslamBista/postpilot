// The shortcut map as a whole: no two shortcuts collide, every one reaches its own handler through real key
// events, and the help dialog lists them all without overflowing a short window.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/shortcuts/app_shortcuts.dart';
import 'package:postpilot/core/theme/app_theme.dart';

/// What each shortcut is written as on Windows/Linux and on macOS, spelled out by hand.
const _labels = {
  AppShortcut.sendRequest: ('Ctrl+Enter', 'Cmd+Enter'),
  AppShortcut.newRequest: ('Ctrl+N', 'Cmd+N'),
  AppShortcut.focusSearch: ('Ctrl+K', 'Cmd+K'),
  AppShortcut.closeRequest: ('Ctrl+W', 'Cmd+W'),
  AppShortcut.openHistory: ('Ctrl+Shift+H', 'Cmd+Shift+H'),
  AppShortcut.toggleSidebar: ('Ctrl+B', 'Cmd+B'),
  AppShortcut.findInResponse: ('Ctrl+F', 'Cmd+F'),
  AppShortcut.commandPalette: ('Ctrl+Shift+P', 'Cmd+Shift+P'),
  AppShortcut.reopenClosedTab: ('Ctrl+Shift+T', 'Cmd+Shift+T'),
  AppShortcut.focusUrl: ('Ctrl+L', 'Cmd+L'),
  AppShortcut.nextTab: ('Ctrl+Page Down', 'Cmd+Page Down'),
  AppShortcut.previousTab: ('Ctrl+Page Up', 'Cmd+Page Up'),
  AppShortcut.duplicateRequest: ('Ctrl+D', 'Cmd+D'),
  AppShortcut.saveResponseExample: ('Ctrl+Shift+S', 'Cmd+Shift+S'),
  AppShortcut.switchEnvironment: ('Ctrl+Shift+E', 'Cmd+Shift+E'),
  AppShortcut.runCollection: ('Ctrl+Shift+R', 'Cmd+Shift+R'),
};

/// A widget test that runs as Windows and puts the platform back before the framework checks it was left alone
/// (`addTearDown` runs too late for that check).
void testOnWindows(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('the map', () {
    test('every shortcut is in the hand-written label table, so a new one cannot be added unnoticed', () {
      expect(AppShortcut.values.toSet(), _labels.keys.toSet());
    });

    test('no two shortcuts share a key and shift state, so none can shadow another on any platform', () {
      final seen = <(LogicalKeyboardKey, bool)>{};
      for (final shortcut in AppShortcut.values) {
        expect(seen.add((shortcut.key, shortcut.shift)), isTrue, reason: '${shortcut.name} repeats an earlier key chord');
      }
    });

    test('the activators are distinct too, with and without the browser (Alt) remapping', () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS]) {
        debugDefaultTargetPlatformOverride = platform;
        final activators = {
          for (final s in AppShortcut.values) (s.activator.trigger, s.activator.control, s.activator.meta, s.activator.alt, s.activator.shift),
        };
        expect(activators, hasLength(AppShortcut.values.length), reason: '$platform');
      }
    });

    test('descriptions are unique and non-empty', () {
      final descriptions = AppShortcut.values.map((s) => s.description).toList();
      expect(descriptions.toSet(), hasLength(descriptions.length));
      expect(descriptions.every((d) => d.trim().isNotEmpty), isTrue);
    });

    for (final entry in _labels.entries) {
      test('${entry.key.name} reads ${entry.value.$1} on Windows and ${entry.value.$2} on macOS', () {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        expect(entry.key.keyLabel, entry.value.$1);
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        expect(entry.key.keyLabel, entry.value.$2);
      });
    }

    test('a handler that was not provided does nothing instead of throwing', () {
      void nothing() {}
      final handlers = ShortcutHandlers(
        sendRequest: nothing,
        newRequest: nothing,
        focusSearch: nothing,
        closeRequest: nothing,
        openHistory: nothing,
        toggleSidebar: nothing,
        findInResponse: nothing,
      );
      for (final shortcut in AppShortcut.values) {
        expect(() => handlers.handlerFor(shortcut)(), returnsNormally, reason: shortcut.name);
      }
    });
  });

  group('real key events reach the right handler', () {
    Future<List<String>> pump(WidgetTester tester) async {
      final fired = <String>[];
      VoidCallback record(String name) =>
          () => fired.add(name);
      await tester.pumpWidget(
        MaterialApp(
          home: AppShortcuts(
            handlers: ShortcutHandlers(
              sendRequest: record('send'),
              newRequest: record('new'),
              focusSearch: record('search'),
              closeRequest: record('close'),
              openHistory: record('history'),
              toggleSidebar: record('sidebar'),
              findInResponse: record('find'),
              openCommandPalette: record('palette'),
              reopenClosedTab: record('reopen'),
              focusUrl: record('focusUrl'),
              nextTab: record('nextTab'),
              previousTab: record('previousTab'),
              duplicateRequest: record('duplicate'),
              saveResponseExample: record('saveExample'),
              switchEnvironment: record('switchEnvironment'),
              runCollection: record('runCollection'),
            ),
            // A focused text field, like the URL bar, must not swallow any of them.
            child: const Scaffold(body: TextField(autofocus: true)),
          ),
        ),
      );
      await tester.pump();
      return fired;
    }

    Future<void> chord(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    const expected = {
      'focusUrl': (LogicalKeyboardKey.keyL, false),
      'nextTab': (LogicalKeyboardKey.pageDown, false),
      'previousTab': (LogicalKeyboardKey.pageUp, false),
      'duplicate': (LogicalKeyboardKey.keyD, false),
      'saveExample': (LogicalKeyboardKey.keyS, true),
      'switchEnvironment': (LogicalKeyboardKey.keyE, true),
      'runCollection': (LogicalKeyboardKey.keyR, true),
      // The older ones are still where they were.
      'send': (LogicalKeyboardKey.enter, false),
      'new': (LogicalKeyboardKey.keyN, false),
      'palette': (LogicalKeyboardKey.keyP, true),
      'reopen': (LogicalKeyboardKey.keyT, true),
    };

    for (final entry in expected.entries) {
      testOnWindows('${entry.value.$2 ? 'Ctrl+Shift+' : 'Ctrl+'}${entry.value.$1.keyLabel} fires only ${entry.key}', (tester) async {
        final fired = await pump(tester);

        await chord(tester, entry.value.$1, shift: entry.value.$2);

        expect(fired, [entry.key]);
      });
    }

    testOnWindows('the same key without Ctrl, or with the wrong Shift state, fires nothing', (tester) async {
      final fired = await pump(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await chord(tester, LogicalKeyboardKey.keyS); // Ctrl+S alone is not Ctrl+Shift+S
      await chord(tester, LogicalKeyboardKey.keyR); // nor is Ctrl+R alone

      expect(fired, isEmpty);
    });
  });

  group('the help dialog', () {
    testOnWindows('lists every shortcut with its keys, and scrolls instead of overflowing a short window', (tester) async {
      tester.view.physicalSize = const Size(700, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const Scaffold(body: ShortcutsHelpDialog())));
      await tester.pump();

      for (final shortcut in AppShortcut.values) {
        expect(find.text(shortcut.description), findsOneWidget, reason: shortcut.name);
        expect(find.text(shortcut.keyLabel), findsOneWidget, reason: shortcut.name);
      }
      expect(tester.takeException(), isNull);
    });
  });
}
