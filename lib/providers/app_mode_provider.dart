import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/nexus/nexus_account_client.dart' show kNexusGatewayBaseUrl;
import 'nav_provider.dart';
import 'servers_provider.dart';

/// Where inference runs — the three header modes from the design.
///
/// * [subscription] — routed cloud inference through the Nexus gateway
///   (`api.nexus-projects.ai`). Unlocks Calls / PBX / Docs (gateway features)
///   and shows the auth gate when signed out.
/// * [local] — a Lemonade server on the LAN / this device. Unlocks the on-device
///   Model Manager; gateway-only tabs show a "needs Subscription" empty state.
/// * [mesh] — agentic WireGuard mesh. UI / toggle only for now (no FFI yet).
enum AppMode { subscription, local, mesh }

extension AppModeX on AppMode {
  String get label => switch (this) {
        AppMode.subscription => 'Subscription',
        AppMode.local => 'Local AI',
        AppMode.mesh => 'Mesh',
      };

  String get wire => name;

  /// Local + Mesh both run against a Lemonade server the user controls, so they
  /// expose the on-device Model Manager.
  bool get showsModelManager => this != AppMode.subscription;

  /// Voice (Calls/PBX) and Knowledge (Docs) are gateway-only features.
  bool get hasGatewayFeatures => this == AppMode.subscription;
}

const _prefsKey = 'nexus.app_mode';

bool _isGateway(String baseUrl) => baseUrl.trim() == kNexusGatewayBaseUrl;

class _AppModeNotifier extends StateNotifier<AppMode> {
  final Ref ref;
  _AppModeNotifier(this.ref) : super(AppMode.subscription) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        state = AppMode.values.firstWhere(
          (m) => m.name == saved,
          orElse: () => AppMode.subscription,
        );
      }
    } catch (_) {
      // SharedPreferences unavailable — keep the default.
    }
  }

  Future<void> setMode(AppMode mode) async {
    state = mode;
    _selectServerForMode(mode);
    // Leaving Subscription disables the cloud tabs — bounce off them to Chat.
    if (mode != AppMode.subscription) {
      final tab = ref.read(navTabProvider);
      if (tab != NexusTab.chat && tab != NexusTab.settings) {
        ref.read(navTabProvider.notifier).state = NexusTab.chat;
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {}
  }

  /// Point the active server at the one that matches the mode: the managed
  /// gateway for Subscription, the first local (non-gateway) server otherwise.
  /// Without this, switching modes would leave the previous server selected —
  /// e.g. "Local AI" still talking to the subscription gateway.
  void _selectServerForMode(AppMode mode) {
    final servers = ref.read(serversProvider);
    if (servers.isEmpty) return;
    final selectedNotifier = ref.read(selectedServerProvider.notifier);
    final current = ref.read(selectedServerProvider);

    if (mode == AppMode.subscription) {
      final gw = servers.where((s) => _isGateway(s.baseUrl)).firstOrNull;
      if (gw != null && current?.name != gw.name) {
        selectedNotifier.selectServer(gw);
      }
    } else {
      // Local / Mesh → a server the user controls.
      if (current != null && !_isGateway(current.baseUrl)) return; // already local
      final local = servers.where((s) => !_isGateway(s.baseUrl)).firstOrNull;
      // If they only have the gateway, clear selection so the device/model
      // panels prompt to add a local server rather than show the gateway.
      selectedNotifier.selectServer(local);
    }
  }
}

/// Current inference mode, persisted across launches.
final appModeProvider =
    StateNotifierProvider<_AppModeNotifier, AppMode>((ref) => _AppModeNotifier(ref));
