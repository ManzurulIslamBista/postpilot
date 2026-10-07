// The network menu: pick a profile, edit its numbers, go back to none; per route with "Same as the whole server".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_network.dart';
import 'package:postpilot/features/mock_server/domain/services/mock_routes.dart';
import 'package:postpilot/features/mock_server/domain/usecases/build_mock_routes_usecase.dart';
import 'package:postpilot/features/mock_server/presentation/mock_network_menu.dart';
import 'package:postpilot/features/mock_server/presentation/mock_scenarios_tab.dart';
import 'package:postpilot/features/mock_server/presentation/mock_server_view_model.dart';
import '../support/in_memory_import_export_fakes.dart';

void main() {
  const menu = ValueKey('network-menu');

  /// A menu wired to a [MockNetwork] the way the dialog wires it: the whole server's, or one route's with [inherit].
  Future<MockNetwork> show(WidgetTester tester, {bool inherit = false, Size size = const Size(900, 900)}) async {
    final network = MockNetwork(DateTime.now);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Align(
            alignment: Alignment.topRight,
            child: MockNetworkMenu(
              profile: inherit ? network.routes['GET /users'] : network.global,
              inherit: inherit,
              onChanged: (p) => setState(() => inherit ? network.setRoute('GET /users', p) : network.setGlobal(p)),
            ),
          ),
        ),
      ),
    ));
    return network;
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(menu));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String name) async {
    await open(tester);
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  testWidgets('offers none and every ready-made profile, applies the one picked, and the button names it', (tester) async {
    final network = await show(tester);
    expect(find.text('Network'), findsOneWidget);
    await open(tester);
    expect(find.text('No throttling'), findsOneWidget);
    for (final p in NetworkProfiles.presets) {
      expect(find.text(p.name), findsOneWidget, reason: p.name);
    }
    expect(find.text('Same as the whole server'), findsNothing, reason: 'only a route has that choice');
    expect(find.text('Edit the numbers…'), findsOneWidget);
    await tester.tap(find.text('3G'));
    await tester.pumpAndSettle();
    expect(network.global!.id, '3g');
    expect(find.text('3G'), findsOneWidget, reason: 'the button names the profile in force');
    expect(find.text('Network'), findsNothing);
    expect(find.byTooltip('Network: 3G. Change it'), findsOneWidget);

    await pick(tester, 'Offline');
    expect(network.global!.offline, isTrue);

    await pick(tester, 'No throttling');
    expect(network.global, isNull);
    expect(network.isIdle, isTrue);
    expect(find.text('Network'), findsOneWidget);
  });

  testWidgets('the numbers can be edited: the copy is named "(edited)" and the ready-made profile stays as it was', (tester) async {
    final network = await show(tester);
    await pick(tester, '3G');
    await pick(tester, 'Edit the numbers…');
    expect(find.text('Edit 3G'), findsOneWidget);
    expect(find.widgetWithText(TextField, '300'), findsOneWidget);
    expect(find.widgetWithText(TextField, '750'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('network-field-First byte after')), '450');
    await tester.enterText(find.byKey(const ValueKey('network-field-Bandwidth (0 = no limit)')), '400');
    await tester.enterText(find.byKey(const ValueKey('network-field-Drop the connection')), '150');
    await tester.enterText(find.byKey(const ValueKey('network-field-statuses')), '503, 200, 429, abc');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final edited = network.global!;
    expect(edited.id, NetworkProfiles.customId);
    expect(edited.name, '3G (edited)');
    expect(edited.latencyMs, 450);
    expect(edited.bandwidthKbps, 400);
    expect(edited.resetPercent, 100, reason: 'a percentage stops at 100');
    expect(edited.jitterPercent, 25, reason: 'what was not touched stays');
    expect(edited.errorStatuses, [503, 429], reason: 'only error statuses are kept');
    expect(find.text('3G (edited)'), findsOneWidget);
    expect(NetworkProfiles.threeG.latencyMs, 300);
    expect(NetworkProfiles.threeG.name, '3G');

    // Editing again keeps the name; Cancel changes nothing.
    await pick(tester, 'Edit the numbers…');
    expect(find.text('Edit 3G (edited)'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(network.global!.latencyMs, 450);
  });

  testWidgets('corruption modes and the offline switch can be changed', (tester) async {
    final network = await show(tester);
    await pick(tester, 'Corrupt answers');
    await pick(tester, 'Edit the numbers…');
    await tester.tap(find.widgetWithText(FilterChip, 'Truncated JSON'));
    await tester.tap(find.widgetWithText(FilterChip, 'Wrong content length'));
    await tester.pump();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Offline'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(network.global!.corruptModes, [NetworkCorruption.malformedJson, NetworkCorruption.wrongContentType]);
    expect(network.global!.offline, isTrue);
  });

  testWidgets('editing flapping: the cycle numbers change, the rest stays', (tester) async {
    final network = await show(tester);
    await pick(tester, 'Flapping');
    await pick(tester, 'Edit the numbers…');
    await tester.enterText(find.byKey(const ValueKey('network-field-Connection up for')), '3');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(network.global!.name, 'Flapping (edited)');
    expect([network.global!.upSeconds, network.global!.downSeconds], [3, 5]);
  });

  testWidgets('on a route: "Same as the whole server" is not set, "No throttling" is a profile of its own that exempts it', (tester) async {
    final network = await show(tester, inherit: true);
    expect(find.text('Network'), findsOneWidget);
    expect(network.routes, isEmpty);
    await open(tester);
    expect(find.text('Same as the whole server'), findsOneWidget);
    await tester.tap(find.text('No throttling'));
    await tester.pumpAndSettle();
    expect(network.routes['GET /users'], same(NetworkProfiles.none));
    expect(find.text('No throttling'), findsOneWidget, reason: 'the button says the route is exempt');

    await pick(tester, 'Slow body');
    expect(network.routes['GET /users']!.id, 'slow-body');
    expect(network.global, isNull, reason: 'only the route was set');

    await pick(tester, 'Same as the whole server');
    expect(network.routes, isEmpty);
    expect(find.text('Network'), findsOneWidget);
  });

  testWidgets('in the Scenarios tab each route has its own network button, and "Back to normal everywhere" clears the network too', (tester) async {
    final db = InMemoryDb();
    final vm = MockServerViewModel(BuildMockRoutesUseCase(db.loader, db.exampleRepository));
    addTearDown(vm.dispose);
    vm.backend.table = MockRouteTable.from([
      const MockSource(requestName: 'List', method: 'GET', url: '{{b}}/users', exampleStatus: 200, exampleBody: '[]', exampleName: 'OK'),
      const MockSource(requestName: 'Ping', method: 'GET', url: '{{b}}/ping', exampleStatus: 200, exampleBody: '{}', exampleName: 'OK'),
    ]);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ListenableBuilder(listenable: vm, builder: (context, _) => MockScenariosTab(vm: vm)),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('scenario-GET /users'));
    expect(find.descendant(of: card, matching: find.byKey(menu)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('scenario-GET /ping')), matching: find.byKey(menu)), findsOneWidget);
    expect(find.text('Back to normal everywhere'), findsNothing, reason: 'nothing is going wrong yet');

    await tester.tap(find.descendant(of: card, matching: find.byKey(menu)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offline'));
    await tester.pumpAndSettle();
    expect(vm.network.routes['GET /users']!.offline, isTrue);
    expect(vm.network.routes.containsKey('GET /ping'), isFalse, reason: 'only that route');
    expect(vm.network.global, isNull);
    expect(find.descendant(of: card, matching: find.text('Offline')), findsOneWidget);

    vm.setGlobalNetwork(NetworkProfiles.lossy);
    await tester.pumpAndSettle();
    expect(find.text('Back to normal everywhere'), findsOneWidget);
    await tester.tap(find.text('Back to normal everywhere'));
    await tester.pumpAndSettle();
    expect(vm.network.isIdle, isTrue);
    expect(vm.network.routes, isEmpty);
    expect(vm.network.global, isNull);
    expect(find.text('Back to normal everywhere'), findsNothing);
  });

  testWidgets('on a phone the button is an icon until a profile is in force', (tester) async {
    final network = await show(tester, size: const Size(360, 700));
    expect(find.text('Network'), findsNothing);
    expect(find.byIcon(Icons.network_check), findsOneWidget);
    expect(find.byTooltip('Simulate a slow, lossy or offline network'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Align(alignment: Alignment.topRight, child: MockNetworkMenu(profile: NetworkProfiles.highLatency, onChanged: (_) {}))),
    ));
    expect(network.isIdle, isTrue);
    expect(find.text('High latency + timeouts'), findsOneWidget);
    expect(find.byTooltip('Network: High latency + timeouts. Change it'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
