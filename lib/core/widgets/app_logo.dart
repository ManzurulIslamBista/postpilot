import 'package:flutter/material.dart';
import '../theme/context_theme_extensions.dart';

/// The PostPilot mark (paper plane on a dark tile), drawn in code so it stays
/// crisp at any size and needs no asset. Mirrors `tool/logo.svg`; the PNG
/// masters used for the platform launcher icons are rendered from that file.
class AppLogo extends StatelessWidget {
  final double size;

  /// Draws just the plane, without the dark rounded tile behind it.
  final bool markOnly;

  const AppLogo({super.key, this.size = 32, this.markOnly = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _LogoPainter(accent: colors.mainAccent, accentEnd: colors.accentSecondary, markOnly: markOnly),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  /// The plane takes its colours from the theme's accent gradient, so it
  /// follows any future re-skin; the dark tile is part of the fixed brand mark.
  final Color accent;
  final Color accentEnd;
  final bool markOnly;
  const _LogoPainter({required this.accent, required this.accentEnd, required this.markOnly});

  static const _tile = [Color(0xFF232842), Color(0xFF12141E), Color(0xFF0A0B11)];

  static Color _shade(Color c, double lightness) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + lightness).clamp(0.0, 1.0)).toColor();
  }

  // Coordinates are the 1024-unit design grid of tool/logo.svg.
  static const _unit = 1024.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _unit);

    if (!markOnly) {
      final tile = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, _unit, _unit), const Radius.circular(232));
      final tileRect = tile.outerRect;
      canvas.drawRRect(
        tile,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _tile,
            stops: [0, 0.55, 1],
          ).createShader(tileRect),
      );
      canvas.save();
      canvas.clipRRect(tile);
      canvas.drawRect(
        tileRect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0.44, -0.44),
            radius: 0.75,
            colors: [accent.withValues(alpha: 0.34), accentEnd.withValues(alpha: 0)],
          ).createShader(tileRect),
      );
      canvas.restore();
    }

    final wing = Path()
      ..moveTo(800, 236)
      ..lineTo(236, 486)
      ..lineTo(446, 586)
      ..close();
    final body = Path()
      ..moveTo(800, 236)
      ..lineTo(446, 586)
      ..lineTo(592, 810)
      ..close();
    final tail = Path()
      ..moveTo(446, 586)
      ..lineTo(592, 810)
      ..lineTo(396, 742)
      ..close();

    Shader grad(Rect r, Alignment a, Alignment b, Color c1, Color c2) =>
        LinearGradient(begin: a, end: b, colors: [c1, c2]).createShader(r);

    canvas.drawPath(
      wing,
      Paint()..shader = grad(wing.getBounds(), Alignment.bottomLeft, Alignment.topRight, accentEnd, _shade(accent, 0.04)),
    );
    canvas.drawPath(
      body,
      Paint()..shader = grad(body.getBounds(), Alignment.topLeft, Alignment.bottomRight, accent, _shade(accentEnd, -0.06)),
    );
    canvas.drawPath(
      tail,
      Paint()..shader = grad(tail.getBounds(), Alignment.topLeft, Alignment.bottomRight, _shade(accentEnd, -0.16), _shade(accentEnd, -0.26)),
    );
    canvas.drawLine(
      const Offset(800, 236),
      const Offset(446, 586),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.markOnly != markOnly || old.accent != accent || old.accentEnd != accentEnd;
}
