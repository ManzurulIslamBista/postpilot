import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/context_theme_extensions.dart';

/// A frosted-glass surface: translucent theme colour over a blurred copy of
/// whatever is behind it, with a hairline border. Used sparingly, on layers
/// that float above other content (top bar, overlays), never for body panels.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final double blur;

  /// Opacity of the tint; lower lets more of the backdrop through.
  final double opacity;
  final bool border;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = BorderRadius.zero,
    this.blur = 18,
    this.opacity = 0.72,
    this.border = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: opacity),
            borderRadius: borderRadius,
            border: border ? Border.all(color: colors.border.withValues(alpha: 0.8)) : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
