import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

extension ContextThemeExtensions on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get scheme => theme.colorScheme;
  AppColors get colors => theme.extension<AppColors>()!;
  AppTextStyles get textStyles => theme.extension<AppTextStyles>()!;
}
