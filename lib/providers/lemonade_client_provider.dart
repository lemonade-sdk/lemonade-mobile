import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/lemonade_client.dart';
import 'servers_provider.dart';

/// One [LemonadeApiClient] per active server. Auto-disposed on server change.
final lemonadeClientProvider = Provider<LemonadeApiClient?>((ref) {
  final server = ref.watch(selectedServerProvider);
  if (server == null) return null;
  final client = LemonadeApiClient(server);
  ref.onDispose(client.close);
  return client;
});
