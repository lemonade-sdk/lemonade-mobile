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
  final Set<String> _notifiedUrls = {};

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
    final existingIndex = state.indexWhere((s) => s.url == server.url);

    if (existingIndex >= 0) {
      // Update lastSeen timestamp
      state = [
        ...state.sublist(0, existingIndex),
        server,
        ...state.sublist(existingIndex + 1),
      ];
    } else {
      // Brand new server discovered
      state = [...state, server];

      if (!_notifiedUrls.contains(server.url)) {
        _notifiedUrls.add(server.url);
        ref.read(pendingBeaconNotificationProvider.notifier).state = server;
      }
    }
  }

  void _removeExpiredServers() {
    final now = DateTime.now();
    final newState = state.where((server) {
      return now.difference(server.lastSeen).inSeconds < _expirationSeconds;
    }).toList();

    // Allow re-notification for servers that expire and come back
    final removedUrls = state
        .where((s) => !newState.contains(s))
        .map((s) => s.url)
        .toSet();
    _notifiedUrls.removeAll(removedUrls);

    if (newState.length != state.length) {
      state = newState;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _cleanupTimer?.cancel();
    super.dispose();
  }
}