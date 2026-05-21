import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/database.dart';
import '../themes/app_theme_def.dart';
import '../themes/theme_registry.dart';

class _ThemeNotifier extends StateNotifier<AppThemeDef> {
  _ThemeNotifier(super.initial);

  Future<void> setThemeId(String id) async {
    final theme = ThemeRegistry.byId(id);
    state = theme;
    if (!AppDatabase.isOpen) return;
    final db = AppDatabase.instance;
    final prefs = await db.readOrCreatePrefs();
    prefs.themeId = id;
    await db.isar.writeTxn(() async => db.appPrefs.put(prefs));
  }
}

/// Override `initialThemeIdProvider` (in main.dart) before runApp to seed the
/// initial theme synchronously and avoid a first-frame theme swap.
final initialThemeIdProviderRef = Provider<String>((_) => ThemeRegistry.defaultId);

final themeProvider = StateNotifierProvider<_ThemeNotifier, AppThemeDef>((ref) {
  // Read the seed value from main.dart's override.
  // Falls back to the registry default for tests / cases without an override.
  final id = ref.watch(initialThemeIdProviderRef);
  return _ThemeNotifier(ThemeRegistry.byId(id));
});

/// Convenience selector — returns just the [ThemeDecorations] of the active theme.
final themeDecorationsProvider = Provider<ThemeDecorations>(
  (ref) => ref.watch(themeProvider).decorations,
);
