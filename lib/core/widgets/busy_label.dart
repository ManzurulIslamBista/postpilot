import 'package:flutter/material.dart';

/// Content for a button that starts async work. While [busy] it keeps its words
/// and shows a spinner beside them ("Importing…"), instead of swapping the text
/// for a lone spinner: the user still sees what the button does and what it is
/// doing now. Put it in any button's `child`; the spinner takes the button's own
/// foreground colour, so it stays visible on filled and outlined buttons alike.
class BusyLabel extends StatelessWidget {
  final bool busy;
  final String label;

  /// Shown instead of [label] while busy, e.g. "Saving…".
  final String busyLabel;

  /// Leading icon shown when idle; the spinner takes its place while busy.
  final IconData? icon;
  final double iconSize;

  const BusyLabel({
    super.key,
    required this.busy,
    required this.label,
    required this.busyLabel,
    this.icon,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color;
    final leading = busy
        ? SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: color))
        : icon == null
        ? null
        : Icon(icon, size: iconSize);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 8)],
        Flexible(child: Text(busy ? busyLabel : label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
