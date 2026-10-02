// Find in the response is Ctrl+F on Windows (and Linux) and Cmd+F on macOS,
// driven here with real key events through the same AppShortcuts the app uses.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/shortcuts/app_shortcuts.dart';

void main() {
  Future<int Function()> pumpShortcuts(WidgetTester tester, TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    var found = 0;
    void nothing() {}
    await tester.pumpWidget(
      MaterialApp(
        home: AppShortcuts(
          handlers: ShortcutHandlers(
            sendRequest: nothing,
            newRequest: nothing,
            focusSearch: nothing,
            closeRequest: nothing,
            openHistory: nothing,
            toggleSidebar: nothing,
            findInResponse: () => found++,
          ),
          // A focused text field, like the URL bar or the search box, must not swallow it.
          child: const Scaffold(body: TextField(autofocus: true)),
        ),
      ),
    );
    await tester.pump();
    return () => found;
  }

  Future<void> chord(WidgetTester tester, LogicalKeyboardKey modifier, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  testWidgets('Ctrl+F finds on Windows', (tester) async {
    final found = await pumpShortcuts(tester, TargetPlatform.windows);

    await chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyF);

    expect(found(), 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Ctrl+F finds on Linux', (tester) async {
    final found = await pumpShortcuts(tester, TargetPlatform.linux);

    await chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyF);

    expect(found(), 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Cmd+F finds on macOS', (tester) async {
    final found = await pumpShortcuts(tester, TargetPlatform.macOS);

    await chord(tester, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyF);

    expect(found(), 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on macOS Ctrl+F is left alone, and on Windows Cmd+F is', (tester) async {
    var found = await pumpShortcuts(tester, TargetPlatform.macOS);
    await chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyF);
    expect(found(), 0);

    found = await pumpShortcuts(tester, TargetPlatform.windows);
    await chord(tester, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyF);
    expect(found(), 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('typing the letter f alone does not trigger it', (tester) async {
    final found = await pumpShortcuts(tester, TargetPlatform.windows);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();

    expect(found(), 0);
    debugDefaultTargetPlatformOverride = null;
  });

  test('the shortcut is listed with the right label per platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(AppShortcut.findInResponse.keyLabel, 'Ctrl+F');
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(AppShortcut.findInResponse.keyLabel, 'Cmd+F');
    debugDefaultTargetPlatformOverride = null;
  });
}
