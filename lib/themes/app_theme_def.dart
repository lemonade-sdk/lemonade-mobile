import 'package:flutter/material.dart';

/// Decorative knobs for theme-specific visual flair beyond what Material 3
/// expresses out of the box. Defaults to "off" for plain themes.
class ThemeDecorations {
  /// Subtle horizontal scanline overlay (CRT vibe). Used by AI Super Hack.
  final bool useScanlines;

  /// Title text gets a glitch / chromatic-aberration shadow stack.
  final bool useGlitchTitles;

  /// AppBar background gets an animated gradient sweep.
  final bool animatedGradientAppBar;

  /// Outline glow on selected items / focused inputs.
  final Color? glowColor;

  /// Optional override for the typeface family the theme uses.
  final String? monoFontFamily;

  /// Color for animated cursor / blinking caret affordances.
  final Color? caretColor;

  const ThemeDecorations({
    this.useScanlines = false,
    this.useGlitchTitles = false,
    this.animatedGradientAppBar = false,
    this.glowColor,
    this.monoFontFamily,
    this.caretColor,
  });

  static const ThemeDecorations none = ThemeDecorations();
}

/// Base class for every theme. Themes are pure data: they expose a [ThemeData]
/// (built once, cached by the registry) plus optional [ThemeDecorations] for
/// effects that fall outside Material's vocabulary.
abstract class AppThemeDef {
  /// Stable string id (persisted). Avoid renaming.
  String get id;

  /// Human-readable label shown in the theme picker.
  String get displayName;

  /// One-line description shown under the displayName in the picker.
  String get description;

  /// Underlying brightness — used by status bar / system chrome theming.
  Brightness get brightness;

  /// Material theme.
  ThemeData buildTheme();

  /// Optional decorative knobs.
  ThemeDecorations get decorations => ThemeDecorations.none;
}
