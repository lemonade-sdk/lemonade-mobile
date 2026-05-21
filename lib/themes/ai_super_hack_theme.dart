import 'package:flutter/material.dart';

import 'app_theme_def.dart';

/// Cyberpunk / hacker aesthetic. Black backdrop, neon-green primary, hot-pink
/// and cyan accents, monospace everywhere. Pair with the [AiSuperHackOverlay]
/// widget (in widgets/) to layer scanlines and a glow pass over the whole app.
class AiSuperHackTheme extends AppThemeDef {
  static const Color _bg = Color(0xFF050505);
  static const Color _bgRaised = Color(0xFF0E0E0E);
  static const Color _bgRaised2 = Color(0xFF161616);
  static const Color _bgRaised3 = Color(0xFF1F1F1F);

  static const Color neonGreen = Color(0xFF39FF14);
  static const Color hotPink = Color(0xFFFF1493);
  static const Color cyan = Color(0xFF00FFFF);
  static const Color magenta = Color(0xFFFF00FF);
  static const Color amber = Color(0xFFFFB300);

  @override
  String get id => 'ai_super_hack';

  @override
  String get displayName => 'AI Super Hack';

  @override
  String get description =>
      'Neon-soaked cyberpunk. Scanlines, glow, monospace — for the night shift.';

  @override
  Brightness get brightness => Brightness.dark;

  @override
  ThemeDecorations get decorations => ThemeDecorations(
        useScanlines: true,
        useGlitchTitles: true,
        animatedGradientAppBar: true,
        glowColor: neonGreen,
        monoFontFamily: 'Courier',
        caretColor: hotPink,
      );

  @override
  ThemeData buildTheme() {
    final base = ColorScheme.fromSeed(
      seedColor: neonGreen,
      brightness: Brightness.dark,
    );

    final scheme = base.copyWith(
      surface: _bg,
      onSurface: neonGreen,
      surfaceContainerLowest: _bg,
      surfaceContainerLow: _bgRaised,
      surfaceContainer: _bgRaised,
      surfaceContainerHigh: _bgRaised2,
      surfaceContainerHighest: _bgRaised3,
      primary: neonGreen,
      onPrimary: _bg,
      secondary: hotPink,
      onSecondary: _bg,
      tertiary: cyan,
      onTertiary: _bg,
      error: magenta,
      onError: _bg,
      outline: neonGreen.withValues(alpha: 0.4),
      outlineVariant: hotPink.withValues(alpha: 0.3),
    );

    // Why we don't roll our own TextTheme:
    //
    // Hand-built TextStyles default to `inherit: true`, while Material's
    // textTheme entries are `inherit: false`. AnimatedTheme.lerp refuses to
    // interpolate two TextStyles whose `inherit` values disagree and throws
    // "Failed to interpolate TextStyles with different inherit values" every
    // frame during a theme switch — which then cascades into null-check
    // failures inside _InputDecoratorState and ListTile, since they end up
    // reading partially-broken styles from the in-flight theme.
    //
    // Building the textTheme by `.apply()`-ing on the framework default
    // preserves each entry's `inherit` flag, so lerping back and forth
    // between this theme and any other Material theme stays well-typed.
    final baseTheme =
        ThemeData(useMaterial3: true, brightness: Brightness.dark, colorScheme: scheme);
    final monoBase = baseTheme.textTheme.apply(
      fontFamily: 'Courier',
      fontFamilyFallback: const ['Menlo', 'Monaco', 'Consolas', 'monospace'],
      displayColor: neonGreen,
      bodyColor: const Color(0xFFA0FFA0),
    );

    final textTheme = monoBase.copyWith(
      displayLarge: monoBase.displayLarge?.copyWith(
          color: neonGreen, fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 0.4),
      displayMedium: monoBase.displayMedium?.copyWith(
          color: neonGreen, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 0.4),
      displaySmall: monoBase.displaySmall?.copyWith(
          color: neonGreen, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 0.4),
      headlineLarge: monoBase.headlineLarge?.copyWith(
          color: neonGreen, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 0.4),
      headlineMedium: monoBase.headlineMedium?.copyWith(
          color: neonGreen, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.4),
      headlineSmall: monoBase.headlineSmall?.copyWith(
          color: cyan, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.4),
      titleLarge: monoBase.titleLarge?.copyWith(
          color: neonGreen, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.4),
      titleMedium: monoBase.titleMedium?.copyWith(
          color: cyan, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.4),
      titleSmall: monoBase.titleSmall?.copyWith(
          color: hotPink, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.4),
      bodyLarge: monoBase.bodyLarge
          ?.copyWith(color: const Color(0xFFC8FFC8), fontSize: 15, letterSpacing: 0.4),
      bodyMedium: monoBase.bodyMedium
          ?.copyWith(color: const Color(0xFFA0FFA0), fontSize: 14, letterSpacing: 0.4),
      bodySmall: monoBase.bodySmall
          ?.copyWith(color: const Color(0xFF88DD88), fontSize: 12, letterSpacing: 0.4),
      labelLarge: monoBase.labelLarge?.copyWith(
          color: neonGreen, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.4),
      labelMedium: monoBase.labelMedium?.copyWith(
          color: cyan, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4),
      labelSmall: monoBase.labelSmall?.copyWith(
          color: hotPink, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4),
    );

    return baseTheme.copyWith(
      scaffoldBackgroundColor: _bg,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: _bg,
        foregroundColor: neonGreen,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: neonGreen,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          shadows: [
            Shadow(color: hotPink.withValues(alpha: 0.6), offset: const Offset(1, 0), blurRadius: 0),
            Shadow(color: cyan.withValues(alpha: 0.5), offset: const Offset(-1, 0), blurRadius: 0),
            Shadow(color: neonGreen.withValues(alpha: 0.8), blurRadius: 12),
          ],
        ),
        iconTheme: const IconThemeData(color: neonGreen),
      ),
      cardTheme: CardThemeData(
        color: _bgRaised,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(color: neonGreen.withValues(alpha: 0.4), width: 1),
        ),
        shadowColor: neonGreen,
      ),
      dividerTheme: DividerThemeData(
        color: neonGreen.withValues(alpha: 0.25),
        thickness: 1,
      ),
      iconTheme: const IconThemeData(color: neonGreen),
      // Set ListTile defaults explicitly so Material's default style
      // resolution can't dereference a null on a partially-themed frame.
      listTileTheme: ListTileThemeData(
        iconColor: neonGreen,
        textColor: neonGreen,
        titleTextStyle: textTheme.bodyLarge?.copyWith(color: neonGreen),
        subtitleTextStyle:
            textTheme.bodySmall?.copyWith(color: const Color(0xFFA0FFA0)),
        leadingAndTrailingTextStyle: textTheme.bodyMedium?.copyWith(color: cyan),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _bgRaised,
        hintStyle: textTheme.bodyMedium
            ?.copyWith(color: neonGreen.withValues(alpha: 0.4)),
        labelStyle: textTheme.bodyMedium?.copyWith(color: cyan),
        helperStyle:
            textTheme.bodySmall?.copyWith(color: cyan.withValues(alpha: 0.7)),
        errorStyle: textTheme.bodySmall?.copyWith(color: magenta),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: BorderSide(color: neonGreen.withValues(alpha: 0.4), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: BorderSide(color: neonGreen.withValues(alpha: 0.4), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: const BorderSide(color: hotPink, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: const BorderSide(color: magenta, width: 1.5),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: hotPink,
        selectionColor: neonGreen.withValues(alpha: 0.3),
        selectionHandleColor: neonGreen,
      ),
      // Don't set `textStyle` on button themes — buttons pick up
      // TextTheme.labelLarge automatically, and overriding it here would
      // re-introduce a TextStyle.lerp inherit mismatch during press/hover
      // transitions.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: neonGreen,
          foregroundColor: _bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          shadowColor: neonGreen,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cyan,
          side: BorderSide(color: cyan.withValues(alpha: 0.6)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: hotPink,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: hotPink,
        foregroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? neonGreen : hotPink),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            (s.contains(WidgetState.selected) ? neonGreen : hotPink)
                .withValues(alpha: 0.3)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: neonGreen,
        linearTrackColor: neonGreen.withValues(alpha: 0.2),
        circularTrackColor: hotPink.withValues(alpha: 0.2),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _bgRaised,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: neonGreen),
        actionTextColor: hotPink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(color: hotPink.withValues(alpha: 0.5), width: 1),
        ),
      ),
    );
  }
}
