import 'package:isar_community/isar.dart';

part 'app_prefs_entity.g.dart';

/// Singleton — only one row, [id] always 0.
@collection
class AppPrefsEntity {
  Id id = 0;

  /// Theme registry id: 'nexus_dark' | 'nexus_light'. Fresh installs default to
  /// the redesign's dark-navy surface; any legacy id falls back to it.
  String themeId = 'nexus_dark';

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
