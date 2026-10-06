import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/settings_view_model.dart';
import '../../../safety/presentation/safety_settings_pane.dart';
import 'appearance_settings_pane.dart';
import 'data_settings_pane.dart';
import 'general_settings_pane.dart';
import 'history_settings_pane.dart';
import 'proxy_settings_pane.dart';

enum _Section {
  general('General', Icons.tune),
  appearance('Appearance', Icons.palette_outlined),
  proxy('Proxy', Icons.lan_outlined),
  safety('Safety', Icons.shield_outlined),
  history('History', Icons.history),
  data('Data', Icons.storage_outlined);

  const _Section(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Below this width the section list no longer fits beside the settings
/// without squeezing them, so it becomes a row of chips above them.
const _narrowWidth = 560.0;

class SettingsDialog extends StatefulWidget {
  /// Each is shown as a button in the Data section only when given, and the
  /// dialog closes before it is called.
  final VoidCallback? onOpenBackup;
  final VoidCallback? onOpenShortcuts;

  /// Whether the app runs in a browser, which cannot honour TLS, proxy or
  /// redirect settings.
  final bool isWeb;

  const SettingsDialog({super.key, this.onOpenBackup, this.onOpenShortcuts, this.isWeb = kIsWeb});

  static Future<void> show(BuildContext context, {VoidCallback? onOpenBackup, VoidCallback? onOpenShortcuts}) =>
      showDialog(
        context: context,
        builder: (_) => SettingsDialog(onOpenBackup: onOpenBackup, onOpenShortcuts: onOpenShortcuts),
      );

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late SettingsViewModel _viewModel;
  _Section _section = _Section.general;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewModel = context.read<SettingsViewModel>();
  }

  @override
  void dispose() {
    // Closing right after an edit must not wait out the save delay.
    _viewModel.flush();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<SettingsViewModel>();
    return Dialog(
      // Larger than a small screen allows: the dialog's own insets cap it.
      child: SizedBox(
        width: 780,
        height: 560,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Text('Settings', style: context.textStyles.heading),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth < _narrowWidth
                    ? Column(
                        children: [
                          _SectionChips(selected: _section, onSelect: _select),
                          const Divider(),
                          Expanded(child: _content(viewModel)),
                        ],
                      )
                    : Row(
                        children: [
                          SizedBox(width: 180, child: _SectionList(selected: _section, onSelect: _select)),
                          const VerticalDivider(),
                          Expanded(child: _content(viewModel)),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _select(_Section section) => setState(() => _section = section);

  Widget _content(SettingsViewModel viewModel) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: switch (_section) {
              _Section.general => GeneralSettingsPane(viewModel: viewModel, isWeb: widget.isWeb),
              _Section.appearance => AppearanceSettingsPane(viewModel: viewModel),
              _Section.proxy => ProxySettingsPane(viewModel: viewModel, isWeb: widget.isWeb),
              _Section.safety => const SafetySettingsPane(),
              _Section.history => const HistorySettingsPane(),
              _Section.data => DataSettingsPane(
                  viewModel: viewModel,
                  onOpenBackup: widget.onOpenBackup,
                  onOpenShortcuts: widget.onOpenShortcuts,
                ),
            },
          ),
        ),
        if (viewModel.saveError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                viewModel.saveError!,
                style: context.textStyles.caption.copyWith(color: context.colors.statusError),
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionList extends StatelessWidget {
  final _Section selected;
  final ValueChanged<_Section> onSelect;
  const _SectionList({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final section in _Section.values)
          ListTile(
            dense: true,
            selected: section == selected,
            leading: Icon(section.icon, size: 18),
            title: Text(section.label),
            onTap: () => onSelect(section),
          ),
      ],
    );
  }
}

class _SectionChips extends StatelessWidget {
  final _Section selected;
  final ValueChanged<_Section> onSelect;
  const _SectionChips({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final section in _Section.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(section.icon, size: 16),
                label: Text(section.label),
                selected: section == selected,
                onSelected: (_) => onSelect(section),
              ),
            ),
        ],
      ),
    );
  }
}
