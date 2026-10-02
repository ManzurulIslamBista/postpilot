import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'core/database/app_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/di/injector.dart';
import 'features/settings/domain/repositories/settings_repository.dart';
import 'features/workplace/presentation/view_models/workplace_view_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.publishableKey);
  setupDependencies();
  try {
    final rows = await locator<AppDatabase>().customSelect('select sqlite_version() as v').get();
    debugPrint('DIAG db ok ${rows.first.data}');
  } catch (e, st) {
    debugPrint('DIAG db FAILED: ${e.runtimeType}: $e');
    debugPrint('DIAG stack: $st');
  }
  // Before the first frame: until the stored settings are loaded the app would
  // run on defaults, and the first change would save those over the stored ones.
  await locator<SettingsRepository>().load();
  await locator<WorkplaceViewModel>().init();
  runApp(const PostPilotApp());
}
