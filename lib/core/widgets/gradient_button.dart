import 'package:flutter/material.dart';
import '../theme/context_theme_extensions.dart';

/// The primary call-to-action: accent gradient fill with a soft glow that
/// intensifies on hover. A plain [FilledButton] cannot paint a gradient.
class GradientButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Shows a spinner in place of the icon and ignores presses.
  final bool loading;
  final EdgeInsetsGeometry padding;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.onPressed != null && !widget.loading;
    final glowAlpha = !enabled ? 0.0 : (_hovered ? 0.55 : 0.28);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: widget.padding,
            decoration: BoxDecoration(
              gradient: enabled ? colors.accentGradient : null,
              color: enabled ? null : colors.border,
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: colors.mainAccent.withValues(alpha: glowAlpha),
                  blurRadius: _hovered ? 18 : 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.loading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                else if (widget.icon != null)
                  Icon(widget.icon, size: 16, color: Colors.white),
                if (widget.loading || widget.icon != null) const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
