import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/models/discovered_server.dart';
import 'package:lemonade_mobile/services/beacon_listener_service.dart';

final beaconServiceProvider = Provider<BeaconListenerService>((ref) {
  final service = BeaconListenerService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Holds the most recent newly-discovered server for notification display.
/// Set to null after the notification is shown.
final pendingBeaconNotificationProvider =
    StateProvider<DiscoveredServer?>((ref) => null);

final discoveredServersProvider =
    StateNotifierProvider<DiscoveredServersNotifier, List<DiscoveredServer>>(
  (ref) => DiscoveredServersNotifier(ref),
);

class DiscoveredServersNotifier extends StateNotifier<List<DiscoveredServer>> {
  static const _expirationSeconds = 15;

  final Ref ref;
  StreamSubscription? _subscription;
  Timer? _cleanupTimer;

  // Notification dedup is per-hostname. A multi-NIC server broadcasts from
  // every interface, so the same hostname arrives with several different
  // source IPs — each is its own list entry (the user can pick which network
  // path to connect over), but only the first one fires a banner. We never
  // re-notify for a hostname during the session, even if it briefly drops off
  // and returns. App restart clears the set, which is the right behavior.
  final Set<String> _notifiedHostnames = {};

  DiscoveredServersNotifier(this.ref) : super([]) {
    _startListening();
  }

  Future<void> _startListening() async {
    final service = ref.read(beaconServiceProvider);

    try {
      await service.startListening();

      _subscription = service.onServerDiscovered.listen(
        (server) {
          _handleDiscoveredServer(server);
        },
        onError: (e) {
          // Don't let errors kill the subscription
        },
        cancelOnError: false,
      );

      _cleanupTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _removeExpiredServers(),
      );
    } catch (_) {
      // Failed to start listening (permission denied, port conflict, etc.)
    }
  }

  void _handleDiscoveredServer(DiscoveredServer server) {
    // Match by hostname AND url so the same hostname at a different IP shows
    // up as its own list entry (the user can pick which network path to use).
    final existingIndex = state.indexWhere(
      (s) => s.hostname == server.hostname && s.url == server.url,
    );

    if (existingIndex >= 0) {
      // Same hostname + url: just refresh lastSeen, no notification.
      state = [
        ...state.sublist(0, existingIndex),
        server,
        ...state.sublist(existingIndex + 1),
      ];
      return;
    }

    state = [...state, server];

    // One banner per hostname per session, normalised so `foo`, `Foo`, and
    // `foo.local` all collapse to the same key. Subsequent IPs for the same
    // host (multi-NIC, VPN + LAN, IP renewal) appear in the discovered list
    // but don't pop another notification.
    final key = server.hostnameKey;
    if (_notifiedHostnames.add(key)) {
      ref.read(pendingBeaconNotificationProvider.notifier).state = server;
    }
  }

  void _removeExpiredServers() {
    final now = DateTime.now();
    final newState = state.where((server) {
      return now.difference(server.lastSeen).inSeconds < _expirationSeconds;
    }).toList();

    if (newState.length != state.length) {
      state = newState;
    }
    // _notifiedHostnames is intentionally not cleared here — expiring a
    // server from the visible list shouldn't re-arm the banner for that
    // hostname.
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _cleanupTimer?.cancel();
    super.dispose();
  }
}