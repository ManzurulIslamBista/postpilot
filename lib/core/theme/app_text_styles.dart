import 'package:flutter/material.dart';

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
    heading: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    body: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
    caption: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
    mono: TextStyle(fontSize: 13, fontFamily: 'monospace'),
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
