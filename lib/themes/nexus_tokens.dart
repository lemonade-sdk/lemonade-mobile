import 'package:flutter/material.dart';

/// Design tokens for the "Nexus AI Mobile" redesign — the CSS-variable palette
/// from the imported Claude Design, expressed as a Material [ThemeExtension] so
/// any widget can read them via `Theme.of(context).extension<NexusTokens>()!`
/// (or the [NexusTokensX.nexus] shortcut).
///
/// These intentionally live OUTSIDE the Material [ColorScheme]: the design uses
/// a bespoke set of layered surfaces, line strokes, and semantic status colors
/// that don't map cleanly onto Material's roles.
@immutable
class NexusTokens extends ThemeExtension<NexusTokens> {
  /// Base canvas (`--bg`).
  final Color bg;

  /// Slightly raised chrome bands — header / bottom nav (`--bg2`).
  final Color bg2;

  /// Card / control surface (`--surface`).
  final Color surface;

  /// Inset / pressed surface, avatar tiles (`--surface2`).
  final Color surface2;

  /// Hairline divider (`--line`).
  final Color line;

  /// Stronger control border (`--line2`).
  final Color line2;

  /// Primary text (`--text`).
  final Color text;

  /// Secondary text (`--muted`).
  final Color muted;

  /// Tertiary / metadata text (`--faint`).
  final Color faint;

  /// Brand accent (`--accent`).
  final Color accent;

  /// Lighter accent for icons / links (`--accent2`).
  final Color accent2;

  /// Translucent accent wash for chips / soft fills (`--accentSoft`).
  final Color accentSoft;

  /// Success / online (`--good`).
  final Color good;

  /// Warning (`--warn`).
  final Color warn;

  /// Live / recording pulse (`--live`).
  final Color live;

  /// Destructive (`--danger`).
  final Color danger;

  const NexusTokens({
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.line2,
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accent2,
    required this.accentSoft,
    required this.good,
    required this.warn,
    required this.live,
    required this.danger,
  });

  /// The committed dark-navy default from the design.
  static const NexusTokens dark = NexusTokens(
    bg: Color(0xFF070B16),
    bg2: Color(0xFF0C1326),
    surface: Color(0xFF111A33),
    surface2: Color(0xFF18233F),
    line: Color(0x1F96AADC), // rgba(150,170,220,0.12)
    line2: Color(0x3396AADC), // rgba(150,170,220,0.20)
    text: Color(0xFFEAF0FB),
    muted: Color(0xFF93A0C0),
    faint: Color(0xFF5D6A8C),
    accent: Color(0xFF4D7CFF),
    accent2: Color(0xFF6F9BFF),
    accentSoft: Color(0x294D7CFF), // rgba(77,124,255,0.16)
    good: Color(0xFF34D399),
    warn: Color(0xFFF4B740),
    live: Color(0xFFFF5A52),
    danger: Color(0xFFFF6B5E),
  );

  /// Light variant — reachable via the header theme toggle. Keeps the same
  /// accents but flips the canvas to a cool off-white with ink text.
  static const NexusTokens light = NexusTokens(
    bg: Color(0xFFF4F6FC),
    bg2: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEDF1FA),
    line: Color(0x14223055), // subtle slate hairline
    line2: Color(0x24223055),
    text: Color(0xFF101728),
    muted: Color(0xFF55617F),
    faint: Color(0xFF8B96B0),
    accent: Color(0xFF3F6BF5),
    accent2: Color(0xFF2F5BE0),
    accentSoft: Color(0x1A3F6BF5),
    good: Color(0xFF1FA971),
    warn: Color(0xFFC98A12),
    live: Color(0xFFE5483F),
    danger: Color(0xFFD9483C),
  );

  @override
  NexusTokens copyWith({
    Color? bg,
    Color? bg2,
    Color? surface,
    Color? surface2,
    Color? line,
    Color? line2,
    Color? text,
    Color? muted,
    Color? faint,
    Color? accent,
    Color? accent2,
    Color? accentSoft,
    Color? good,
    Color? warn,
    Color? live,
    Color? danger,
  }) {
    return NexusTokens(
      bg: bg ?? this.bg,
      bg2: bg2 ?? this.bg2,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      line: line ?? this.line,
      line2: line2 ?? this.line2,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      faint: faint ?? this.faint,
      accent: accent ?? this.accent,
      accent2: accent2 ?? this.accent2,
      accentSoft: accentSoft ?? this.accentSoft,
      good: good ?? this.good,
      warn: warn ?? this.warn,
      live: live ?? this.live,
      danger: danger ?? this.danger,
    );
  }

  @override
  NexusTokens lerp(ThemeExtension<NexusTokens>? other, double t) {
    if (other is! NexusTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return NexusTokens(
      bg: c(bg, other.bg),
      bg2: c(bg2, other.bg2),
      surface: c(surface, other.surface),
      surface2: c(surface2, other.surface2),
      line: c(line, other.line),
      line2: c(line2, other.line2),
      text: c(text, other.text),
      muted: c(muted, other.muted),
      faint: c(faint, other.faint),
      accent: c(accent, other.accent),
      accent2: c(accent2, other.accent2),
      accentSoft: c(accentSoft, other.accentSoft),
      good: c(good, other.good),
      warn: c(warn, other.warn),
      live: c(live, other.live),
      danger: c(danger, other.danger),
    );
  }
}

/// Ergonomic access: `context.nexus.accent`.
extension NexusTokensX on BuildContext {
  NexusTokens get nexus =>
      Theme.of(this).extension<NexusTokens>() ?? NexusTokens.dark;
}
