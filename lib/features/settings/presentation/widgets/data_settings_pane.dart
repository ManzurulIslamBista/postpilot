import 'package:flutter/material.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/settings_view_model.dart';
import 'setting_row.dart';

class DataSettingsPane extends StatelessWidget {
  final SettingsViewModel viewModel;
  final VoidCallback? onOpenBackup;
  final VoidCallback? onOpenShortcuts;

  const DataSettingsPane({super.key, required this.viewModel, this.onOpenBackup, this.onOpenShortcuts});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Data', style: context.textStyles.heading),
        if (onOpenBackup != null)
          SettingRow(
            title: 'Backup and restore',
            description: 'Export your workspace to a file, or restore one.',
            control: OutlinedButton(
              onPressed: () => _closeThen(context, onOpenBackup!),
              child: const Text('Backup & restore…'),
            ),
          ),
        if (onOpenShortcuts != null)
          SettingRow(
            title: 'Keyboard shortcuts',
            description: 'See every shortcut the app understands.',
            control: OutlinedButton(
              onPressed: () => _closeThen(context, onOpenShortcuts!),
              child: const Text('Keyboard shortcuts'),
            ),
          ),
        SettingRow(
          title: 'Reset all settings',
          description: 'Put every setting back to its default. Requests, collections and environments stay as they are.',
          control: OutlinedButton(
            onPressed: () => _confirmReset(context),
            child: Text('Reset all settings', style: TextStyle(color: context.colors.statusError)),
          ),
        ),
      ],
    );
  }

  /// The follow-up opens its own dialog, so this one closes first instead of
  /// stacking under it.
  void _closeThen(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset all settings',
      message: 'Every setting goes back to its default. Your requests, collections and environments are not affected.',
      confirmLabel: 'Reset',
    );
    if (confirmed) await viewModel.reset();
  }
}
