import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/nexus/nexus_agents_client.dart';
import '../api/nexus/nexus_billing_client.dart';
import '../api/nexus/nexus_call_tasks_client.dart';
import '../api/nexus/nexus_gateway_base.dart';
import '../api/nexus/nexus_knowledge_client.dart';
import '../api/nexus/nexus_voice_client.dart';
import 'account_provider.dart';

// Each client watches ONLY the token (via select), not the whole AuthState.
// Watching the full state meant any unrelated mutation — a `busy` flip, a
// profile refresh — rebuilt the provider and `close()`d the old client while
// requests/uploads were still in flight ("Client is already closed"). With
// select, dispose fires only when the token actually changes.

/// Build a token-bound gateway client provider. All five feature clients share
/// this lifecycle; only the constructor differs.
Provider<T?> _tokenClientProvider<T extends NexusGatewayClient>(
  T Function(String token) create,
) {
  return Provider<T?>((ref) {
    final token = ref.watch(authProvider.select((a) => a.token));
    if (token == null || token.isEmpty) return null;
    final client = create(token);
    ref.onDispose(client.close);
    return client;
  });
}

/// The Voice client bound to the signed-in account token, or null when signed
/// out. Voice/PBX features are gateway-only (Subscription mode).
final nexusVoiceClientProvider =
    _tokenClientProvider((t) => NexusVoiceClient(token: t));

/// The Knowledge/RAG client bound to the signed-in account token, or null.
final nexusKnowledgeClientProvider =
    _tokenClientProvider((t) => NexusKnowledgeClient(token: t));

/// The AI Call Tasks client bound to the signed-in account token, or null.
final nexusCallTasksClientProvider =
    _tokenClientProvider((t) => NexusCallTasksClient(token: t));

/// Client for AI agent profiles / HTTP tools / agent knowledge pages, or null.
final nexusAgentsClientProvider =
    _tokenClientProvider((t) => NexusAgentsClient(token: t));

/// Client for billing & entitlements (capabilities, wallet, memberships), or null.
final nexusBillingClientProvider =
    _tokenClientProvider((t) => NexusBillingClient(token: t));
