import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:postpilot/core/network/api_http_response.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/settings/domain/entities/app_settings.dart';
import 'package:postpilot/features/settings/domain/entities/proxy_settings.dart';
import 'package:postpilot/features/settings/presentation/view_models/settings_view_model.dart';
import 'package:postpilot/features/settings/presentation/widgets/settings_dialog.dart';
import 'fakes/fake_settings_repositories.dart';

const _note = 'Not available in the browser version';

final class _Harness {
  final FakeSettingsRepository repository;
  final SettingsViewModel viewModel;
  _Harness(this.repository, this.viewModel);
}

/// Opens the dialog from a button, the way the app does. [isWeb] goes through
/// a direct showDialog, since the static `show` reads the platform itself.
Future<_Harness> _open(
  WidgetTester tester, {
  AppSettings initial = const AppSettings(),
  bool? isWeb,
  VoidCallback? onOpenBackup,
  VoidCallback? onOpenShortcuts,
  Size surface = const Size(1000, 900),
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repository = FakeSettingsRepository(initial);
  final viewModel = SettingsViewModel(repository);
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsViewModel>.value(
      value: viewModel,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => isWeb == null
                  ? SettingsDialog.show(context, onOpenBackup: onOpenBackup, onOpenShortcuts: onOpenShortcuts)
                  : showDialog<void>(
                      context: context,
                      builder: (_) => SettingsDialog(isWeb: isWeb, onOpenBackup: onOpenBackup, onOpenShortcuts: onOpenShortcuts),
                    ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return _Harness(repository, viewModel);
}

/// Runs a widget test, then closes the dialog and disposes the view model so
/// no save timer is pending when the body ends.
void _dialogTest(
  String name,
  Future<void> Function(WidgetTester tester, _Harness harness) body, {
  AppSettings initial = const AppSettings(),
  bool? isWeb,
  VoidCallback? onOpenBackup,
  VoidCallback? onOpenShortcuts,
  Size surface = const Size(1000, 900),
}) {
  testWidgets(name, (tester) async {
    final harness = await _open(
      tester,
      initial: initial,
      isWeb: isWeb,
      onOpenBackup: onOpenBackup,
      onOpenShortcuts: onOpenShortcuts,
      surface: surface,
    );
    try {
      await body(tester, harness);
    } finally {
      harness.viewModel.dispose();
    }
  });
}

Future<void> _goTo(WidgetTester tester, String section) async {
  await tester.ensureVisible(find.text(section));
  await tester.tap(find.text(section));
  await tester.pumpAndSettle();
}

/// Taps a control that may sit below the fold of the scrolling pane.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

String _text(WidgetTester tester, Finder field) => tester.widget<TextField>(field).controller!.text;

Finder _field(int index) => find.byType(TextField).at(index);

bool _switchValue(WidgetTester tester, int index) => tester.widget<Switch>(find.byType(Switch).at(index)).value;

void main() {
  setUp(_calls.clear);

  group('layout', () {
    _dialogTest('lists the five sections and opens on General with the defaults', (tester, harness) async {
      for (final section in ['General', 'Appearance', 'Proxy', 'Safety', 'Data']) {
        expect(find.text(section), findsWidgets, reason: section);
      }
      expect(find.text('Request timeout'), findsOneWidget);
      expect(find.text('Max response size'), findsOneWidget);
      expect(_text(tester, _field(0)), '30');
      expect(_text(tester, _field(1)), '50');
      expect(_text(tester, _field(2)), '10');
      expect([for (var i = 0; i < 4; i++) _switchValue(tester, i)], [true, true, false, false]);
    });

    _dialogTest('shows each section\'s own settings when picked', (tester, harness) async {
      await _goTo(tester, 'Appearance');
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Request timeout'), findsNothing);

      await _goTo(tester, 'Proxy');
      expect(find.text('Route requests through'), findsOneWidget);

      await _goTo(tester, 'Data');
      expect(find.text('Reset all settings'), findsWidgets);

      await _goTo(tester, 'General');
      expect(find.text('Request timeout'), findsOneWidget);
    });

    _dialogTest('a narrow screen swaps the section list for chips, and they still navigate', (tester, harness) async {
      expect(find.byType(ChoiceChip), findsNWidgets(5));
      expect(find.byType(ListTile), findsNothing);

      await _tap(tester, find.widgetWithText(ChoiceChip, 'Proxy'));
      await tester.pumpAndSettle();

      expect(find.text('Route requests through'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, surface: const Size(420, 800));

    _dialogTest('every section fits a phone-width screen without overflowing', (tester, harness) async {
      for (final section in ['Appearance', 'Safety', 'Data', 'General']) {
        await _tap(tester, find.widgetWithText(ChoiceChip, section));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: section);
      }

      await _tap(tester, find.widgetWithText(ChoiceChip, 'Proxy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'a custom proxy');
      expect(find.text('Host'), findsOneWidget);
    }, surface: const Size(360, 700));

    _dialogTest('a wide screen keeps the section list beside the settings', (tester, harness) async {
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(5));
    });

    _dialogTest('the close button closes it', (tester, harness) async {
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsDialog), findsNothing);
    });
  });

  group('on a desktop platform', () {
    testWidgets('its two scrolling areas do not fight over one scroll controller', (tester) async {
      // Only desktop (and so web) adds scrollbars, which is what shares the route's controller.
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final harness = await _open(tester);
        expect(find.byType(Scrollbar), findsWidgets, reason: 'the platform adds scrollbars, so this test exercises them');
        for (final section in ['Appearance', 'Proxy', 'Data', 'General']) {
          await _goTo(tester, section);
        }
        await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -300));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        harness.viewModel.dispose();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('general', () {
    _dialogTest('a switch changes its setting', (tester, harness) async {
      await _tap(tester, find.byType(Switch).at(2));
      await tester.pump();

      expect(harness.viewModel.settings.sendNoCacheHeader, isTrue);
      expect(_switchValue(tester, 2), isTrue);
    });

    _dialogTest('turning off follow redirects also disables the redirect limit', (tester, harness) async {
      expect(tester.widget<TextField>(_field(2)).enabled, isTrue);

      await tester.tap(find.byType(Switch).at(0));
      await tester.pump();

      expect(harness.viewModel.settings.followRedirects, isFalse);
      expect(tester.widget<TextField>(_field(2)).enabled, isFalse);
    });

    _dialogTest('typing a number applies it at once and saves it after the delay', (tester, harness) async {
      await tester.enterText(_field(0), '45');
      await tester.pump();

      expect(harness.viewModel.settings.requestTimeoutSeconds, 45);
      expect(harness.repository.saved, isEmpty);

      await tester.pump(const Duration(milliseconds: 400));
      expect(harness.repository.saved.single.requestTimeoutSeconds, 45);
    });

    _dialogTest('0 is a valid timeout and means no timeout', (tester, harness) async {
      await tester.enterText(_field(0), '0');
      await tester.pump();

      expect(harness.viewModel.settings.requestTimeoutSeconds, 0);
    });

    _dialogTest('only digits can be typed into a number field', (tester, harness) async {
      await tester.enterText(_field(0), '1a2-3');
      await tester.pump();

      expect(_text(tester, _field(0)), '123');
      expect(harness.viewModel.settings.requestTimeoutSeconds, 123);
    });

    _dialogTest('clearing a number field changes nothing, and the stored value returns when the field is left', (tester, harness) async {
      await tester.enterText(_field(0), '');
      await tester.pump();

      expect(harness.viewModel.settings.requestTimeoutSeconds, 30);
      expect(_text(tester, _field(0)), '');

      await tester.tap(_field(1));
      await tester.pump();

      expect(_text(tester, _field(0)), '30');
    });

    _dialogTest('a number beyond its range is capped, and the field shows the cap once it is left', (tester, harness) async {
      await tester.enterText(_field(2), '9999999');
      await tester.pump();

      expect(harness.viewModel.settings.maxRedirects, AppSettings.maxRedirectsLimit);

      await tester.tap(_field(0));
      await tester.pump();

      expect(_text(tester, _field(2)), '${AppSettings.maxRedirectsLimit}');
    });

    _dialogTest('a save that fails says so', (tester, harness) async {
      harness.repository.failWith = StateError('disk full');

      await _tap(tester, find.byType(Switch).at(3));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('Couldn\'t save your settings'), findsOneWidget);
    });

    _dialogTest('closing right after an edit saves it without waiting out the delay', (tester, harness) async {
      await tester.enterText(_field(0), '7');
      await tester.pump();
      expect(harness.repository.saved, isEmpty);

      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(SettingsDialog), findsNothing);
      expect(harness.repository.saved.single.requestTimeoutSeconds, 7);
    });
  });

  group('appearance', () {
    _dialogTest('picking a theme changes the theme mode the app follows', (tester, harness) async {
      await _goTo(tester, 'Appearance');

      await tester.tap(find.text('Dark'));
      await tester.pump();
      expect(harness.viewModel.settings.themeMode, AppThemeMode.dark);
      expect(harness.viewModel.themeMode, ThemeMode.dark);

      await tester.tap(find.text('Light'));
      await tester.pump();
      expect(harness.viewModel.themeMode, ThemeMode.light);

      await tester.tap(find.text('System'));
      await tester.pump();
      expect(harness.viewModel.themeMode, ThemeMode.system);
    });

    _dialogTest('shows the theme that is set', (tester, harness) async {
      await _goTo(tester, 'Appearance');

      final button = tester.widget<SegmentedButton<AppThemeMode>>(find.byType(SegmentedButton<AppThemeMode>));
      expect(button.selected, {AppThemeMode.dark});
    }, initial: const AppSettings(themeMode: AppThemeMode.dark));
  });

  group('proxy', () {
    _dialogTest('the system proxy needs no fields, and says where it comes from', (tester, harness) async {
      await _goTo(tester, 'Proxy');

      expect(find.textContaining('HTTP_PROXY'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    _dialogTest('no proxy shows nothing more', (tester, harness) async {
      await _goTo(tester, 'Proxy');

      await tester.tap(find.text('No proxy'));
      await tester.pump();

      expect(harness.viewModel.settings.proxy.mode, ProxyMode.none);
      expect(find.textContaining('HTTP_PROXY'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    _dialogTest('a custom proxy shows its fields and saves what is typed', (tester, harness) async {
      await _goTo(tester, 'Proxy');
      await tester.tap(find.text('Custom'));
      await tester.pump();

      expect(harness.viewModel.settings.proxy.mode, ProxyMode.custom);
      for (final label in ['Host', 'Port', 'Username', 'Password', 'Bypass proxy for']) {
        expect(find.widgetWithText(TextField, label), findsOneWidget, reason: label);
      }
      expect(find.textContaining('Until then requests go direct'), findsOneWidget);
      expect(_text(tester, find.widgetWithText(TextField, 'Port')), '8080');

      await tester.enterText(find.widgetWithText(TextField, 'Host'), 'proxy.local');
      await tester.enterText(find.widgetWithText(TextField, 'Port'), '3128');
      await tester.enterText(find.widgetWithText(TextField, 'Username'), 'ann');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'secret');
      await tester.enterText(find.widgetWithText(TextField, 'Bypass proxy for'), 'localhost');
      await tester.pump(const Duration(milliseconds: 400));

      final proxy = harness.repository.saved.last.proxy;
      expect((proxy.mode, proxy.host, proxy.port, proxy.username, proxy.password, proxy.bypass),
          (ProxyMode.custom, 'proxy.local', 3128, 'ann', 'secret', 'localhost'));
      expect(find.textContaining('Until then requests go direct'), findsNothing);
    });

    _dialogTest('the password is hidden until asked for', (tester, harness) async {
      await _goTo(tester, 'Proxy');
      final password = find.widgetWithText(TextField, 'Password');

      expect(tester.widget<TextField>(password).obscureText, isTrue);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(tester.widget<TextField>(password).obscureText, isFalse);

      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(tester.widget<TextField>(password).obscureText, isTrue);
    }, initial: const AppSettings(proxy: ProxySettings(mode: ProxyMode.custom, password: 'secret')));

    _dialogTest('a saved proxy is shown filled in', (tester, harness) async {
      await _goTo(tester, 'Proxy');

      expect(_text(tester, find.widgetWithText(TextField, 'Host')), 'proxy.local');
      expect(_text(tester, find.widgetWithText(TextField, 'Port')), '3128');
      expect(_text(tester, find.widgetWithText(TextField, 'Username')), 'ann');
      expect(find.textContaining('Until then requests go direct'), findsNothing);
    }, initial: const AppSettings(proxy: ProxySettings(mode: ProxyMode.custom, host: 'proxy.local', port: 3128, username: 'ann')));
  });

  group('data', () {
    _dialogTest('without callbacks only the reset button is offered', (tester, harness) async {
      await _goTo(tester, 'Data');

      expect(find.text('Backup & restore…'), findsNothing);
      expect(find.text('Keyboard shortcuts'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Reset all settings'), findsOneWidget);
    });

    _dialogTest('with callbacks both buttons appear and each closes the dialog, then runs its callback', (tester, harness) async {
      await _goTo(tester, 'Data');
      expect(find.widgetWithText(OutlinedButton, 'Keyboard shortcuts'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Backup & restore…'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsDialog), findsNothing);
      expect(_calls, ['backup']);
    }, onOpenBackup: () => _calls.add('backup'), onOpenShortcuts: () => _calls.add('shortcuts'));

    _dialogTest('the shortcuts button runs its callback, and is alone when there is no backup callback', (tester, harness) async {
      await _goTo(tester, 'Data');

      expect(find.text('Backup & restore…'), findsNothing);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Keyboard shortcuts'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsDialog), findsNothing);
      expect(_calls, ['shortcuts']);
    }, onOpenShortcuts: () => _calls.add('shortcuts'));

    _dialogTest('reset asks first, and cancelling changes nothing', (tester, harness) async {
      await _goTo(tester, 'Data');

      await tester.tap(find.widgetWithText(OutlinedButton, 'Reset all settings'));
      await tester.pumpAndSettle();
      expect(find.text('Every setting goes back to its default. Your requests, collections and environments are not affected.'),
          findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(harness.viewModel.settings.verifySsl, isFalse);
      expect(harness.repository.resets, 0);
    }, initial: const AppSettings(verifySsl: false));

    _dialogTest('confirming reset puts every setting, and every field, back to its default', (tester, harness) async {
      await _goTo(tester, 'Data');

      await tester.tap(find.widgetWithText(OutlinedButton, 'Reset all settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
      await tester.pumpAndSettle();

      expect(harness.viewModel.settings, const AppSettings());
      expect(harness.repository.resets, 1);

      await _goTo(tester, 'General');
      expect(_text(tester, _field(0)), '30');
      expect(_text(tester, _field(1)), '50');
      expect([for (var i = 0; i < 4; i++) _switchValue(tester, i)], [true, true, false, false]);
    }, initial: const AppSettings(requestTimeoutSeconds: 5, maxResponseSizeMb: 0, followRedirects: false, sendNoCacheHeader: true));
  });

  group('in the browser', () {
    _dialogTest('the options a browser cannot honour are disabled and say so', (tester, harness) async {
      expect(find.text(_note), findsNWidgets(3), reason: 'follow redirects, maximum redirects, verify SSL');
      expect(tester.widget<Switch>(find.byType(Switch).at(0)).onChanged, isNull);
      expect(tester.widget<Switch>(find.byType(Switch).at(1)).onChanged, isNull);
      expect(tester.widget<TextField>(_field(2)).enabled, isFalse);
    }, isWeb: true);

    _dialogTest('the options a browser can honour stay usable', (tester, harness) async {
      expect(tester.widget<TextField>(_field(0)).enabled, isTrue);
      expect(tester.widget<TextField>(_field(1)).enabled, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch).at(2)).onChanged, isNotNull);
      expect(tester.widget<Switch>(find.byType(Switch).at(3)).onChanged, isNotNull);
    }, isWeb: true);

    _dialogTest('the proxy section says it is not available and its controls are disabled', (tester, harness) async {
      await _goTo(tester, 'Proxy');

      expect(find.textContaining(_note), findsOneWidget);
      expect(tester.widget<SegmentedButton<ProxyMode>>(find.byType(SegmentedButton<ProxyMode>)).onSelectionChanged, isNull);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Host')).enabled, isFalse);
    }, isWeb: true, initial: const AppSettings(proxy: ProxySettings(mode: ProxyMode.custom)));

    _dialogTest('the timeout and the size limit stay usable but say how the browser bends them', (tester, harness) async {
      expect(find.text('Approximate in the browser version'), findsOneWidget);
      expect(find.text('The browser still downloads the whole response first'), findsOneWidget);
    }, isWeb: true);

    _dialogTest('outside the browser nothing is disabled', (tester, harness) async {
      expect(find.text('Approximate in the browser version'), findsNothing);
      expect(find.text('The browser still downloads the whole response first'), findsNothing);
      expect(find.text(_note), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch).at(0)).onChanged, isNotNull);
      expect(tester.widget<TextField>(_field(2)).enabled, isTrue);

      await _goTo(tester, 'Proxy');
      expect(find.textContaining(_note), findsNothing);
      expect(tester.widget<SegmentedButton<ProxyMode>>(find.byType(SegmentedButton<ProxyMode>)).onSelectionChanged, isNotNull);
    }, isWeb: false);
  });
}

/// What the Data buttons' callbacks were called with, across one test.
final List<String> _calls = [];
