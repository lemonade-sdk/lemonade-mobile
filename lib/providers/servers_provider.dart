import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../models/server_config.dart';
import '../storage/database.dart';
import '../storage/entities/server_config_entity.dart';
import '../storage/secure_storage.dart';

final serversProvider = StateNotifierProvider<ServersNotifier, List<ServerConfig>>(
  (ref) => ServersNotifier(ref),
);

final selectedServerProvider =
    StateNotifierProvider<SelectedServerNotifier, ServerConfig?>(
  (ref) => SelectedServerNotifier(ref),
);

class ServersNotifier extends StateNotifier<List<ServerConfig>> {
  final Ref ref;

  /// Completes once the initial Isar load has been applied to [state]. Every
  /// mutation awaits it, serializing them behind the load — otherwise a slow
  /// [_load] landing after an `addServer` clobbered the in-memory list and
  /// the just-added server vanished until restart.
  late final Future<void> _loaded;

  ServersNotifier(this.ref) : super([]) {
    _loaded = _load();
  }

  Future<void> _load() async {
    if (!AppDatabase.isOpen) return;
    try {
      final db = AppDatabase.instance;
      final rows = await db.serverConfigs.where().findAll();
      final configs = <ServerConfig>[];
      for (final row in rows) {
        String? apiKey;
        if (row.hasApiKey) {
          try {
            apiKey = await SecureKeyStore.readApiKey(row.name);
          } catch (_) {
            apiKey = null; // Keychain unavailable — proceed without auth.
          }
        }
        configs.add(ServerConfig(
          name: row.name,
          baseUrl: row.baseUrl,
          apiKey: apiKey,
        ));
      }
      state = configs;
    } catch (e) {
      // Never rethrow: [_loaded] must always complete or every mutation
      // awaiting it would hang forever.
      debugPrint('ServersNotifier: load failed: $e');
    }
  }

  Future<void> addServer(ServerConfig server) async {
    await _loaded;
    if (!AppDatabase.isOpen) return;
    final db = AppDatabase.instance;
    final hasKey = (server.apiKey ?? '').isNotEmpty;
    var keyPersisted = false;
    if (hasKey) {
      try {
        await SecureKeyStore.writeApiKey(server.name, server.apiKey!);
        keyPersisted = true;
      } catch (_) {
        // Keychain unavailable. The API key won't be saved across launches.
      }
    }
    final entity = ServerConfigEntity()
      ..name = server.name
      ..baseUrl = server.baseUrl
      ..hasApiKey = keyPersisted
      ..createdAt = DateTime.now();
    await db.isar.writeTxn(() async => db.serverConfigs.put(entity));
    state = [...state, server];
  }

  Future<void> removeServer(ServerConfig server) async {
    await _loaded;
    if (!AppDatabase.isOpen) return;
    final db = AppDatabase.instance;
    try {
      await db.isar.writeTxn(() async {
        await db.serverConfigs.filter().nameEqualTo(server.name).deleteFirst();
      });
    } catch (e) {
      debugPrint('removeServer: Isar delete failed: $e');
    }
    try {
      await SecureKeyStore.deleteApiKey(server.name);
    } catch (_) {
      // Keychain unavailable — ignore. The Isar row is already gone.
    }
    state = state.where((s) => s.name != server.name).toList(growable: false);
  }

  Future<void> updateServer(ServerConfig oldServer, ServerConfig newServer) async {
    await _loaded;
    if (!AppDatabase.isOpen) return;
    final db = AppDatabase.instance;
    final hasKey = (newServer.apiKey ?? '').isNotEmpty;

    await db.isar.writeTxn(() async {
      final existing =
          await db.serverConfigs.filter().nameEqualTo(oldServer.name).findFirst();
      if (existing != null) {
        existing
          ..name = newServer.name
          ..baseUrl = newServer.baseUrl
          ..hasApiKey = hasKey;
        await db.serverConfigs.put(existing);
      } else {
        await db.serverConfigs.put(ServerConfigEntity()
          ..name = newServer.name
          ..baseUrl = newServer.baseUrl
          ..hasApiKey = hasKey
          ..createdAt = DateTime.now());
      }
    });

    // Keychain writes are best-effort — the Isar row is already committed, so
    // a keychain error must not skip the state update / rename handling below.
    try {
      if (oldServer.name != newServer.name) {
        await SecureKeyStore.renameApiKey(oldServer.name, newServer.name);
      }
      if (hasKey) {
        await SecureKeyStore.writeApiKey(newServer.name, newServer.apiKey!);
      } else {
        await SecureKeyStore.deleteApiKey(newServer.name);
      }
    } catch (_) {
      // Keychain unavailable. The API key won't be saved across launches.
    }

    // A renamed *selected* server keeps its selection (the persisted name
    // follows the rename). Done BEFORE the list update below so the selection
    // listener re-resolves against the new name instead of dropping to null.
    if (oldServer.name != newServer.name) {
      await ref
          .read(selectedServerProvider.notifier)
          .handleServerRenamed(oldServer, newServer);
    }

    // Match by name (the row identity used everywhere else). Full-object
    // equality silently skipped the in-memory update when the copies differed
    // in a field the caller didn't know about (e.g. apiKey null in the loaded
    // list vs set on [oldServer]).
    state = [
      for (final s in state) s.name == oldServer.name ? newServer : s,
    ];
  }
}

class SelectedServerNotifier extends StateNotifier<ServerConfig?> {
  final Ref ref;
  String? _savedServerName;

  SelectedServerNotifier(this.ref) : super(null) {
    _loadSelected();
    ref.listen(serversProvider, (previous, next) {
      if (_savedServerName != null && next.isNotEmpty) {
        state = next.cast<ServerConfig?>().firstWhere(
              (server) => server?.name == _savedServerName,
              orElse: () => null,
            );
      }
    });
  }

  Future<void> _loadSelected() async {
    if (!AppDatabase.isOpen) return;
    final prefs = await AppDatabase.instance.readOrCreatePrefs();
    _savedServerName = prefs.selectedServerName;
    if (_savedServerName != null) {
      final servers = ref.read(serversProvider);
      if (servers.isNotEmpty) {
        state = servers.cast<ServerConfig?>().firstWhere(
              (server) => server?.name == _savedServerName,
              orElse: () => null,
            );
      }
    }
  }

  Future<void> _saveSelected() async {
    if (!AppDatabase.isOpen) return;
    final db = AppDatabase.instance;
    final prefs = await db.readOrCreatePrefs();
    prefs.selectedServerName = state?.name;
    await db.isar.writeTxn(() async => db.appPrefs.put(prefs));
  }

  Future<void> selectServer(ServerConfig? server) async {
    state = server;
    _savedServerName = server?.name;
    await _saveSelected();
  }

  /// Keep the selection (and its persisted name) attached to a server that
  /// was just renamed — renaming the selected server used to drop the
  /// selection until the user manually re-picked it.
  Future<void> handleServerRenamed(
      ServerConfig oldServer, ServerConfig newServer) async {
    if (_savedServerName != oldServer.name) return;
    _savedServerName = newServer.name;
    state = newServer;
    await _saveSelected();
  }
}
