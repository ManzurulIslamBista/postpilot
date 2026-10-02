import 'package:flutter/material.dart';
import 'app.dart';
import 'core/di/injector.dart';
import 'core/layout/layout_prefs.dart';
import 'features/settings/domain/repositories/settings_repository.dart';
import 'features/workplace/presentation/view_models/workplace_view_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupDependencies();
  // Before the first frame: until the stored settings are loaded the app would
  // run on defaults, and the first change would save those over the stored ones.
  await locator<SettingsRepository>().load();
  await locator<WorkplaceViewModel>().init();
  await locator<LayoutPrefs>().load();
  runApp(const PostPilotApp());
}
