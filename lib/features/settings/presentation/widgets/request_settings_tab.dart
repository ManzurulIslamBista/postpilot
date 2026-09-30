import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/request_settings_view_model.dart';
import 'setting_row.dart';
import 'synced_text_field.dart';

enum _Choice { useGlobal, on, off }

/// The "Settings" tab of the request builder: this request's overrides of the
/// global settings, auto-saved on every change. Each one says what "use
/// global" currently means. Designed to sit inside the page's scroll view, so
/// it lays out as a plain Column.
class RequestSettingsTab extends StatefulWidget {
  final int requestId;

  /// Whether the app runs in a browser, which cannot honour TLS or redirect
  /// settings.
  final bool isWeb;

  const RequestSettingsTab({super.key, required this.requestId, this.isWeb = kIsWeb});

  @override
  State<RequestSettingsTab> createState() => _RequestSettingsTabState();
}

class _RequestSettingsTabState extends State<RequestSettingsTab> {
  late final RequestSettingsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<RequestSettingsViewModel>();
    _viewModel.load(widget.requestId);
  }

  @override
  void didUpdateWidget(covariant RequestSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId) {
      _viewModel.load(widget.requestId);
    }
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RequestSettingsViewModel>.value(
      value: _viewModel,
      child: Consumer<RequestSettingsViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) return const Center(child: CircularProgressIndicator());
          final overrides = vm.overrides;
          final global = vm.global;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Request settings', style: context.textStyles.heading),
              Text(
                'Override the global Settings for this request only. "Use global" follows whatever Settings says.',
                style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
              ),
              SettingRow(
                title: 'Follow redirects',
                description: 'Follow 3xx responses automatically instead of showing them.',
                stacked: true,
                unavailable: widget.isWeb,
                control: _OverrideChoice(
                  value: overrides.followRedirects,
                  globalLabel: _onOff(global.followRedirects),
                  onChanged: widget.isWeb ? null : vm.setFollowRedirects,
                ),
              ),
              SettingRow(
                title: 'Verify SSL certificates',
                description: 'Turn off to accept a self-signed or expired certificate from this request\'s server.',
                stacked: true,
                unavailable: widget.isWeb,
                control: _OverrideChoice(
                  value: overrides.verifySsl,
                  globalLabel: _onOff(global.verifySsl),
                  onChanged: widget.isWeb ? null : vm.setVerifySsl,
                ),
              ),
              SettingRow(
                title: 'Send no-cache header',
                description: 'Add Cache-Control: no-cache to this request if it does not set it.',
                stacked: true,
                control: _OverrideChoice(
                  value: overrides.sendNoCacheHeader,
                  globalLabel: _onOff(global.sendNoCacheHeader),
                  onChanged: vm.setSendNoCacheHeader,
                ),
              ),
              SettingRow(
                title: 'Request timeout',
                description: 'Leave empty to use the global timeout. 0 waits forever.',
                note: widget.isWeb ? 'Approximate in the browser version' : null,
                control: SizedBox(
                  width: 160,
                  child: SyncedTextField(
                    value: overrides.timeoutSeconds?.toString() ?? '',
                    hintText: 'Global: ${_timeoutLabel(global.requestTimeoutSeconds)}',
                    suffixText: 's',
                    digitsOnly: true,
                    onChanged: (text) => vm.setTimeoutSeconds(int.tryParse(text)),
                  ),
                ),
              ),
              if (vm.saveError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    vm.saveError!,
                    style: context.textStyles.caption.copyWith(color: context.colors.statusError),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Use global settings for everything'),
                  onPressed: overrides.isEmpty ? null : vm.clear,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _onOff(bool value) => value ? 'On' : 'Off';

  String _timeoutLabel(int seconds) => seconds == 0 ? 'no timeout' : '$seconds s';
}

class _OverrideChoice extends StatelessWidget {
  final bool? value;
  final String globalLabel;
  final ValueChanged<bool?>? onChanged;

  const _OverrideChoice({required this.value, required this.globalLabel, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final choice = switch (value) {
      null => _Choice.useGlobal,
      true => _Choice.on,
      false => _Choice.off,
    };
    return SegmentedButton<_Choice>(
      segments: [
        ButtonSegment(value: _Choice.useGlobal, label: Text('Use global ($globalLabel)')),
        const ButtonSegment(value: _Choice.on, label: Text('On')),
        const ButtonSegment(value: _Choice.off, label: Text('Off')),
      ],
      selected: {choice},
      showSelectedIcon: false,
      onSelectionChanged: onChanged == null
          ? null
          : (selection) => onChanged!(switch (selection.first) {
                _Choice.useGlobal => null,
                _Choice.on => true,
                _Choice.off => false,
              }),
    );
  }
}
