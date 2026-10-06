import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/device_helper/domain/services/device_targets.dart';
import 'package:postpilot/features/device_helper/presentation/device_helper_dialog.dart';

void main() {
  Future<void> open(WidgetTester tester, String url) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Builder(builder: (context) => FilledButton(onPressed: () => DeviceHelperDialog.show(context, initialUrl: url), child: const Text('open')))),
    ));
    await tester.tap(find.text('open'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The rewrite section is at the bottom of a scrolling list, which builds only what is on screen.
    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  const rewriteNote = ValueKey('cleartext-note-rewrite');

  testWidgets('an http:// address is followed by what Android and iOS need to open it', (tester) async {
    await open(tester, 'http://localhost:3000/api');
    // The Android emulator address is http://10.0.2.2:3000/api.
    expect(find.text('http://10.0.2.2:3000/api'), findsOneWidget);
    expect(find.byKey(rewriteNote), findsOneWidget);
    expect(find.text('Plain http:// needs a setting in your app'), findsWidgets);
    expect(find.textContaining('usesCleartextTraffic', findRichText: true), findsWidgets);
    expect(find.textContaining('NSAllowsLocalNetworking', findRichText: true), findsWidgets);
    expect(DeviceTargets.cleartextNote, contains('Info.plist'));
  });

  testWidgets('an https:// address needs no such note', (tester) async {
    await open(tester, 'https://localhost:3000/api');
    expect(find.text('https://10.0.2.2:3000/api'), findsOneWidget);
    expect(find.byKey(rewriteNote), findsNothing);
  });

  testWidgets('without a URL to rewrite there is no rewrite note', (tester) async {
    await open(tester, '');
    expect(find.byKey(rewriteNote), findsNothing);
  });
}
