import 'package:flutter/material.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../settings/presentation/widgets/settings_dialog.dart';
import '../domain/cors_proxy_protocol.dart';

/// What the response area offers under a failed call in the browser: the way out of a CORS block (the CORS proxy), or the way
/// to fix a proxy that is on but cannot be used. Shown only when the failure carries a [NetworkHelp].
class CorsErrorHelp extends StatelessWidget {
  final NetworkHelp help;

  /// Replaces opening Settings > CORS proxy, for a test.
  final VoidCallback? onOpenSettings;

  const CorsErrorHelp({super.key, required this.help, this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final styles = context.textStyles;
    final blocked = help == NetworkHelp.corsBlocked;
    void openSettings() => onOpenSettings != null ? onOpenSettings!() : SettingsDialog.show(context, corsProxy: true);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: colors.mainAccent.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: openSettings,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: Text(blocked ? 'Use the CORS proxy' : 'Open the CORS proxy settings'),
              ),
              if (blocked) Text('Run this on your computer:', style: styles.caption.copyWith(color: colors.secondaryText)),
              if (blocked) SelectableText(CorsProxyProtocol.command, style: styles.mono.copyWith(fontSize: 12)),
            ],
          ),
          if (blocked)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'The proxy forwards your call and adds the headers the server lacks. Or open this request in the PostPilot '
                'desktop app, which is not limited by CORS.',
                style: styles.caption.copyWith(color: colors.secondaryText),
              ),
            ),
        ],
      ),
    );
  }
}
