import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color appBackground;
  final Color surface;

  /// A step above [surface]: dialogs, popups, hovered cards.
  final Color surfaceElevated;
  final Color sidebarBackground;
  final Color border;

  /// A hairline softer than [border], for dividers inside a panel.
  final Color borderSubtle;
  final Color primaryText;
  final Color secondaryText;
  final Color mainAccent;

  /// The far end of the accent gradient (the near end is [mainAccent]).
  final Color accentSecondary;
  final Color methodGet;
  final Color methodPost;
  final Color methodPut;
  final Color methodPatch;
  final Color methodDelete;
  final Color statusSuccess;
  final Color statusWarning;
  final Color statusError;
  final Color syntaxKey;
  final Color syntaxString;
  final Color syntaxNumber;
  final Color syntaxKeyword;

  const AppColors({
    required this.appBackground,
    required this.surface,
    required this.surfaceElevated,
    required this.sidebarBackground,
    required this.border,
    required this.borderSubtle,
    required this.primaryText,
    required this.secondaryText,
    required this.mainAccent,
    required this.accentSecondary,
    required this.methodGet,
    required this.methodPost,
    required this.methodPut,
    required this.methodPatch,
    required this.methodDelete,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusError,
    required this.syntaxKey,
    required this.syntaxString,
    required this.syntaxNumber,
    required this.syntaxKeyword,
  });

  static const light = AppColors(
    appBackground: Color(0xFFF3F4F8),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    sidebarBackground: Color(0xFFEBEDF3),
    border: Color(0xFFDCE0E8),
    borderSubtle: Color(0xFFE8EBF1),
    primaryText: Color(0xFF181B22),
    secondaryText: Color(0xFF677085),
    mainAccent: Color(0xFFFF6C37),
    accentSecondary: Color(0xFFF03E7E),
    methodGet: Color(0xFF1E8E3E),
    methodPost: Color(0xFFB35A00),
    methodPut: Color(0xFF1565C0),
    methodPatch: Color(0xFF7B1FA2),
    methodDelete: Color(0xFFC62828),
    statusSuccess: Color(0xFF1E8E3E),
    statusWarning: Color(0xFFB35A00),
    statusError: Color(0xFFC62828),
    syntaxKey: Color(0xFF1F5FBF),
    syntaxString: Color(0xFF1E7A3C),
    syntaxNumber: Color(0xFFB4510F),
    syntaxKeyword: Color(0xFF8A3FB5),
  );

  static const dark = AppColors(
    appBackground: Color(0xFF0D0F14),
    surface: Color(0xFF151821),
    surfaceElevated: Color(0xFF1C202B),
    sidebarBackground: Color(0xFF11141B),
    border: Color(0xFF272B38),
    borderSubtle: Color(0xFF1D212C),
    primaryText: Color(0xFFE9EBF1),
    secondaryText: Color(0xFF8E95A6),
    mainAccent: Color(0xFFFF7A45),
    accentSecondary: Color(0xFFFF4D8D),
    methodGet: Color(0xFF4CC38A),
    methodPost: Color(0xFFF0B04A),
    methodPut: Color(0xFF5AAEFF),
    methodPatch: Color(0xFFC58BE8),
    methodDelete: Color(0xFFF2625B),
    statusSuccess: Color(0xFF4CC38A),
    statusWarning: Color(0xFFF0B04A),
    statusError: Color(0xFFF2625B),
    syntaxKey: Color(0xFF7CB7FF),
    syntaxString: Color(0xFF8FD694),
    syntaxNumber: Color(0xFFF5A66B),
    syntaxKeyword: Color(0xFFD29BF0),
  );

  /// Orange → pink: the signature gradient (Send button, active tab, focus).
  LinearGradient get accentGradient => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [mainAccent, accentSecondary],
      );

  /// Soft coloured halo behind accent surfaces.
  Color get glow => mainAccent.withValues(alpha: 0.35);

  /// Drop-shadow tint for floating panels: deep on dark surfaces, faint on light.
  Color get shadow => appBackground.computeLuminance() < 0.5
      ? Colors.black.withValues(alpha: 0.35)
      : const Color(0xFF1B2333).withValues(alpha: 0.10);

  /// Hover/pressed wash that works on both the light and the dark surfaces.
  Color get hover => primaryText.withValues(alpha: 0.06);

  @override
  AppColors copyWith({
    Color? appBackground,
    Color? surface,
    Color? surfaceElevated,
    Color? sidebarBackground,
    Color? border,
    Color? borderSubtle,
    Color? primaryText,
    Color? secondaryText,
    Color? mainAccent,
    Color? accentSecondary,
    Color? methodGet,
    Color? methodPost,
    Color? methodPut,
    Color? methodPatch,
    Color? methodDelete,
    Color? statusSuccess,
    Color? statusWarning,
    Color? statusError,
    Color? syntaxKey,
    Color? syntaxString,
    Color? syntaxNumber,
    Color? syntaxKeyword,
  }) =>
      AppColors(
        appBackground: appBackground ?? this.appBackground,
        surface: surface ?? this.surface,
        surfaceElevated: surfaceElevated ?? this.surfaceElevated,
        sidebarBackground: sidebarBackground ?? this.sidebarBackground,
        border: border ?? this.border,
        borderSubtle: borderSubtle ?? this.borderSubtle,
        primaryText: primaryText ?? this.primaryText,
        secondaryText: secondaryText ?? this.secondaryText,
        mainAccent: mainAccent ?? this.mainAccent,
        accentSecondary: accentSecondary ?? this.accentSecondary,
        methodGet: methodGet ?? this.methodGet,
        methodPost: methodPost ?? this.methodPost,
        methodPut: methodPut ?? this.methodPut,
        methodPatch: methodPatch ?? this.methodPatch,
        methodDelete: methodDelete ?? this.methodDelete,
        statusSuccess: statusSuccess ?? this.statusSuccess,
        statusWarning: statusWarning ?? this.statusWarning,
        statusError: statusError ?? this.statusError,
        syntaxKey: syntaxKey ?? this.syntaxKey,
        syntaxString: syntaxString ?? this.syntaxString,
        syntaxNumber: syntaxNumber ?? this.syntaxNumber,
        syntaxKeyword: syntaxKeyword ?? this.syntaxKeyword,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      appBackground: mix(appBackground, other.appBackground),
      surface: mix(surface, other.surface),
      surfaceElevated: mix(surfaceElevated, other.surfaceElevated),
      sidebarBackground: mix(sidebarBackground, other.sidebarBackground),
      border: mix(border, other.border),
      borderSubtle: mix(borderSubtle, other.borderSubtle),
      primaryText: mix(primaryText, other.primaryText),
      secondaryText: mix(secondaryText, other.secondaryText),
      mainAccent: mix(mainAccent, other.mainAccent),
      accentSecondary: mix(accentSecondary, other.accentSecondary),
      methodGet: mix(methodGet, other.methodGet),
      methodPost: mix(methodPost, other.methodPost),
      methodPut: mix(methodPut, other.methodPut),
      methodPatch: mix(methodPatch, other.methodPatch),
      methodDelete: mix(methodDelete, other.methodDelete),
      statusSuccess: mix(statusSuccess, other.statusSuccess),
      statusWarning: mix(statusWarning, other.statusWarning),
      statusError: mix(statusError, other.statusError),
      syntaxKey: mix(syntaxKey, other.syntaxKey),
      syntaxString: mix(syntaxString, other.syntaxString),
      syntaxNumber: mix(syntaxNumber, other.syntaxNumber),
      syntaxKeyword: mix(syntaxKeyword, other.syntaxKeyword),
    );
  }

  Color forMethod(String method) => switch (method.toUpperCase()) {
        'GET' => methodGet,
        'POST' => methodPost,
        'PUT' => methodPut,
        'PATCH' => methodPatch,
        'DELETE' => methodDelete,
        _ => secondaryText,
      };

  /// Colour for an HTTP status: 2xx green, 3xx blue, 4xx amber, 5xx red.
  Color forStatus(int code) {
    if (code >= 500) return statusError;
    if (code >= 400) return statusWarning;
    if (code >= 300) return methodPut;
    if (code >= 200) return statusSuccess;
    return secondaryText;
  }
}
