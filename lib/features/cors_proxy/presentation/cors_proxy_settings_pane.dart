import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/di/injector.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/busy_label.dart';
import '../../../core/widgets/code_block.dart';
import '../../../core/widgets/info_banner.dart';
import '../../settings/presentation/widgets/setting_row.dart';
import '../../settings/presentation/widgets/synced_text_field.dart';
import '../domain/cors_proxy_protocol.dart';
import '../domain/cors_proxy_worker_guide.dart';
import 'cors_proxy_settings_view_model.dart';

/// Settings > CORS proxy (the web version only): switch the proxy on, say where it is and what its token is, test it, and see
/// the two ways to have one: a program on this computer, or a Worker of your own on Cloudflare.
class CorsProxySettingsPane extends StatefulWidget {
  /// Replaces the one from the service locator, for a test.
  final CorsProxySettingsViewModel? viewModel;

  const CorsProxySettingsPane({super.key, this.viewModel});

  @override
  State<CorsProxySettingsPane> createState() => _CorsProxySettingsPaneState();
}

class _CorsProxySettingsPaneState extends State<CorsProxySettingsPane> {
  late final CorsProxySettingsViewModel _vm = widget.viewModel ?? locator<CorsProxySettingsViewModel>();
  bool _tokenVisible = false;

  @override
  void initState() {
    super.initState();
    // The saved choices are read once; the pane shows them as soon as they are there.
    _vm.load();
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $what')));
  }

  @override
  Widget build(BuildContext context) {
    final styles = context.textStyles;
    final colors = context.colors;
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final settings = _vm.settings;
        final result = _vm.testResult;
        // On a hosted page nobody can be asked to run a program, so the Worker comes first there.
        final origin = _vm.pageOrigin;
        final hosted = origin != null && !CorsProxyOrigins.isLoopback(origin);
        final local = _localSection(context, settings.token.trim().isNotEmpty);
        final deploy = _deploySection(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CORS proxy', style: styles.heading),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'A browser only lets a web page call servers that allow it (CORS). The CORS proxy is a small program that '
                'forwards PostPilot\'s calls and adds the headers the server lacks.',
                style: styles.caption.copyWith(color: colors.secondaryText),
              ),
            ),
            SettingRow(
              title: 'Send requests through the CORS proxy',
              description: 'Off sends every call straight from the browser.',
              control: Switch(value: settings.enabled, onChanged: _vm.setEnabled),
            ),
            const SizedBox(height: 4),
            SyncedTextField(
              value: settings.url,
              labelText: 'Proxy URL',
              hintText: CorsProxyProtocol.defaultUrl,
              onChanged: _vm.setUrl,
            ),
            if (settings.urlProblem case final problem?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(problem, style: styles.caption.copyWith(color: colors.statusError)),
              ),
            const SizedBox(height: 12),
            SyncedTextField(
              value: settings.token,
              labelText: 'Token',
              hintText: 'The token the proxy printed, or the one you gave your Worker',
              obscureText: !_tokenVisible,
              suffixIcon: IconButton(
                icon: Icon(_tokenVisible ? Icons.visibility_off : Icons.visibility, size: 16),
                tooltip: _tokenVisible ? 'Hide token' : 'Show token',
                onPressed: () => setState(() => _tokenVisible = !_tokenVisible),
              ),
              onChanged: _vm.setToken,
            ),
            if (settings.tokenProblem case final problem?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(problem, style: styles.caption.copyWith(color: colors.statusError)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Kept encrypted in this browser only: never in the workspace file or in Git.',
                style: styles.caption.copyWith(color: colors.secondaryText),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  onPressed: _vm.testing || settings.baseUri == null || settings.tokenProblem != null ? null : _vm.test,
                  child: BusyLabel(busy: _vm.testing, label: 'Test connection', busyLabel: 'Testing…', icon: Icons.network_check),
                ),
                OutlinedButton.icon(
                  onPressed: _vm.generateToken,
                  icon: const Icon(Icons.vpn_key_outlined, size: 18),
                  label: const Text('Generate a token'),
                ),
              ],
            ),
            if (result != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: InfoBanner(
                  kind: result.ok ? BannerKind.success : BannerKind.warning,
                  title: result.title,
                  message: result.message,
                ),
              ),
            const SizedBox(height: 20),
            ...hosted ? [deploy, local] : [local, deploy],
          ],
        );
      },
    );
  }

  /// Run the proxy on this computer.
  Widget _localSection(BuildContext context, bool hasToken) {
    final styles = context.textStyles;
    final colors = context.colors;
    final origin = _vm.pageOrigin;
    return ToolSection(
      title: 'Run it on this computer',
      hint: 'In a terminal, in the PostPilot folder; leave it running. It prints the URL and the token.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 92, child: CodeBlock(text: _vm.command(), label: 'Terminal', wrap: true)),
          const SizedBox(height: 8),
          if (hasToken)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _copy(_vm.command(withToken: true), 'the command with your token'),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy with my token'),
                ),
              ],
            ),
          Text(
            'With the PostPilot desktop app you need no terminal: its command palette has "CORS proxy…".',
            style: styles.caption.copyWith(color: colors.secondaryText),
          ),
          if (origin != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'This page runs at $origin.${CorsProxyOrigins.isLoopback(origin) ? ' The proxy allows pages on this computer by default.' : ' The command above allows it.'}',
                style: styles.caption.copyWith(color: colors.secondaryText),
              ),
            ),
        ],
      ),
    );
  }

  /// Deploy a Worker of your own: for a hosted page, where no local program can be asked for.
  Widget _deploySection(BuildContext context) {
    final styles = context.textStyles;
    final colors = context.colors;
    return ToolSection(
      title: CorsProxyWorkerGuide.title,
      hint: CorsProxyWorkerGuide.intro,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, step) in CorsProxyWorkerGuide.steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${i + 1}. $step', style: styles.body),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: 214,
            child: CodeBlock(text: CorsProxyWorkerGuide.commands(pageOrigin: _vm.pageOrigin), label: 'Terminal'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Free plan: 100,000 calls a day. The Worker logs nothing, and anyone without your token gets a 401.',
              style: styles.caption.copyWith(color: colors.secondaryText),
            ),
          ),
        ],
      ),
    );
  }
}
