import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/shortcuts/app_shortcuts.dart';
import 'package:postpilot/features/command_palette/domain/services/palette_search.dart';
import 'package:postpilot/features/command_palette/presentation/palette_items.dart';

void main() {
  final calls = <String>[];

  setUp(calls.clear);

  /// id -> (shortcut, what the entry calls)
  final expected = {
    'app.duplicate': (AppShortcut.duplicateRequest, 'duplicate'),
    'app.focus-url': (AppShortcut.focusUrl, 'focusUrl'),
    'app.next-tab': (AppShortcut.nextTab, 'nextTab'),
    'app.previous-tab': (AppShortcut.previousTab, 'previousTab'),
    'app.save-example': (AppShortcut.saveResponseExample, 'saveExample'),
    'app.switch-env': (AppShortcut.switchEnvironment, 'switchEnvironment'),
    'app.run-collection': (AppShortcut.runCollection, 'runCollection'),
  };

  testWidgets('every shell action is a palette entry that shows its shortcut and calls its callback', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));
    final items = {for (final item in PaletteItems.app(
      newRequest: () => calls.add('new'),
      toggleSidebar: () => calls.add('sidebar'),
      openImport: () => calls.add('import'),
      duplicateRequest: () => calls.add('duplicate'),
      nextTab: () => calls.add('nextTab'),
      previousTab: () => calls.add('previousTab'),
      focusUrl: () => calls.add('focusUrl'),
      saveResponseExample: () => calls.add('saveExample'),
      switchEnvironment: () => calls.add('switchEnvironment'),
      runCollection: () => calls.add('runCollection'),
    )) item.id: item};

    for (final entry in expected.entries) {
      final item = items[entry.key];
      expect(item, isNotNull, reason: entry.key);
      expect(item!.shortcut, entry.value.$1.keyLabel, reason: entry.key);
      item.run(context);
      expect(calls.last, entry.value.$2, reason: entry.key);
    }
    expect(calls, hasLength(expected.length));
  });

  test('entries whose callback is not given are left out, and the usual ones stay', () {
    final ids = PaletteItems.app(newRequest: () {}, toggleSidebar: () {}, openImport: () {}).map((i) => i.id).toSet();

    expect(ids.intersection(expected.keys.toSet()), isEmpty);
    expect(ids, containsAll(['app.new', 'app.import', 'app.sidebar', 'app.history', 'app.shortcuts']));
  });

  test('ids and titles are unique across the whole app list, so no entry hides another', () {
    final items = PaletteItems.app(
      newRequest: () {},
      toggleSidebar: () {},
      openImport: () {},
      duplicateRequest: () {},
      nextTab: () {},
      previousTab: () {},
      focusUrl: () {},
      saveResponseExample: () {},
      switchEnvironment: () {},
      runCollection: () {},
    );

    expect(items.map((i) => i.id).toSet(), hasLength(items.length));
    expect(items.map((i) => i.title).toSet(), hasLength(items.length));
  });

  test('typing what a person would type finds them', () {
    final items = PaletteItems.app(
      newRequest: () {},
      toggleSidebar: () {},
      openImport: () {},
      duplicateRequest: () {},
      nextTab: () {},
      previousTab: () {},
      focusUrl: () {},
      saveResponseExample: () {},
      switchEnvironment: () {},
      runCollection: () {},
    );
    String top(String query) => PaletteSearch.search(items, query).first.item.id;

    expect(top('duplicate'), 'app.duplicate');
    expect(top('run collection'), 'app.run-collection');
    expect(top('save example'), 'app.save-example');
    expect(top('environment'), 'app.switch-env');
    expect(top('url bar'), 'app.focus-url');
  });
}
