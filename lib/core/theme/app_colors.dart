import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color appBackground;
  final Color surface;
  final Color sidebarBackground;
  final Color border;
  final Color primaryText;
  final Color secondaryText;
  final Color mainAccent;
  final Color methodGet;
  final Color methodPost;
  final Color methodPut;
  final Color methodPatch;
  final Color methodDelete;
  final Color statusSuccess;
  final Color statusError;

  const AppColors({
    required this.appBackground,
    required this.surface,
    required this.sidebarBackground,
    required this.border,
    required this.primaryText,
    required this.secondaryText,
    required this.mainAccent,
    required this.methodGet,
    required this.methodPost,
    required this.methodPut,
    required this.methodPatch,
    required this.methodDelete,
    required this.statusSuccess,
    required this.statusError,
  });

  static const light = AppColors(
    appBackground: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    sidebarBackground: Color(0xFFEFF1F5),
    border: Color(0xFFE1E4EA),
    primaryText: Color(0xFF1A1D24),
    secondaryText: Color(0xFF6B7280),
    mainAccent: Color(0xFFFF6C37),
    methodGet: Color(0xFF2E7D32),
    methodPost: Color(0xFFB35A00),
    methodPut: Color(0xFF1565C0),
    methodPatch: Color(0xFF6A1B9A),
    methodDelete: Color(0xFFC62828),
    statusSuccess: Color(0xFF2E7D32),
    statusError: Color(0xFFC62828),
  );

  static const dark = AppColors(
    appBackground: Color(0xFF15171C),
    surface: Color(0xFF1D2027),
    sidebarBackground: Color(0xFF191B21),
    border: Color(0xFF2C2F38),
    primaryText: Color(0xFFE7E9ED),
    secondaryText: Color(0xFF9AA0AC),
    mainAccent: Color(0xFFFF6C37),
    methodGet: Color(0xFF4CAF50),
    methodPost: Color(0xFFE0A030),
    methodPut: Color(0xFF4FA3F7),
    methodPatch: Color(0xFFBB6BD9),
    methodDelete: Color(0xFFE0554F),
    statusSuccess: Color(0xFF4CAF50),
    statusError: Color(0xFFE0554F),
  );

  @override
  AppColors copyWith({
    Color? appBackground,
    Color? surface,
    Color? sidebarBackground,
    Color? border,
    Color? primaryText,
    Color? secondaryText,
    Color? mainAccent,
    Color? methodGet,
    Color? methodPost,
    Color? methodPut,
    Color? methodPatch,
    Color? methodDelete,
    Color? statusSuccess,
    Color? statusError,
  }) =>
      AppColors(
        appBackground: appBackground ?? this.appBackground,
        surface: surface ?? this.surface,
        sidebarBackground: sidebarBackground ?? this.sidebarBackground,
        border: border ?? this.border,
        primaryText: primaryText ?? this.primaryText,
        secondaryText: secondaryText ?? this.secondaryText,
        mainAccent: mainAccent ?? this.mainAccent,
        methodGet: methodGet ?? this.methodGet,
        methodPost: methodPost ?? this.methodPost,
        methodPut: methodPut ?? this.methodPut,
        methodPatch: methodPatch ?? this.methodPatch,
        methodDelete: methodDelete ?? this.methodDelete,
        statusSuccess: statusSuccess ?? this.statusSuccess,
        statusError: statusError ?? this.statusError,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      appBackground: Color.lerp(appBackground, other.appBackground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      sidebarBackground: Color.lerp(sidebarBackground, other.sidebarBackground, t)!,
      border: Color.lerp(border, other.border, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      mainAccent: Color.lerp(mainAccent, other.mainAccent, t)!,
      methodGet: Color.lerp(methodGet, other.methodGet, t)!,
      methodPost: Color.lerp(methodPost, other.methodPost, t)!,
      methodPut: Color.lerp(methodPut, other.methodPut, t)!,
      methodPatch: Color.lerp(methodPatch, other.methodPatch, t)!,
      methodDelete: Color.lerp(methodDelete, other.methodDelete, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusError: Color.lerp(statusError, other.statusError, t)!,
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
}
