import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/di/injector.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/settings/domain/entities/app_settings.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'package:postpilot/features/settings/presentation/view_models/request_settings_view_model.dart';
import 'package:postpilot/features/settings/presentation/widgets/request_settings_tab.dart';
import 'fakes/fake_settings_repositories.dart';

const _note = 'Not available in the browser version';

final class _Harness {
  final FakeRequestSettingsRepository requests;
  final FakeSettingsRepository global;
  _Harness(this.requests, this.global);
}

Widget _tree(int requestId, {bool isWeb = false}) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: RequestSettingsTab(requestId: requestId, isWeb: isWeb),
        ),
      ),
    );

void _tabTest(
  String name,
  Future<void> Function(WidgetTester tester, _Harness harness) body, {
  AppSettings global = const AppSettings(),
  Map<int, RequestSettings> stored = const {},
  bool isWeb = false,
}) {
  testWidgets(name, (tester) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final harness = _Harness(FakeRequestSettingsRepository()..stored.addAll(stored), FakeSettingsRepository(global));
    locator.registerFactory<RequestSettingsViewModel>(
      () => RequestSettingsViewModel(harness.requests, harness.global),
    );
    addTearDown(locator.reset);

    await tester.pumpWidget(_tree(7, isWeb: isWeb));
    await tester.pumpAndSettle();
    try {
      await body(tester, harness);
    } finally {
      // Takes the tab down so its view model cancels any save timer still pending.
      await tester.pumpWidget(const SizedBox());
    }
  });
}

List<SegmentedButton<dynamic>> _choiceButtons(WidgetTester tester) =>
    tester.widgetList<SegmentedButton<dynamic>>(find.byWidgetPredicate((w) => w is SegmentedButton)).toList();

/// The `Use global / On / Off` choice of the nth row, as its name.
String _choiceOf(WidgetTester tester, int row) => _choiceButtons(tester)[row].selected.single.toString().split('.').last;

/// Read through `dynamic`: the callback is typed for the private choice enum, so
/// reading it as a `SegmentedButton<dynamic>` would fail its runtime type check.
bool _isEnabled(WidgetTester tester, int row) => (_choiceButtons(tester)[row] as dynamic).onSelectionChanged != null;

Finder _timeoutField() => find.byType(TextField);

String _timeoutText(WidgetTester tester) => tester.widget<TextField>(_timeoutField()).controller!.text;

void main() {
  group('what it shows', () {
    _tabTest('every override starts on "use global", saying what global currently is', (tester, harness) async {
      expect(find.text('Use global (On)'), findsNWidgets(2), reason: 'follow redirects and verify SSL are on by default');
      expect(find.text('Use global (Off)'), findsOneWidget, reason: 'the no-cache header is off by default');
      expect([for (var row = 0; row < 3; row++) _choiceOf(tester, row)], ['useGlobal', 'useGlobal', 'useGlobal']);
      expect(_timeoutText(tester), '');
      expect(find.text('Global: 30 s'), findsOneWidget);
    });

    _tabTest('the hints follow the global settings', (tester, harness) async {
      expect(find.text('Use global (Off)'), findsNWidgets(2), reason: 'follow redirects and verify SSL are off here');
      expect(find.text('Use global (On)'), findsOneWidget, reason: 'the no-cache header is on here');
      expect(find.text('Global: no timeout'), findsOneWidget);
    }, global: const AppSettings(followRedirects: false, verifySsl: false, sendNoCacheHeader: true, requestTimeoutSeconds: 0));

    _tabTest('a change to the global settings shows up without reopening the tab', (tester, harness) async {
      expect(find.text('Global: 30 s'), findsOneWidget);

      harness.global.changeElsewhere(const AppSettings(requestTimeoutSeconds: 8, verifySsl: false));
      await tester.pump(); // the change arrives on a stream, after this frame was built
      await tester.pump();

      expect(find.text('Global: 8 s'), findsOneWidget);
      expect(find.text('Use global (Off)'), findsNWidgets(2), reason: 'verify SSL and the no-cache header');
    });

    _tabTest('shows the overrides this request already has', (tester, harness) async {
      expect(_choiceOf(tester, 0), 'useGlobal');
      expect(_choiceOf(tester, 1), 'off');
      expect(_choiceOf(tester, 2), 'on');
      expect(_timeoutText(tester), '12');
    }, stored: {7: const RequestSettings(verifySsl: false, sendNoCacheHeader: true, timeoutSeconds: 12)});

    _tabTest('a request with none stored shows none, whatever another request has', (tester, harness) async {
      expect(_choiceOf(tester, 1), 'useGlobal');
      expect(_timeoutText(tester), '');
    }, stored: {8: const RequestSettings(verifySsl: false, timeoutSeconds: 3)});
  });

  group('editing', () {
    _tabTest('a choice is written for its request at once, with no delay to wait out', (tester, harness) async {
      await tester.tap(find.text('Off').at(0));
      await tester.pump();

      expect(_choiceOf(tester, 0), 'off');
      expect(harness.requests.saves.single.requestId, 7);
      expect(harness.requests.saves.single.settings, const RequestSettings(followRedirects: false));
    });

    _tabTest('each row sets its own override, and "use global" takes one back', (tester, harness) async {
      await tester.tap(find.text('Off').at(0));
      await tester.tap(find.text('On').at(1));
      await tester.tap(find.text('On').at(2));
      await tester.pump();
      expect([for (var row = 0; row < 3; row++) _choiceOf(tester, row)], ['off', 'on', 'on']);

      await tester.tap(find.text('Use global (On)').at(0));
      await tester.pump();
      expect([for (var row = 0; row < 3; row++) _choiceOf(tester, row)], ['useGlobal', 'on', 'on']);

      expect(
        harness.requests.saves.last.settings,
        const RequestSettings(verifySsl: true, sendNoCacheHeader: true),
      );
    });

    _tabTest('a timeout override is saved, and emptying the field goes back to the global timeout', (tester, harness) async {
      await tester.enterText(_timeoutField(), '9');
      await tester.pump();
      expect(harness.requests.saves.last.settings, const RequestSettings(timeoutSeconds: 9));

      await tester.enterText(_timeoutField(), '');
      await tester.pump();
      expect(harness.requests.saves.last.settings, RequestSettings.none);
    });

    _tabTest('0 is a timeout override of its own: wait forever', (tester, harness) async {
      await tester.enterText(_timeoutField(), '0');
      await tester.pump();

      expect(harness.requests.saves.single.settings, const RequestSettings(timeoutSeconds: 0));
    });

    _tabTest('only digits can be typed into the timeout', (tester, harness) async {
      await tester.enterText(_timeoutField(), '4x2');
      await tester.pump();

      expect(_timeoutText(tester), '42');
      expect(harness.requests.saves.single.settings, const RequestSettings(timeoutSeconds: 42));
    });

    _tabTest('the reset button is off until there is something to reset, then puts everything back to global', (tester, harness) async {
      final reset = find.widgetWithText(TextButton, 'Use global settings for everything');
      expect(tester.widget<TextButton>(reset).onPressed, isNull);

      await tester.tap(find.text('Off').at(0));
      await tester.pump();
      expect(tester.widget<TextButton>(reset).onPressed, isNotNull);

      await tester.tap(reset);
      await tester.pump();
      expect([for (var row = 0; row < 3; row++) _choiceOf(tester, row)], ['useGlobal', 'useGlobal', 'useGlobal']);
      expect(tester.widget<TextButton>(reset).onPressed, isNull);
      expect(harness.requests.saves.last.settings, RequestSettings.none);
    });

    _tabTest('a save that fails says so', (tester, harness) async {
      harness.requests.saveFailure = StateError('disk full');

      await tester.tap(find.text('Off').at(1));
      await tester.pump();
      await tester.pump();

      expect(find.text("Couldn't save this request's settings"), findsOneWidget);
    });
  });

  group('on a phone', () {
    testWidgets('the tab fits a narrow screen without overflowing', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final requests = FakeRequestSettingsRepository();
      final global = FakeSettingsRepository();
      locator.registerFactory<RequestSettingsViewModel>(() => RequestSettingsViewModel(requests, global));
      addTearDown(locator.reset);

      await tester.pumpWidget(_tree(7));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Off'), findsNWidgets(3));

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('in the browser', () {
    _tabTest('redirect and certificate overrides are disabled and say so', (tester, harness) async {
      expect(find.text(_note), findsNWidgets(2));
      expect(_isEnabled(tester, 0), isFalse);
      expect(_isEnabled(tester, 1), isFalse);
    }, isWeb: true);

    _tabTest('the timeout can still be overridden, and says the browser only approximates it', (tester, harness) async {
      expect(find.text('Approximate in the browser version'), findsOneWidget);
    }, isWeb: true);

    _tabTest('the no-cache header and the timeout can still be overridden', (tester, harness) async {
      expect(_isEnabled(tester, 2), isTrue);
      expect(tester.widget<TextField>(_timeoutField()).enabled, isTrue);
    }, isWeb: true);

    _tabTest('outside the browser nothing is disabled', (tester, harness) async {
      expect(find.text(_note), findsNothing);
      expect([for (var row = 0; row < 3; row++) _isEnabled(tester, row)], [true, true, true]);
    });
  });

  group('lifecycle', () {
    testWidgets("showing another request loads its overrides, and the first one's edit stays with the first", (tester) async {
      final requests = FakeRequestSettingsRepository()..stored[8] = const RequestSettings(sendNoCacheHeader: false);
      final global = FakeSettingsRepository();
      locator.registerFactory<RequestSettingsViewModel>(() => RequestSettingsViewModel(requests, global));
      addTearDown(locator.reset);
      tester.view.physicalSize = const Size(900, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_tree(7));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off').at(0));
      await tester.pump();

      await tester.pumpWidget(_tree(8));
      await tester.pumpAndSettle();

      expect(requests.saves.single.requestId, 7);
      expect(requests.saves.single.settings, const RequestSettings(followRedirects: false));
      expect(_choiceOf(tester, 0), 'useGlobal', reason: 'request 7\'s edit must not show on request 8');
      expect(_choiceOf(tester, 2), 'off');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an edit is already stored when the tab is taken down, so nothing is lost', (tester) async {
      final requests = FakeRequestSettingsRepository();
      final global = FakeSettingsRepository();
      locator.registerFactory<RequestSettingsViewModel>(() => RequestSettingsViewModel(requests, global));
      addTearDown(locator.reset);
      tester.view.physicalSize = const Size(900, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_tree(7));
      await tester.pumpAndSettle();
      await tester.tap(find.text('On').at(1));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(requests.saves.single.requestId, 7);
      expect(requests.saves.single.settings, const RequestSettings(verifySsl: true));
    });
  });
}
