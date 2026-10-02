import 'package:flutter/material.dart';
import '../theme/context_theme_extensions.dart';

/// The one dialog frame every developer tool uses, so Dart models, Odoo,
/// mock server, command palette and the rest look like one product: an accent
/// icon chip, title and subtitle, a hairline, the content, and an optional
/// footer. On a phone it fills the screen instead of floating.
class ToolDialog extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  /// Buttons for the footer, right-aligned. No footer when empty.
  final List<Widget> actions;

  /// Shown on the footer's left, e.g. a status line or a hint.
  final Widget? footerLeading;

  /// Widgets placed in the header, left of the close button.
  final List<Widget> headerActions;
  final double width;
  final double height;

  const ToolDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.footerLeading,
    this.headerActions = const [],
    this.width = 760,
    this.height = 560,
  });

  static Future<T?> show<T>(BuildContext context, WidgetBuilder builder, {bool barrierDismissible = true}) =>
      showDialog<T>(context: context, barrierDismissible: barrierDismissible, builder: builder);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = MediaQuery.sizeOf(context);
    final phone = size.width < 600;
    final w = phone ? size.width : width.clamp(320.0, size.width - 48);
    final h = phone ? size.height : height.clamp(320.0, size.height - 48);
    return Dialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: phone ? EdgeInsets.zero : const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(phone ? 0 : 14),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: w,
        height: h,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(icon: icon, title: title, subtitle: subtitle, actions: headerActions),
            Divider(height: 1, color: colors.border),
            Expanded(child: child),
            if (actions.isNotEmpty || footerLeading != null) ...[
              Divider(height: 1, color: colors.border),
              Container(
                color: colors.sidebarBackground.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    if (footerLeading != null) Expanded(flex: 2, child: footerLeading!) else const Spacer(),
                    // Wraps instead of overflowing when a narrow window cannot fit every button on one line.
                    Flexible(flex: 5, child: Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: actions)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const _Header({required this.icon, required this.title, required this.subtitle, required this.actions});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: colors.accentGradient,
              borderRadius: BorderRadius.circular(9),
              boxShadow: [BoxShadow(color: colors.glow.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: context.textStyles.heading, overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          ...actions,
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// A tab strip + body for use inside [ToolDialog]; keeps each tab alive.
class ToolTabs extends StatelessWidget {
  final List<ToolTab> tabs;
  final int initialIndex;
  const ToolTabs({super.key, required this.tabs, this.initialIndex = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: tabs.length,
      initialIndex: initialIndex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final t in tabs)
                  Tab(
                    height: 38,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Icon(t.icon, size: 15), const SizedBox(width: 6), Text(t.label)],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: TabBarView(children: [for (final t in tabs) t.child])),
        ],
      ),
    );
  }
}

class ToolTab {
  final String label;
  final IconData icon;
  final Widget child;
  const ToolTab({required this.label, required this.icon, required this.child});
}
