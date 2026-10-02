import 'package:flutter/material.dart';

/// Font stacks, in preference order. Every desktop OS ships one of these, so
/// nothing has to be bundled or downloaded; the web build falls through to the
/// last entries.
abstract final class AppFonts {
  static const uiFamily = 'Segoe UI';
  static const uiFallback = ['SF Pro Text', 'Inter', 'Roboto', 'Helvetica Neue', 'Arial', 'sans-serif'];

  /// There is no generic "monospace" family on Windows/macOS, so code text
  /// needs a concrete name or it silently renders in the proportional UI font.
  static const monoFamily = 'Cascadia Mono';
  static const monoFallback = ['Consolas', 'SF Mono', 'Menlo', 'Roboto Mono', 'Courier New', 'monospace'];
}

@immutable
class AppTextStyles extends ThemeExtension<AppTextStyles> {
  final TextStyle heading;
  final TextStyle body;
  final TextStyle caption;
  final TextStyle mono;

  const AppTextStyles({
    required this.heading,
    required this.body,
    required this.caption,
    required this.mono,
  });

  static const _base = AppTextStyles(
    heading: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.1),
    body: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
    caption: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
    mono: TextStyle(
      fontSize: 12.5,
      height: 1.45,
      fontFamily: AppFonts.monoFamily,
      fontFamilyFallback: AppFonts.monoFallback,
    ),
  );

  static AppTextStyles forColor(Color color) => AppTextStyles(
        heading: _base.heading.copyWith(color: color),
        body: _base.body.copyWith(color: color),
        caption: _base.caption.copyWith(color: color),
        mono: _base.mono.copyWith(color: color),
      );

  @override
  AppTextStyles copyWith({TextStyle? heading, TextStyle? body, TextStyle? caption, TextStyle? mono}) =>
      AppTextStyles(
        heading: heading ?? this.heading,
        body: body ?? this.body,
        caption: caption ?? this.caption,
        mono: mono ?? this.mono,
      );

  @override
  AppTextStyles lerp(ThemeExtension<AppTextStyles>? other, double t) {
    if (other is! AppTextStyles) return this;
    return AppTextStyles(
      heading: TextStyle.lerp(heading, other.heading, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
      mono: TextStyle.lerp(mono, other.mono, t)!,
    );
  }
}
