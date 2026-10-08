import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/tool_dialog.dart';
import 'cors_proxy_server_view_model.dart';

/// Starts the CORS proxy of the web version from the desktop app, without a terminal: the web app's Settings > CORS proxy
/// takes the URL and the token shown here. Keeps running after the dialog is closed.
class CorsProxyDialog extends StatefulWidget {
  /// Replaces the one from the service locator, for a test.
  @visibleForTesting
  final CorsProxyServerViewModel? viewModel;

  const CorsProxyDialog({super.key, this.viewModel});

  static Future<void> show(BuildContext context) => ToolDialog.show(context, (_) => const CorsProxyDialog());

  @override
  State<CorsProxyDialog> createState() => _CorsProxyDialogState();
}

class _CorsProxyDialogState extends State<CorsProxyDialog> {
  late final CorsProxyServerViewModel _vm = widget.viewModel ?? locator<CorsProxyServerViewModel>();
  late final _port = TextEditingController(text: _vm.portText);
  late final _origins = TextEditingController(text: _vm.originsText);
  bool _tokenVisible = false;

  @override
  void dispose() {
    _port.dispose();
    _origins.dispose();
    super.dispose();
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $what')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final running = _vm.isRunning;
        return ToolDialog(
          icon: Icons.swap_horiz,
          title: 'CORS proxy',
          subtitle: 'Lets the web version of PostPilot call APIs that send no CORS headers',
          width: 720,
          height: 640,
          headerActions: [
            if (running)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: colors.statusSuccess.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 8, color: colors.statusSuccess),
                  const SizedBox(width: 6),
                  Text('Running on :${_vm.port}', style: TextStyle(color: colors.statusSuccess, fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
              ),
          ],
          child: !_vm.isSupported
              ? const EmptyHint(
                  icon: Icons.web_asset_off,
                  title: 'Not available in the browser',
                  message: 'A browser cannot listen on a port. Use the desktop app, or run "dart run bin/postpilot.dart proxy" in a terminal.',
                )
              // One scroll view that builds everything (a ListView builds only what is near the screen), the address and the
              // token first while it runs: that is what the person came for.
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const InfoBanner(
                        message: 'A browser only lets a web page call servers that allow it (CORS). This proxy forwards the web '
                            'version\'s calls from this computer and adds the missing headers. Only pages on this computer can use it, '
                            'and only with the token below.',
                      ),
                      const SizedBox(height: 16),
                      if (running) ..._connection(context),
                      ..._controls(context, running),
                      if (_vm.error != null) ...[
                        const SizedBox(height: 12),
                        InfoBanner(kind: BannerKind.error, message: _vm.error!),
                      ],
                      if (running) ...[
                        const SizedBox(height: 16),
                        _log(context),
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }

  List<Widget> _controls(BuildContext context, bool running) {
    final styles = context.textStyles;
    final colors = context.colors;
    return [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: TextField(
              controller: _port,
              enabled: !running,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'),
              onChanged: (v) => _vm.update(port: v),
            ),
          ),
          SizedBox(
            width: 360,
            child: TextField(
              controller: _origins,
              enabled: !running,
              decoration: const InputDecoration(
                labelText: 'Other pages allowed',
                hintText: 'https://app.example.com (optional)',
                helperText: 'Pages on this computer are always allowed',
              ),
              onChanged: (v) => _vm.update(origins: v),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Allow other devices on my network'),
        subtitle: Text(
          'Listens on every network interface. Anyone with the token could then send requests from this computer.',
          style: styles.caption.copyWith(color: _vm.allowLan ? colors.statusWarning : colors.secondaryText),
        ),
        value: _vm.allowLan,
        onChanged: running ? null : (v) => _vm.update(allowLan: v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Accept self-signed certificates'),
        subtitle: Text('For test servers whose certificate is not trusted.', style: styles.caption.copyWith(color: colors.secondaryText)),
        value: _vm.insecure,
        onChanged: running ? null : (v) => _vm.update(insecure: v),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (!running)
            GradientButton(label: 'Start', icon: Icons.play_arrow, loading: _vm.isBusy, onPressed: _vm.start)
          else
            OutlinedButton(
              onPressed: _vm.isBusy ? null : _vm.stop,
              child: BusyLabel(busy: _vm.isBusy, label: 'Stop', busyLabel: 'Stopping…', icon: Icons.stop),
            ),
          if (!running)
            TextButton.icon(
              onPressed: _vm.newToken,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('New token'),
            ),
        ],
      ),
    ];
  }

  List<Widget> _connection(BuildContext context) {
    final styles = context.textStyles;
    final colors = context.colors;
    final config = _vm.runningConfig!;
    Widget row(String label, Widget value, String copyText, String what) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label, style: styles.caption.copyWith(color: colors.secondaryText))),
          Expanded(child: value),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: 'Copy $what',
            onPressed: () => _copy(copyText, what),
          ),
        ],
      ),
    );
    return [
      ToolSection(
        title: 'Paste into the web app',
        hint: 'Settings > CORS proxy: the URL and the token, then switch it on and press Test connection.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('URL', SelectableText(_vm.url, style: styles.mono), _vm.url, 'the URL'),
            row(
              'Token',
              _tokenVisible ? SelectableText(config.token, style: styles.mono) : Text('•' * 24, style: styles.mono),
              config.token,
              'the token',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _tokenVisible = !_tokenVisible),
                icon: Icon(_tokenVisible ? Icons.visibility_off : Icons.visibility, size: 16),
                label: Text(_tokenVisible ? 'Hide token' : 'Show token'),
              ),
            ),
            Text(
              'Pages allowed: ${config.origins.describe()}',
              style: styles.caption.copyWith(color: colors.secondaryText),
            ),
            if (config.listensOnAllInterfaces)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: InfoBanner(
                  kind: BannerKind.warning,
                  title: 'Open to your network',
                  message: 'Every device on this network can reach the proxy. Anyone who learns the token can send requests from this computer to any address it can reach.',
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _log(BuildContext context) {
    final styles = context.textStyles;
    final colors = context.colors;
    return ToolSection(
      title: 'Calls',
      hint: 'Method, host and path (secrets in the query masked), status and time. Headers and bodies are never kept.',
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: colors.appBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: _vm.events.isEmpty
            ? Center(child: Text('No call yet', style: styles.caption.copyWith(color: colors.secondaryText)))
            : ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: _vm.events.length,
                itemBuilder: (context, i) {
                  final e = _vm.events[i];
                  final failed = e.error != null || e.status >= 400;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      e.line,
                      style: styles.mono.copyWith(fontSize: 12, color: failed ? colors.statusError : null),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
