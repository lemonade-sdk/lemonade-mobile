import 'app_theme_def.dart';
import 'nexus_dark_theme.dart';
import 'nexus_light_theme.dart';

/// Static registry of available themes. The redesign ships exactly two — the
/// Nexus dark-navy surface and its light variant; the header toggle flips
/// between them. (Legacy themes were removed.)
class ThemeRegistry {
  static final List<AppThemeDef> _themes = [
    NexusDarkTheme(),
    NexusLightTheme(),
  ];

  static List<AppThemeDef> get all => List.unmodifiable(_themes);

  static AppThemeDef byId(String id) {
    return _themes.firstWhere(
      (t) => t.id == id,
      // Any stale/legacy persisted id (e.g. 'dark', 'ai_super_hack') falls
      // back to the Nexus dark default.
      orElse: () => _themes.firstWhere((t) => t.id == defaultId),
    );
  }

  static const String defaultId = 'nexus_dark';
  static const String nexusDarkId = 'nexus_dark';
  static const String nexusLightId = 'nexus_light';
}
