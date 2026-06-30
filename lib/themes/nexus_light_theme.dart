import 'package:flutter/material.dart';

import 'app_theme_def.dart';
import 'nexus_theme_builder.dart';
import 'nexus_tokens.dart';

/// Light variant of the Nexus design, reached via the header theme toggle.
class NexusLightTheme extends AppThemeDef {
  @override
  String get id => 'nexus_light';

  @override
  String get displayName => 'Nexus Light';

  @override
  String get description => 'Cool off-white with the same blue accents.';

  @override
  Brightness get brightness => Brightness.light;

  @override
  ThemeData buildTheme() =>
      buildNexusTheme(NexusTokens.light, Brightness.light);
}
