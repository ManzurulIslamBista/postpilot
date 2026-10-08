// The one place the cleanup ledger is found: a single entry in the command palette's tools, which opens the dialog.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/cleanup_ledger/domain/entities/cleanup_entry.dart';
import 'package:postpilot/features/cleanup_ledger/domain/services/cleanup_executor.dart';
import 'package:postpilot/features/cleanup_ledger/presentation/view_models/cleanup_ledger.dart';
import 'package:postpilot/features/command_palette/domain/services/palette_search.dart';
import 'package:postpilot/features/command_palette/presentation/palette_items.dart';

final class _NoSender implements CleanupSender {
  @override
  Future<CleanupPrepared> prepare(CleanupEntry entry) => throw UnimplementedError();

  @override
  Future<CleanupResult> send(CleanupPrepared prepared) => throw UnimplementedError();
}

void main() {
  tearDown(() => locator.reset());

  test('the tools list holds exactly one cleanup entry, and a search for what people would type finds it', () {
    final tools = PaletteItems.tools();
    final entries = tools.where((i) => i.id.startsWith('cleanup')).toList();

    expect(entries.map((i) => i.id), ['cleanup.ledger']);
    expect(entries.single.title, 'Cleanup ledger: records created in this session');
    expect(tools.map((i) => i.id).toSet(), hasLength(tools.length), reason: 'every palette id is unique');
    for (final query in ['cleanup', 'clean up', 'unlink', 'delete created', 'ledger', 'staging']) {
      final hits = PaletteSearch.search(tools, query);
      expect(hits.map((h) => h.item.id), contains('cleanup.ledger'), reason: query);
    }
  });

  testWidgets('running the entry opens the ledger dialog on the registered ledger', (tester) async {
    locator.registerSingleton<CleanupLedger>(CleanupLedger(_NoSender()));
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const Scaffold(body: SizedBox.expand())));
    final item = PaletteItems.tools().firstWhere((i) => i.id == 'cleanup.ledger');

    item.run(tester.element(find.byType(Scaffold)));
    await tester.pumpAndSettle();

    expect(find.text('Cleanup ledger'), findsOneWidget);
    expect(find.text('Nothing was created yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
