import 'package:flutter/material.dart';

/// A rounded gradient bar under the selected tab, used as the app-wide
/// [TabBar.indicator] so tabs share the accent gradient instead of a flat line.
class GradientUnderlineIndicator extends Decoration {
  final Gradient gradient;
  final double thickness;

  const GradientUnderlineIndicator({required this.gradient, this.thickness = 2.5});

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _Painter(this);
}

class _Painter extends BoxPainter {
  final GradientUnderlineIndicator decoration;
  _Painter(this.decoration);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final rect = Rect.fromLTWH(
      offset.dx,
      offset.dy + size.height - decoration.thickness,
      size.width,
      decoration.thickness,
    );
    final paint = Paint()..shader = decoration.gradient.createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(2), topRight: const Radius.circular(2)),
      paint,
    );
  }
}
