import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

/// A desktop-first, IDE-like look (VS Code / Postman) rather than default
/// Material: flat surfaces, thin 1px borders instead of elevation shadows,
/// dense inputs, and an accent-colored focus/selection state throughout.
abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light, AppColors.light);
  static ThemeData get dark => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors colors) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.mainAccent,
      onPrimary: Colors.white,
      secondary: colors.mainAccent,
      onSecondary: Colors.white,
      error: colors.statusError,
      onError: Colors.white,
      surface: colors.surface,
      onSurface: colors.primaryText,
      surfaceContainerHighest: colors.sidebarBackground,
      onSurfaceVariant: colors.secondaryText,
      outline: colors.border,
      outlineVariant: colors.border,
    );

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: colors.border),
    );

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.appBackground,
      canvasColor: colors.appBackground,
      dividerColor: colors.border,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.compact,
      extensions: [colors, AppTextStyles.forColor(colors.primaryText)],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.primaryText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: colors.border)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        isDense: true,
        filled: true,
        fillColor: colors.appBackground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: BorderSide(color: colors.mainAccent, width: 1.5)),
        hintStyle: TextStyle(color: colors.secondaryText),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.mainAccent,
        unselectedLabelColor: colors.secondaryText,
        indicatorColor: colors.mainAccent,
        dividerColor: colors.border,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        dense: true,
        selectedTileColor: colors.mainAccent.withValues(alpha: 0.1),
        selectedColor: colors.mainAccent,
        iconColor: colors.secondaryText,
      ),
      iconTheme: IconThemeData(color: colors.secondaryText, size: 20),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.mainAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: colors.mainAccent)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primaryText,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: const WidgetStatePropertyAll(true),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(colors.secondaryText.withValues(alpha: 0.3)),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.mainAccent : Colors.transparent,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.mainAccent : colors.secondaryText,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: colors.border)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: colors.primaryText, borderRadius: BorderRadius.circular(4)),
        textStyle: TextStyle(color: colors.surface, fontSize: 12),
      ),
    );
  }
}
