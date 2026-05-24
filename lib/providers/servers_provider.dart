import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../models/server_config.dart';
import '../storage/database.dart';
import '../storage/entities/server_config_entity.dart';
import '../storage/secure_storage.dart';

final serversProvider = StateNotifierProvider<ServersNotifier, List<ServerConfig>>(
  (ref) => ServersNotifier(),
);

final selectedServerProvider =
    StateNotifierProvider<SelectedServerNotifier, ServerConfig?>(
  (ref) => SelectedServerNotifier(ref),
);

class ServersNotifier extends StateNotifier<List<ServerConfig>> {
  ServersNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    if (!AppDatabase.isOpen) return;
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
  }

  Future<void> addServer(ServerConfig server) async {
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

    if (oldServer.name != newServer.name) {
      await SecureKeyStore.renameApiKey(oldServer.name, newServer.name);
    }
    if (hasKey) {
      await SecureKeyStore.writeApiKey(newServer.name, newServer.apiKey!);
    } else {
      await SecureKeyStore.deleteApiKey(newServer.name);
    }

    state = state.map((s) => s == oldServer ? newServer : s).toList();
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
}
