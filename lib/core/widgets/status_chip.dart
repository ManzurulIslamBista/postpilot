import 'package:flutter/material.dart';
import '../theme/context_theme_extensions.dart';

/// A small rounded readout (status, time, size). With [color] set it is tinted
/// and bold, otherwise a neutral outline chip.
class StatusChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;

  const StatusChip({super.key, required this.label, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = color;
    final fg = tint ?? colors.secondaryText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tint?.withValues(alpha: 0.13) ?? colors.hover,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint?.withValues(alpha: 0.35) ?? colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 5)],
          Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: tint == null ? FontWeight.w500 : FontWeight.w700)),
        ],
      ),
    );
  }
}
