import 'package:flutter/material.dart';

import 'app_theme_def.dart';
import 'nexus_theme_builder.dart';
import 'nexus_tokens.dart';

/// "Nexus AI Mobile" — the committed dark-navy design language. This is the
/// app's default theme after the redesign.
class NexusDarkTheme extends AppThemeDef {
  @override
  String get id => 'nexus_dark';

  @override
  String get displayName => 'Nexus Dark';

  @override
  String get description => 'Deep navy with electric-blue accents.';

  @override
  Brightness get brightness => Brightness.dark;

  @override
  ThemeData buildTheme() => buildNexusTheme(NexusTokens.dark, Brightness.dark);
}
