import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';

/// One feature of the Flow tab: a header with a switch and a one-line summary of what it is set to, and, while it
/// is on, its settings below. Off, it is only the header, so the tab stays short and quiet.
class FlowSection extends StatelessWidget {
  final String title;

  /// What the feature does, or (while on) how it is set: one line.
  final String summary;
  final bool enabled;
  final ValueChanged<bool> onToggle;

  /// The settings, shown while [enabled].
  final Widget child;

  const FlowSection({
    super.key,
    required this.title,
    required this.summary,
    required this.enabled,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: enabled ? colors.mainAccent.withValues(alpha: 0.45) : colors.border),
      ),
      // A Material of its own on top of the panel, so a tap on the header shows its ripple instead of painting it
      // under the panel's colour.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onToggle(!enabled),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: context.textStyles.heading),
                          Text(summary, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                        ],
                      ),
                    ),
                    Switch(value: enabled, onChanged: onToggle),
                  ],
                ),
              ),
            ),
            if (enabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: child,
              ),
          ],
        ),
      ),
    );
  }
}

/// A checkbox with a title and, under it, what it does: the compact form every option of the Flow tab uses. Not a
/// `CheckboxListTile`: a list tile paints on the nearest Material and complains when a coloured panel (every pane of
/// the request builder is one) sits between it and that Material.
class FlowCheckbox extends StatelessWidget {
  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const FlowCheckbox({super.key, required this.title, required this.value, required this.onChanged, this.description});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (checked) => onChanged(checked ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.textStyles.body),
                    if (description != null)
                      Text(description!, style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short explanation under a section's settings.
class FlowHint extends StatelessWidget {
  final String text;
  const FlowHint(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
      );
}
