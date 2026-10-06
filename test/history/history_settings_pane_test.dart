// Settings > History: the switch, the limits and the Clear history button with its confirmation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/history/domain/repositories/history_repository.dart';
import 'package:postpilot/features/settings/data/history_prefs.dart';
import 'package:postpilot/features/settings/presentation/widgets/history_settings_pane.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_history_store.dart';

void main() {
  late InMemoryHistoryStore store;
  late HistoryPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await locator.reset();
    prefs = HistoryPrefs();
    store = InMemoryHistoryStore();
    locator
      ..registerSingleton<HistoryPrefs>(prefs)
      ..registerSingleton<HistoryRepository>(store);
  });
  tearDown(() async {
    prefs.dispose();
    await locator.reset();
  });

  Future<void> pumpPane(WidgetTester tester, {Size size = const Size(780, 900), bool dark = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: HistorySettingsPane())),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    for (final size in [const Size(780, 900), const Size(420, 900)]) {
      testWidgets('shows the defaults and fits the screen (${dark ? 'dark' : 'light'}, ${size.width.toInt()} px)', (tester) async {
        await pumpPane(tester, size: size, dark: dark);

        expect(find.text('Keep request/response bodies in history'), findsOneWidget);
        expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue, reason: 'bodies are kept by default');
        final fields = find.byType(TextField);
        expect([for (var i = 0; i < 3; i++) tester.widget<TextField>(fields.at(i)).controller!.text], ['1000', '0', '256']);
        expect(find.text('Clear history'), findsNWidgets(2), reason: 'the row title and its button');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the switch is saved: bodies off is what the next send sees', (tester) async {
    await pumpPane(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect((await prefs.limits()).keepBodies, isFalse);
    expect((await SharedPreferences.getInstance()).getBool('history.keepBodies'), isFalse);
  });

  testWidgets('the limits are saved as they are typed, within their range', (tester) async {
    await pumpPane(tester);
    final fields = find.byType(TextField);

    await tester.enterText(fields.at(0), '250');
    await tester.enterText(fields.at(1), '30');
    await tester.enterText(fields.at(2), '64');
    await tester.pumpAndSettle();

    final limits = await prefs.limits();
    expect((limits.maxEntries, limits.retentionDays, limits.maxBodyBytes), (250, 30, 64 * 1024));

    await tester.enterText(fields.at(0), '1');
    await tester.pumpAndSettle();
    expect((await prefs.limits()).maxEntries, 10, reason: 'below the smallest limit it is the smallest');
  });

  testWidgets('Clear history asks first: Cancel keeps everything, Clear history empties it and says so', (tester) async {
    await pumpPane(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Clear history'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Delete every recorded request'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.clears, 0);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Clear history'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
    await tester.pumpAndSettle();

    expect(store.clears, 1);
    expect(find.text('History is empty now.'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Clear history')).onPressed, isNotNull);
  });
}
