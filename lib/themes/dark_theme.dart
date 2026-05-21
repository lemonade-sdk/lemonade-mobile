import 'package:flutter/material.dart';

import 'app_theme_def.dart';

class DarkTheme extends AppThemeDef {
  @override
  String get id => 'dark';

  @override
  String get displayName => 'Dark';

  @override
  String get description => 'Polished slate-and-indigo dark theme.';

  @override
  Brightness get brightness => Brightness.dark;

  @override
  ThemeData buildTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF818CF8),
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF0F172A),
      surfaceContainer: const Color(0xFF1E293B),
      surfaceContainerHigh: const Color(0xFF334155),
      surfaceContainerHighest: const Color(0xFF475569),
      primary: const Color(0xFF818CF8),
      secondary: const Color(0xFFA78BFA),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainer,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
