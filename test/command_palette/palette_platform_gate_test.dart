import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/platform/platform_support.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/command_palette/domain/entities/palette_item.dart';
import 'package:postpilot/features/command_palette/presentation/command_palette_dialog.dart';

const _reason = 'Needs the desktop app: browsers cannot open server sockets';

Future<List<String>> _open(WidgetTester tester, {required bool web}) async {
  final ran = <String>[];
  await tester.binding.setSurfaceSize(const Size(1000, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => CommandPaletteDialog(
                hostContext: context,
                web: web,
                items: [
                  PaletteItem(
                    id: 'mock',
                    title: 'Mock server: serve a collection',
                    subtitle: 'Saved examples answer real HTTP calls on this computer',
                    requires: PlatformFeature.mockServer,
                    run: (_) => ran.add('mock'),
                  ),
                  PaletteItem(id: 'tour', title: 'Take the quick tour', run: (_) => ran.add('tour')),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return ran;
}

void main() {
  testWidgets('in the browser an entry that needs the desktop app shows why instead of its subtitle, and does nothing', (tester) async {
    final ran = await _open(tester, web: true);

    expect(find.text(_reason), findsOneWidget);
    expect(find.text('Saved examples answer real HTTP calls on this computer'), findsNothing);

    await tester.tap(find.textContaining('Mock server'));
    await tester.pumpAndSettle();

    expect(ran, isEmpty);
    expect(find.byType(CommandPaletteDialog), findsOneWidget, reason: 'the palette stays open: nothing was started');
  });

  testWidgets('Enter on that entry does nothing either, while the next entry still runs', (tester) async {
    final ran = await _open(tester, web: true);

    await tester.enterText(find.byType(TextField), 'mock');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(ran, isEmpty);
    expect(find.byType(CommandPaletteDialog), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'quick tour');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(ran, ['tour']);
    expect(find.byType(CommandPaletteDialog), findsNothing);
  });

  testWidgets('on desktop the same entry shows its subtitle and runs', (tester) async {
    final ran = await _open(tester, web: false);

    expect(find.text(_reason), findsNothing);
    expect(find.text('Saved examples answer real HTTP calls on this computer'), findsOneWidget);

    await tester.tap(find.textContaining('Mock server'));
    await tester.pumpAndSettle();

    expect(ran, ['mock']);
    expect(find.byType(CommandPaletteDialog), findsNothing);
  });
}
