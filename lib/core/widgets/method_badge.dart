import 'package:flutter/material.dart';
import '../theme/context_theme_extensions.dart';

/// HTTP method as a tinted pill, coloured per verb. Fixed width so a column of
/// them (sidebar, tabs) lines up.
class MethodBadge extends StatelessWidget {
  final String method;
  final double width;

  const MethodBadge({super.key, required this.method, this.width = 42});

  @override
  Widget build(BuildContext context) {
    final color = context.colors.forMethod(method);
    final label = method.toUpperCase();
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        // DELETE / OPTIONS do not fit a pill this narrow at full length.
        label.length > 4 ? label.substring(0, 3) : label,
        maxLines: 1,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 0.3),
      ),
    );
  }
}
