import 'package:flutter/material.dart';

class AppColors {
  // Light theme colors
  static const primaryLight = Color(0xFF6366F1); // Indigo
  static const secondaryLight = Color(0xFF8B5CF6); // Purple
  static const backgroundLight = Color(0xFFFAFAFA);
  static const surfaceLight = Colors.white;
  static const surfaceVariantLight = Color(0xFFF8FAFC);
  static const errorLight = Color(0xFFEF4444);
  static const onPrimaryLight = Colors.white;
  static const onBackgroundLight = Color(0xFF1F2937);
  static const onSurfaceLight = Color(0xFF374151);
  static const userMessageLight = Color(0xFF6366F1);
  static const assistantMessageLight = Color(0xFFF1F5F9);
  static const borderLight = Color(0xFFE5E7EB);

  // Dark theme colors
  static const primaryDark = Color(0xFF818CF8); // Lighter indigo for dark
  static const secondaryDark = Color(0xFFA78BFA); // Lighter purple for dark
  static const backgroundDark = Color(0xFF0F172A); // Dark slate
  static const surfaceDark = Color(0xFF1E293B); // Slate
  static const surfaceVariantDark = Color(0xFF334155); // Lighter slate
  static const errorDark = Color(0xFFF87171);
  static const onPrimaryDark = Colors.white;
  static const onBackgroundDark = Color(0xFFF1F5F9);
  static const onSurfaceDark = Color(0xFFE2E8F0);
  static const userMessageDark = Color(0xFF6366F1);
  static const assistantMessageDark = Color(0xFF334155);
  static const borderDark = Color(0xFF475569);
}

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: AppColors.primaryLight,
    scaffoldBackgroundColor: AppColors.backgroundLight,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surfaceLight,
      foregroundColor: AppColors.onBackgroundLight,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.surfaceLight,
    ),
    cardTheme: const CardThemeData(
      shadowColor: Color(0x0F000000),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceVariantLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryLight,
        foregroundColor: AppColors.onPrimaryLight,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    colorScheme: const ColorScheme.light(
      primary: AppColors.primaryLight,
      secondary: AppColors.secondaryLight,
      surface: AppColors.surfaceLight,
      error: AppColors.errorLight,
      onPrimary: AppColors.onPrimaryLight,
      onSurface: AppColors.onSurfaceLight,
      surfaceContainerHighest: AppColors.surfaceVariantLight,
    ),
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: AppColors.primaryDark,
    scaffoldBackgroundColor: AppColors.backgroundDark,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surfaceDark,
      foregroundColor: AppColors.onBackgroundDark,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: AppColors.surfaceDark,
    ),
    cardTheme: const CardThemeData(
      shadowColor: Color(0x4D000000),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryDark, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: AppColors.onPrimaryDark,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primaryDark,
      secondary: AppColors.secondaryDark,
      surface: AppColors.surfaceDark,
      error: AppColors.errorDark,
      onPrimary: AppColors.onPrimaryDark,
      onSurface: AppColors.onSurfaceDark,
      surfaceContainerHighest: AppColors.surfaceVariantDark,
    ),
  );
}
