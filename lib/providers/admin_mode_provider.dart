import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/database.dart';

class _AdminModeNotifier extends StateNotifier<bool> {
  _AdminModeNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    if (!AppDatabase.isOpen) return;
    final prefs = await AppDatabase.instance.readOrCreatePrefs();
    state = prefs.adminModeEnabled;
  }

  Future<void> setEnabled(bool value) async {
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
