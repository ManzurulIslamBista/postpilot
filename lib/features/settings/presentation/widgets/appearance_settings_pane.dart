import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/app_settings.dart';
import '../view_models/settings_view_model.dart';
import 'setting_row.dart';

class AppearanceSettingsPane extends StatelessWidget {
  final SettingsViewModel viewModel;

  const AppearanceSettingsPane({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Appearance', style: context.textStyles.heading),
        SettingRow(
          title: 'Theme',
          description: 'System follows the light or dark mode of your device.',
          stacked: true,
          control: SegmentedButton<AppThemeMode>(
            segments: const [
              ButtonSegment(value: AppThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto, size: 16)),
              ButtonSegment(value: AppThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined, size: 16)),
              ButtonSegment(value: AppThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined, size: 16)),
            ],
            selected: {viewModel.settings.themeMode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => viewModel.setThemeMode(selection.first),
          ),
        ),
      ],
    );
  }
}
