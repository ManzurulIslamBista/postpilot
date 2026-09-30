import 'package:flutter/material.dart';
import '../../../../core/network/api_http_response.dart' show ProxyMode;
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/settings_view_model.dart';
import 'setting_row.dart';
import 'setting_number_field.dart';
import 'synced_text_field.dart';

class ProxySettingsPane extends StatefulWidget {
  final SettingsViewModel viewModel;
  final bool isWeb;

  const ProxySettingsPane({super.key, required this.viewModel, required this.isWeb});

  @override
  State<ProxySettingsPane> createState() => _ProxySettingsPaneState();
}

class _ProxySettingsPaneState extends State<ProxySettingsPane> {
  bool _passwordVisible = false;

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final proxy = vm.settings.proxy;
    final enabled = !widget.isWeb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Proxy', style: context.textStyles.heading),
        if (widget.isWeb)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '$browserUnavailableNote — the browser decides how requests reach the network.',
              style: context.textStyles.caption.copyWith(color: context.colors.mainAccent),
            ),
          ),
        SettingRow(
          title: 'Route requests through',
          stacked: true,
          control: SegmentedButton<ProxyMode>(
            segments: const [
              ButtonSegment(value: ProxyMode.none, label: Text('No proxy')),
              ButtonSegment(value: ProxyMode.system, label: Text('System')),
              ButtonSegment(value: ProxyMode.custom, label: Text('Custom')),
            ],
            selected: {proxy.mode},
            showSelectedIcon: false,
            onSelectionChanged: enabled ? (selection) => vm.setProxyMode(selection.first) : null,
          ),
        ),
        if (proxy.mode == ProxyMode.system)
          Text(
            'Uses the HTTP_PROXY, HTTPS_PROXY and NO_PROXY environment variables of this device.',
            style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
          ),
        if (proxy.mode == ProxyMode.custom) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SyncedTextField(
                  value: proxy.host,
                  labelText: 'Host',
                  hintText: 'proxy.example.com',
                  enabled: enabled,
                  onChanged: vm.setProxyHost,
                ),
              ),
              const SizedBox(width: 8),
              SettingNumberField(
                value: proxy.port,
                labelText: 'Port',
                width: 96,
                enabled: enabled,
                onChanged: vm.setProxyPort,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SyncedTextField(
                  value: proxy.username,
                  labelText: 'Username',
                  enabled: enabled,
                  onChanged: vm.setProxyUsername,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SyncedTextField(
                  value: proxy.password,
                  labelText: 'Password',
                  enabled: enabled,
                  obscureText: !_passwordVisible,
                  suffixIcon: IconButton(
                    icon: Icon(_passwordVisible ? Icons.visibility_off : Icons.visibility, size: 16),
                    tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                    onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                  ),
                  onChanged: vm.setProxyPassword,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SyncedTextField(
            value: proxy.bypass,
            labelText: 'Bypass proxy for',
            hintText: 'localhost, 127.0.0.1, *.internal.example.com',
            enabled: enabled,
            onChanged: vm.setProxyBypass,
          ),
          if (proxy.host.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Enter a host to start using this proxy. Until then requests go direct.',
                style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
              ),
            ),
        ],
      ],
    );
  }
}
