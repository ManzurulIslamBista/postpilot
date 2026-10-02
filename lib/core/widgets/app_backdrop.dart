import 'package:flutter/material.dart';
import '../theme/context_theme_extensions.dart';

/// The app's base layer: the theme background with two faint accent washes in
/// opposite corners, so panels floating above it read as layered glass rather
/// than flat rectangles. Purely decorative and cheap (two gradients, no blur).
class AppBackdrop extends StatelessWidget {
  final Widget child;
  const AppBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.appBackground),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.95, -1.05),
            radius: 1.1,
            colors: [colors.mainAccent.withValues(alpha: 0.07), Colors.transparent],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.9, 1.1),
              radius: 1.0,
              colors: [colors.accentSecondary.withValues(alpha: 0.05), Colors.transparent],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
