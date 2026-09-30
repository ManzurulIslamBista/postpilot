import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/settings_view_model.dart';
import 'setting_number_field.dart';
import 'setting_row.dart';

class GeneralSettingsPane extends StatelessWidget {
  final SettingsViewModel viewModel;
  final bool isWeb;

  const GeneralSettingsPane({super.key, required this.viewModel, required this.isWeb});

  @override
  Widget build(BuildContext context) {
    final settings = viewModel.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('General', style: context.textStyles.heading),
        SettingRow(
          title: 'Request timeout',
          description: 'How long to wait for a response before giving up. 0 waits forever.',
          note: isWeb ? 'Approximate in the browser version' : null,
          control: SettingNumberField(
            value: settings.requestTimeoutSeconds,
            suffixText: 's',
            onChanged: viewModel.setRequestTimeoutSeconds,
          ),
        ),
        SettingRow(
          title: 'Max response size',
          description: 'A larger response is cut off at this size. 0 keeps everything.',
          note: isWeb ? 'The browser still downloads the whole response first' : null,
          control: SettingNumberField(
            value: settings.maxResponseSizeMb,
            suffixText: 'MB',
            onChanged: viewModel.setMaxResponseSizeMb,
          ),
        ),
        SettingRow(
          title: 'Follow redirects',
          description: 'Follow 3xx responses automatically instead of showing them.',
          unavailable: isWeb,
          control: Switch(
            value: settings.followRedirects,
            onChanged: isWeb ? null : viewModel.setFollowRedirects,
          ),
        ),
        SettingRow(
          title: 'Maximum redirects',
          description: 'A request that is redirected more often than this fails.',
          unavailable: isWeb,
          control: SettingNumberField(
            value: settings.maxRedirects,
            enabled: !isWeb && settings.followRedirects,
            onChanged: viewModel.setMaxRedirects,
          ),
        ),
        SettingRow(
          title: 'Verify SSL certificates',
          description: 'Turn off to accept self-signed or expired certificates, for a dev server.',
          unavailable: isWeb,
          control: Switch(
            value: settings.verifySsl,
            onChanged: isWeb ? null : viewModel.setVerifySsl,
          ),
        ),
        SettingRow(
          title: 'Send no-cache header',
          description: 'Add Cache-Control: no-cache to requests that do not set it.',
          control: Switch(value: settings.sendNoCacheHeader, onChanged: viewModel.setSendNoCacheHeader),
        ),
        SettingRow(
          title: 'Trim keys and values',
          description: 'Strip leading and trailing whitespace from header, query and form-field keys and values.',
          control: Switch(value: settings.trimKeysAndValues, onChanged: viewModel.setTrimKeysAndValues),
        ),
      ],
    );
  }
}
