import 'app_theme_def.dart';
import 'ai_super_hack_theme.dart';
import 'dark_theme.dart';
import 'light_theme.dart';
import 'medium_theme.dart';

/// Static registry of available themes. Adding a new theme is a one-line
/// change here — drop a new [AppThemeDef] file under `lib/themes/` and append
/// it to [_themes].
class ThemeRegistry {
  static final List<AppThemeDef> _themes = [
    LightTheme(),
    MediumTheme(),
    DarkTheme(),
    AiSuperHackTheme(),
  ];

  static List<AppThemeDef> get all => List.unmodifiable(_themes);

  static AppThemeDef byId(String id) {
    return _themes.firstWhere(
      (t) => t.id == id,
      orElse: () => _themes.firstWhere((t) => t.id == 'dark'),
    );
  }

  static const String defaultId = 'dark';
}
