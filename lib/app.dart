import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/constants/app_constants.dart';
import 'core/di/injector.dart';
import 'core/layout/layout_prefs.dart';
import 'core/theme/app_theme.dart';
import 'features/collections/presentation/view_models/collections_view_model.dart';
import 'features/documentation/presentation/view_models/tag_filter_view_model.dart';
import 'features/environments/presentation/view_models/environments_view_model.dart';
import 'features/git_sync/presentation/view_models/linked_collections_view_model.dart';
import 'features/history/presentation/view_models/history_view_model.dart';
import 'features/settings/presentation/view_models/settings_view_model.dart';
import 'features/shell/presentation/shell_page.dart';
import 'features/shell/presentation/shell_view_model.dart';
import 'features/workplace/presentation/view_models/workplace_view_model.dart';

class PostPilotApp extends StatelessWidget {
  const PostPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // Providers live above MaterialApp (the Navigator's ancestor) so that
      // dialogs — pushed as sibling routes, not descendants of the page that
      // opened them — can still read this state. See injector.dart.
      providers: [
        ChangeNotifierProvider.value(value: locator<WorkplaceViewModel>()),
        ChangeNotifierProvider.value(value: locator<ShellViewModel>()),
        ChangeNotifierProvider.value(value: locator<CollectionsViewModel>()),
        ChangeNotifierProvider.value(value: locator<EnvironmentsViewModel>()),
        ChangeNotifierProvider.value(value: locator<HistoryViewModel>()),
        ChangeNotifierProvider.value(value: locator<LinkedCollectionsViewModel>()),
        ChangeNotifierProvider.value(value: locator<SettingsViewModel>()),
        ChangeNotifierProvider.value(value: locator<TagFilterViewModel>()),
        ChangeNotifierProvider.value(value: locator<LayoutPrefs>()),
      ],
      // A Selector so that typing in a settings field does not rebuild the app.
      child: Selector<SettingsViewModel, ThemeMode>(
        selector: (_, settings) => settings.themeMode,
        builder: (context, themeMode, _) => MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          home: const ShellPage(),
        ),
      ),
    );
  }
}
