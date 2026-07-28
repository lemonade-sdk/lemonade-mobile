import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/lemonade_client.dart';
import 'servers_provider.dart';

/// One [LemonadeApiClient] per active server. Auto-disposed on server change.
final lemonadeClientProvider = Provider<LemonadeApiClient?>((ref) {
  final server = ref.watch(selectedServerProvider);
  if (server == null) return null;
  final client = LemonadeApiClient(server);
  ref.onDispose(() {
    // Delay the close: closing immediately on server change kills any
    // still-running requests/SSE streams on the OLD client mid-flight (they
    // hold a reference to it, not to this provider). Two minutes comfortably
    // outlives the default request timeouts, after which the sockets are freed.
    Future.delayed(const Duration(minutes: 2), client.close);
  });
  return client;
});
