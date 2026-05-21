import 'package:flutter/material.dart';

import 'app_theme_def.dart';

/// Warm-toned middle ground between light and dark. Reduced contrast for long
/// reading sessions; cream backgrounds, mocha surfaces, terracotta accents.
class MediumTheme extends AppThemeDef {
  @override
  String get id => 'medium';

  @override
  String get displayName => 'Medium';

  @override
  String get description => 'Warm sepia tones — easy on the eyes for long sessions.';

  @override
  Brightness get brightness => Brightness.light;

  @override
  ThemeData buildTheme() {
    const seed = Color(0xFF8B5E34); // mocha
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ).copyWith(
      surface: const Color(0xFFF5EFE6),
      surfaceContainer: const Color(0xFFEAE0D0),
      surfaceContainerHigh: const Color(0xFFE0D4BF),
      surfaceContainerHighest: const Color(0xFFD4C4A8),
      primary: const Color(0xFF8B5E34),
      onPrimary: const Color(0xFFFFFBF1),
      secondary: const Color(0xFF6B7F6B), // muted sage
      tertiary: const Color(0xFFB5651D), // burnt sienna
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF5EFE6),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainer,
        foregroundColor: const Color(0xFF3E2A1F),
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
