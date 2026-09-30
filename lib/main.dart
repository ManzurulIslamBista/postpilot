import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/di/injector.dart';
import 'features/settings/domain/repositories/settings_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.publishableKey);
  setupDependencies();
  // Before the first frame: until the stored settings are loaded the app would
  // run on defaults, and the first change would save those over the stored ones.
  await locator<SettingsRepository>().load();
  runApp(const PostPilotApp());
}
