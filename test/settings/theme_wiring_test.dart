// The app.dart wiring the settings feature asks for: the view model provided
// above MaterialApp, whose theme mode follows the picked theme.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/settings/presentation/view_models/settings_view_model.dart';
import 'package:postpilot/features/settings/presentation/widgets/settings_dialog.dart';
import 'fakes/fake_settings_repositories.dart';

void main() {
  testWidgets('the theme picked in the dialog re-themes the whole app, and other settings leave the app alone', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;

    final viewModel = SettingsViewModel(FakeSettingsRepository());
    var appBuilds = 0;
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider<SettingsViewModel>.value(value: viewModel)],
        child: Selector<SettingsViewModel, ThemeMode>(
          selector: (_, settings) => settings.themeMode,
          builder: (context, themeMode, _) {
            appBuilds++;
            return MaterialApp(
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: themeMode,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(onPressed: () => SettingsDialog.show(context), child: const Text('open')),
                ),
              ),
            );
          },
        ),
      ),
    );
    Brightness brightness() => Theme.of(tester.element(find.text('open'))).brightness;
    expect(brightness(), Brightness.light);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final buildsBefore = appBuilds;
    await tester.enterText(find.byType(TextField).first, '12');
    await tester.pump();
    expect(appBuilds, buildsBefore, reason: 'typing a timeout must not rebuild the whole app');

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark, reason: 'System follows the device');

    viewModel.dispose();
  });
}
