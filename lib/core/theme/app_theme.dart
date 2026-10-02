import 'package:flutter/material.dart';
import '../widgets/gradient_underline_indicator.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

/// A polished desktop-first look: deep layered surfaces, hairline borders with
/// soft shadows on floating layers, a signature orange→pink accent gradient,
/// and compact type so a request fits comfortably on a laptop at 150% scaling.
abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light, AppColors.light);
  static ThemeData get dark => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors colors) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.mainAccent,
      onPrimary: Colors.white,
      secondary: colors.accentSecondary,
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

    OutlineInputBorder inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color, width: width),
        );

    // Material's default sizes (14/16) read oversized on a 150%-scaled laptop,
    // so the scale is set explicitly one step smaller. A partial TextTheme is
    // merged over the platform defaults, which keeps their weights and spacing.
    final textTheme = const TextTheme(
      headlineLarge: TextStyle(fontSize: 28),
      headlineMedium: TextStyle(fontSize: 24),
      headlineSmall: TextStyle(fontSize: 20),
      titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 14),
      bodyMedium: TextStyle(fontSize: 13),
      bodySmall: TextStyle(fontSize: 12),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
    ).apply(
      fontFamily: AppFonts.uiFamily,
      fontFamilyFallback: AppFonts.uiFallback,
      bodyColor: colors.primaryText,
      displayColor: colors.primaryText,
    );

    final shadow = brightness == Brightness.dark ? Colors.black : const Color(0xFF1B2333);
    final radius10 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      fontFamily: AppFonts.uiFamily,
      fontFamilyFallback: AppFonts.uiFallback,
      scaffoldBackgroundColor: colors.appBackground,
      canvasColor: colors.surfaceElevated,
      dividerColor: colors.border,
      splashFactory: NoSplash.splashFactory,
      hoverColor: colors.hover,
      highlightColor: Colors.transparent,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: colors.border)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 28,
        shadowColor: shadow.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.border),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colors.sidebarBackground,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        isDense: true,
        filled: true,
        fillColor: colors.appBackground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: inputBorder(colors.border),
        enabledBorder: inputBorder(colors.border),
        hoverColor: colors.hover,
        focusedBorder: inputBorder(colors.mainAccent, 1.4),
        errorBorder: inputBorder(colors.statusError),
        focusedErrorBorder: inputBorder(colors.statusError, 1.4),
        hintStyle: TextStyle(color: colors.secondaryText.withValues(alpha: 0.75)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.primaryText,
        unselectedLabelColor: colors.secondaryText,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        indicator: GradientUnderlineIndicator(gradient: colors.accentGradient),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: colors.borderSubtle,
        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
        overlayColor: WidgetStatePropertyAll(colors.hover),
      ),
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        dense: true,
        selectedTileColor: colors.mainAccent.withValues(alpha: 0.12),
        selectedColor: colors.mainAccent,
        iconColor: colors.secondaryText,
        shape: buttonShape,
      ),
      iconTheme: IconThemeData(color: colors.secondaryText, size: 20),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.secondaryText,
          hoverColor: colors.hover,
          highlightColor: Colors.transparent,
          shape: buttonShape,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.mainAccent,
          foregroundColor: Colors.white,
          shape: buttonShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colors.mainAccent, shape: buttonShape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primaryText,
          side: BorderSide(color: colors.border),
          shape: buttonShape,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(buttonShape),
          side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? Colors.white : colors.secondaryText,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? colors.mainAccent : Colors.transparent,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surface,
        selectedColor: colors.mainAccent,
        side: BorderSide(color: colors.border),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(color: colors.primaryText, fontSize: 12),
        secondaryLabelStyle: const TextStyle(color: Colors.white, fontSize: 12),
        checkmarkColor: Colors.white,
      ),
      scrollbarTheme: ScrollbarThemeData(
        // Hidden until the pointer is near or the content scrolls; an always-on
        // bar sat on top of the tab strip and cluttered every panel.
        thumbVisibility: const WidgetStatePropertyAll(false),
        trackVisibility: const WidgetStatePropertyAll(false),
        thickness: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.hovered) ? 9 : 6),
        radius: const Radius.circular(6),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => colors.secondaryText.withValues(alpha: states.contains(WidgetState.hovered) ? 0.55 : 0.32),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: colors.secondaryText.withValues(alpha: 0.7), width: 1.4),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.mainAccent : Colors.transparent,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.mainAccent : colors.secondaryText,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.mainAccent : colors.border,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 14,
        shadowColor: shadow.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: colors.border)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surfaceElevated),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(radius10),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.surfaceElevated,
        contentTextStyle: TextStyle(color: colors.primaryText, fontSize: 13),
        actionTextColor: colors.mainAccent,
        elevation: 10,
        width: 420,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: colors.border)),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: colors.mainAccent,
        collapsedIconColor: colors.secondaryText,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.mainAccent),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: colors.primaryText,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(color: colors.surface, fontSize: 12),
      ),
    );
  }
}
