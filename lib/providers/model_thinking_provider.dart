import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/thinking_level.dart';

/// Saved reasoning depth keyed by the runnable model id.
///
/// Missing entries deliberately mean Off. Keeping Off implicit also makes
/// upgrades safe: installing a new reasoning model never silently enables a
/// slower or more expensive mode.
final modelThinkingLevelsProvider =
    StateNotifierProvider<
      ModelThinkingLevelsNotifier,
      Map<String, ThinkingLevel>
    >((ref) => ModelThinkingLevelsNotifier());

class ModelThinkingLevelsNotifier
    extends StateNotifier<Map<String, ThinkingLevel>> {
  static const _prefsKey = 'nexus.model_thinking_levels';

  ModelThinkingLevelsNotifier() : super(const {}) {
    _load();
  }

  bool _userDirty = false;
  Future<void> _pendingSave = Future.value();

  ThinkingLevel levelFor(String modelId) => state[modelId] ?? ThinkingLevel.off;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty || _userDirty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final loaded = <String, ThinkingLevel>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! String) continue;
        final level = ThinkingLevelX.fromWire(entry.value as String);
        // Off is the implicit default; don't retain redundant entries.
        if (level != ThinkingLevel.off) loaded[entry.key as String] = level;
      }
      if (!_userDirty) state = Map.unmodifiable(loaded);
    } catch (_) {
      // Corrupt or unavailable preferences fall back safely to Off.
    }
  }

  Future<void> setLevel(String modelId, ThinkingLevel level) async {
    final next = Map<String, ThinkingLevel>.of(state);
    if (level == ThinkingLevel.off) {
      next.remove(modelId);
    } else {
      next[modelId] = level;
    }
    state = Map.unmodifiable(next);
    _userDirty = true;

    final snapshot = state;
    final save = _pendingSave.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({for (final e in snapshot.entries) e.key: e.value.wire}),
      );
    });
    _pendingSave = save.catchError((_) {});
    await save;
  }
}
