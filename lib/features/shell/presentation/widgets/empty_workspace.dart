import 'package:flutter/material.dart';
import '../../../../core/shortcuts/app_shortcuts.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/gradient_button.dart';

/// What the main area shows when no request is open: the brand mark, one clear
/// next step, and the shortcuts that make the app quick to drive.
class EmptyWorkspace extends StatelessWidget {
  final VoidCallback onNewRequest;
  final VoidCallback onImport;

  const EmptyWorkspace({super.key, required this.onNewRequest, required this.onImport});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textStyles = context.textStyles;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [BoxShadow(color: colors.glow, blurRadius: 36, spreadRadius: -6)],
                ),
                child: const AppLogo(size: 88),
              ),
              const SizedBox(height: 22),
              Text('PostPilot', style: textStyles.heading.copyWith(fontSize: 24, letterSpacing: -0.4)),
              const SizedBox(height: 6),
              Text(
                'Design, send and test APIs. Open a request from the sidebar, or start a new one.',
                textAlign: TextAlign.center,
                style: textStyles.body.copyWith(color: colors.secondaryText, height: 1.4),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  GradientButton(label: 'New request', icon: Icons.add_rounded, onPressed: onNewRequest),
                  OutlinedButton.icon(
                    onPressed: onImport,
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: const Text('Import'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Divider(color: colors.borderSubtle),
              const SizedBox(height: 14),
              for (final shortcut in const [
                AppShortcut.newRequest,
                AppShortcut.focusSearch,
                AppShortcut.sendRequest,
                AppShortcut.toggleSidebar,
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          shortcut.description,
                          style: textStyles.caption.copyWith(color: colors.secondaryText),
                        ),
                      ),
                      _KeyCap(label: shortcut.keyLabel),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  final String label;
  const _KeyCap({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 2, offset: const Offset(0, 1))],
      ),
      child: Text(label, style: context.textStyles.mono.copyWith(fontSize: 11.5)),
    );
  }
}
