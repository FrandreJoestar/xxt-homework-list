import 'package:flutter/material.dart';

/// 应用配色：冷白底 + 深墨蓝文字，钴蓝作为主色；
/// 紧迫度用琥珀 / 砖红 / 灰绿三种信号色，仅出现在状态与倒计时上。
class AppColors {
  static const background = Color(0xFFF4F5F8);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF16233C);
  static const muted = Color(0xFF6B768C);
  static const accent = Color(0xFF2E5BFF);
  static const pending = Color(0xFFBF6A00);
  static const success = Color(0xFF1F7A52);
  static const danger = Color(0xFFC63A2F);
  static const line = Color(0xFFE4E7EF);
  static const fill = Color(0xFFF6F7FB);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.accent).copyWith(
    primary: AppColors.accent,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
  );

  OutlineInputBorder border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.ink,
      unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.accent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.line,
      labelStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: border(AppColors.line),
      enabledBorder: border(AppColors.line),
      focusedBorder: border(AppColors.accent, 1.4),
      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
