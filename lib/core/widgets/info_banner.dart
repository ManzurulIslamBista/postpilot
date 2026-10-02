import 'package:flutter/material.dart';
import '../theme/context_theme_extensions.dart';

enum BannerKind { info, success, warning, error }

/// A tinted, bordered message strip: the one way tools report a state
/// ("Server is running", "Odoo error", "Remote changed").
class InfoBanner extends StatelessWidget {
  final BannerKind kind;
  final String message;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;

  const InfoBanner({
    super.key,
    required this.message,
    this.kind = BannerKind.info,
    this.title,
    this.trailing,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (color, icon) = switch (kind) {
      BannerKind.info => (colors.methodPut, Icons.info_outline),
      BannerKind.success => (colors.statusSuccess, Icons.check_circle_outline),
      BannerKind.warning => (colors.statusWarning, Icons.warning_amber_rounded),
      BannerKind.error => (colors.statusError, Icons.error_outline),
    };
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(title!, style: context.textStyles.body.copyWith(fontWeight: FontWeight.w700, color: color)),
                SelectableText(message, style: context.textStyles.body),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// Centered icon + text for a panel with nothing to show yet.
class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const EmptyHint({super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: colors.mainAccent.withValues(alpha: 0.10), shape: BoxShape.circle),
              child: Icon(icon, size: 24, color: colors.mainAccent),
            ),
            const SizedBox(height: 14),
            Text(title, style: context.textStyles.heading, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: context.textStyles.body.copyWith(color: colors.secondaryText),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // No height limit (inside a scroll view or a plain Column): nothing can overflow.
        if (!constraints.hasBoundedHeight) return Center(child: content);
        // Centred while there is room; scrolls instead of overflowing in a small panel.
        return SingleChildScrollView(
          primary: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}

/// A labelled group inside a tool: small caps title, optional hint, content.
class ToolSection extends StatelessWidget {
  final String title;
  final String? hint;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ToolSection({
    super.key,
    required this.title,
    required this.child,
    this.hint,
    this.padding = const EdgeInsets.only(bottom: 16),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: context.textStyles.caption.copyWith(
              color: colors.secondaryText,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 3),
            Text(hint!, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
          ],
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
