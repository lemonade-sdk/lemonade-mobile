import 'package:flutter/material.dart';

import 'app_theme_def.dart';

class LightTheme extends AppThemeDef {
  @override
  String get id => 'light';

  @override
  String get displayName => 'Light';

  @override
  String get description => 'Clean, bright, high-contrast — daylight friendly.';

  @override
  Brightness get brightness => Brightness.light;

  @override
  ThemeData buildTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6366F1), // indigo
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFFAFAFA),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHighest,
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
