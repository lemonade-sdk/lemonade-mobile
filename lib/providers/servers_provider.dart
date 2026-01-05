import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_config.dart';

final serversProvider = StateNotifierProvider<ServersNotifier, List<ServerConfig>>(
  (ref) => ServersNotifier(),
);

final selectedServerProvider = StateNotifierProvider<SelectedServerNotifier, ServerConfig?>(
  (ref) => SelectedServerNotifier(ref),
);

class ServersNotifier extends StateNotifier<List<ServerConfig>> {
  static const String _serversKey = 'servers';
  ServersNotifier() : super([]) {
    _loadServers();
  }

  Future<void> _loadServers() async {
    final prefs = await SharedPreferences.getInstance();
    final serversJson = prefs.getStringList(_serversKey) ?? [];
    state = serversJson
        .map((json) => ServerConfig.fromJson(jsonDecode(json)))
        .toList();
  }

  Future<void> _saveServers() async {
    final prefs = await SharedPreferences.getInstance();
    final serversJson = state.map((server) => jsonEncode(server.toJson())).toList();
    await prefs.setStringList(_serversKey, serversJson);
  }

  Future<void> addServer(ServerConfig server) async {
    state = [...state, server];
    await _saveServers();
  }

  Future<void> removeServer(ServerConfig server) async {
    state = state.where((s) => s != server).toList();
    await _saveServers();
  }

  Future<void> updateServer(ServerConfig oldServer, ServerConfig newServer) async {
    state = state.map((s) => s == oldServer ? newServer : s).toList();
    await _saveServers();
  }
}

class SelectedServerNotifier extends StateNotifier<ServerConfig?> {
  static const String _selectedServerKey = 'selected_server_name';
  final Ref ref;
  String? _savedServerName;

  SelectedServerNotifier(this.ref) : super(null) {
    _loadSelectedServer();
    // Listen for server list changes to restore selection
    ref.listen(serversProvider, (previous, next) {
      if (_savedServerName != null && next.isNotEmpty) {
        state = next.cast<ServerConfig?>().firstWhere(
              (server) => server?.name == _savedServerName,
              orElse: () => null,
            );
      }
    });
  }

  Future<void> _loadSelectedServer() async {
    final prefs = await SharedPreferences.getInstance();
    _savedServerName = prefs.getString(_selectedServerKey);
    if (_savedServerName != null) {
      // Try to find the server immediately, or it will be found when servers load
      final servers = ref.read(serversProvider);
      if (servers.isNotEmpty) {
        state = servers.cast<ServerConfig?>().firstWhere(
              (server) => server?.name == _savedServerName,
              orElse: () => null,
            );
      }
    }
  }

  Future<void> _saveSelectedServer() async {
    final prefs = await SharedPreferences.getInstance();
    if (state != null) {
      await prefs.setString(_selectedServerKey, state!.name);
    } else {
      await prefs.remove(_selectedServerKey);
    }
  }

  Future<void> selectServer(ServerConfig? server) async {
    state = server;
    await _saveSelectedServer();
  }
}
