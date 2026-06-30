import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'nexus_tokens.dart';

/// Shared [ThemeData] builder for both Nexus variants. Wires the design's
/// typography (Inter Tight for UI, IBM Plex Mono available via [nexusMono]) and
/// maps the [NexusTokens] palette onto Material's [ColorScheme] so stock widgets
/// (dialogs, snackbars, switches) inherit the look without bespoke styling.
ThemeData buildNexusTheme(NexusTokens t, Brightness brightness) {
  final base = ThemeData(brightness: brightness, useMaterial3: true);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: Colors.white,
    secondary: t.accent2,
    onSecondary: Colors.white,
    error: t.danger,
    onError: Colors.white,
    surface: t.surface,
    onSurface: t.text,
    surfaceContainerLowest: t.bg,
    surfaceContainerLow: t.bg2,
    surfaceContainer: t.surface,
    surfaceContainerHigh: t.surface2,
    surfaceContainerHighest: t.surface2,
    outline: t.line2,
    outlineVariant: t.line,
  );

  final textTheme = GoogleFonts.interTightTextTheme(base.textTheme).apply(
    bodyColor: t.text,
    displayColor: t.text,
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    textTheme: textTheme,
    primaryColor: t.accent,
    dividerColor: t.line,
    splashFactory: InkRipple.splashFactory,
    extensions: <ThemeExtension<dynamic>>[t],
    iconTheme: IconThemeData(color: t.muted),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg2,
      foregroundColor: t.text,
      elevation: 0,
      centerTitle: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.bg2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: t.muted),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.surface2,
      contentTextStyle: TextStyle(color: t.text),
      actionTextColor: t.accent2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.bg2,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : t.surface2,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      hintStyle: TextStyle(color: t.faint),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.line2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.line2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.accent),
      ),
    ),
  );
}

/// IBM Plex Mono text style for monospaced data (DIDs, timers, model ids).
TextStyle nexusMono({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? letterSpacing,
}) {
  return GoogleFonts.ibmPlexMono(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
  );
}
