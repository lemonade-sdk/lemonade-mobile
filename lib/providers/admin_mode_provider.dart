import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/database.dart';

class _AdminModeNotifier extends StateNotifier<bool> {
  _AdminModeNotifier() : super(false) {
    _load();
  }

  /// A toggle flipped before [_load] resolves must win over the stale
  /// snapshot it read (cold-start window).
  bool _userDirty = false;

  Future<void> _load() async {
    if (!AppDatabase.isOpen) return;
    final prefs = await AppDatabase.instance.readOrCreatePrefs();
    if (_userDirty) return;
    state = prefs.adminModeEnabled;
  }

  Future<void> setEnabled(bool value) async {
    _userDirty = true;
    state = value;
    if (!AppDatabase.isOpen) return;
    final db = AppDatabase.instance;
    final prefs = await db.readOrCreatePrefs();
    prefs.adminModeEnabled = value;
    await db.isar.writeTxn(() async => db.appPrefs.put(prefs));
  }
}

final adminModeProvider =
    StateNotifierProvider<_AdminModeNotifier, bool>((ref) => _AdminModeNotifier());
