// A separate file from the socket tests: a test suite that uses the widget test
// binding gets a fake HttpClient that answers 400 to everything.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/core/utils/variable_resolver.dart';
import 'package:postpilot/features/realtime/data/realtime_session.dart';
import 'package:postpilot/features/realtime/presentation/realtime_dialog.dart';
import 'package:postpilot/features/realtime/presentation/realtime_view_model.dart';

void main() {
  setUp(() => locator.reset());
  tearDown(() => locator.reset());

  Future<void> open(WidgetTester tester, RealtimeViewModel model) async {
    locator.registerFactory<RealtimeViewModel>(() => model);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Builder(builder: (context) => FilledButton(onPressed: () => RealtimeDialog.show(context), child: const Text('open')))),
    ));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the button reads Cancel while connecting and works', (tester) async {
    final never = Completer<VariableResolver>();
    final model = RealtimeViewModel(const RealtimeConnector(), () => never.future)..url = 'wss://a.test/socket';
    await open(tester, model);
    expect(find.text('Connect'), findsOneWidget);
    model.connect().ignore();
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Disconnect'), findsNothing);
    expect(find.text('Connecting…'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(model.status, RealtimeStatus.disconnected);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
  });

  testWidgets('without live SSE the option is disabled and the reason is shown', (tester) async {
    final model = RealtimeViewModel(const RealtimeConnector(supportsLiveSse: false), () async => VariableResolver({}));
    await open(tester, model);
    final picker = tester.widget<SegmentedButton<RealtimeMode>>(find.byType(SegmentedButton<RealtimeMode>));
    expect(picker.segments.map((s) => s.enabled), [true, false]);
    expect(find.textContaining('cannot be streamed live in the browser build'), findsOneWidget);
  });

  testWidgets('with live SSE there is no note and both modes are enabled', (tester) async {
    final model = RealtimeViewModel(const RealtimeConnector(supportsLiveSse: true), () async => VariableResolver({}));
    await open(tester, model);
    final picker = tester.widget<SegmentedButton<RealtimeMode>>(find.byType(SegmentedButton<RealtimeMode>));
    expect(picker.segments.map((s) => s.enabled), [true, true]);
    expect(find.textContaining('cannot be streamed live'), findsNothing);
  });
}
