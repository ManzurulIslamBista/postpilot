import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/sync_doc.dart';

enum GitBannerKind { error, warning, success, info }

/// Inline message strip: the place where failures and confirmations show up instead of snack bars.
class GitBanner extends StatelessWidget {
  final String message;
  final GitBannerKind kind;
  const GitBanner({super.key, required this.message, this.kind = GitBannerKind.info});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (color, icon) = switch (kind) {
      GitBannerKind.error => (colors.statusError, Icons.error_outline),
      GitBannerKind.warning => (colors.methodPost, Icons.warning_amber_rounded),
      GitBannerKind.success => (colors.statusSuccess, Icons.check_circle_outline),
      GitBannerKind.info => (colors.secondaryText, Icons.info_outline),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 16, color: color)),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(message, style: context.textStyles.body.copyWith(fontSize: 13))),
        ],
      ),
    );
  }
}

class GitChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final VoidCallback? onTap;
  const GitChip({super.key, required this.label, required this.color, this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return InkWell(borderRadius: BorderRadius.circular(999), onTap: onTap, child: chip);
  }
}

/// Underlined accent text that hands its [url] to [onOpen] (the view model opens it and reports failures inline).
class GitLinkText extends StatelessWidget {
  final String label;
  final String url;
  final ValueChanged<String> onOpen;
  final TextStyle? style;
  final bool showIcon;
  const GitLinkText({
    super.key,
    required this.label,
    required this.url,
    required this.onOpen,
    this.style,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.mainAccent;
    return InkWell(
      onTap: () => onOpen(url),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: (style ?? context.textStyles.body).copyWith(color: accent, decoration: TextDecoration.underline),
            ),
          ),
          if (showIcon) ...[const SizedBox(width: 4), Icon(Icons.open_in_new, size: 12, color: accent)],
        ],
      ),
    );
  }
}

/// Thin progress line with a fixed height so showing it never shifts the layout below.
class GitBusyBar extends StatelessWidget {
  final bool busy;
  const GitBusyBar({super.key, required this.busy});

  @override
  Widget build(BuildContext context) => SizedBox(height: 2, child: busy ? const LinearProgressIndicator() : null);
}

/// Under the "Include credentials in commits" switch: what stays out of commits while it is off, stated exactly.
const gitCredentialsOffHint = 'When off, auth settings and credential-looking values (variables, headers, URL and '
    'form parameters, JSON body fields named like a token, password, secret, API key or Authorization) are left out. '
    'Everything else is committed.';

class GitCredentialsWarning extends StatelessWidget {
  const GitCredentialsWarning({super.key});

  @override
  Widget build(BuildContext context) {
    final color = context.colors.statusError;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(Icons.warning_amber_rounded, size: 16, color: color)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Tokens, passwords and API keys stored in this collection would be visible to everyone who can access the repository.',
            style: context.textStyles.caption.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class GitPanelTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? busyLabel;

  /// False while a change is being written: closing then would not stop it and would lose its result.
  final bool canClose;
  const GitPanelTitle({super.key, required this.title, this.subtitle, this.busyLabel, this.canClose = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.textStyles.heading),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
                  ),
              ],
            ),
          ),
          if (busyLabel != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                busyLabel!,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.caption.copyWith(color: context.colors.mainAccent),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: canClose ? () => Navigator.pop(context) : null,
          ),
        ],
      ),
    );
  }
}

IconData gitKindIcon(SyncKind kind) => switch (kind) {
      SyncKind.collection => Icons.inventory_2_outlined,
      SyncKind.folder => Icons.folder_outlined,
      SyncKind.request => Icons.send_outlined,
    };

String gitKindLabel(SyncKind kind) => switch (kind) {
      SyncKind.collection => 'Collection',
      SyncKind.folder => 'Folder',
      SyncKind.request => 'Request',
    };

/// Windows and macOS have no generic "monospace" family, so the theme's mono style needs a concrete fallback there.
TextStyle gitMono(BuildContext context) =>
    context.textStyles.mono.copyWith(fontSize: 12, fontFamilyFallback: const ['Consolas', 'Menlo', 'Courier New']);
