import 'package:isar_community/isar.dart';

part 'app_prefs_entity.g.dart';

/// Singleton — only one row, [id] always 0.
@collection
class AppPrefsEntity {
  Id id = 0;

  /// Theme registry id: 'light' | 'medium' | 'dark' | 'ai_super_hack'
  String themeId = 'dark';

  /// Persisted UI selections.
  String? selectedServerName;
  String? selectedModelId;

  /// OmniRouter mode toggle. When true, the agent loop drives multimodal tool calls;
  /// when false, the app shows manual fallbacks for image/audio/etc.
  bool omniRouterEnabled = true;

  /// Reveals the Admin Console in the drawer.
  bool adminModeEnabled = false;

  /// Tracks whether the one-time SharedPreferences→Isar migration has run.
  bool legacyMigrationCompleted = false;

  int schemaVersion = 1;
}
