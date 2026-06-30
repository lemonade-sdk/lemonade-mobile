import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/nexus/nexus_agents_client.dart';
import '../api/nexus/nexus_billing_client.dart';
import '../api/nexus/nexus_call_tasks_client.dart';
import '../api/nexus/nexus_knowledge_client.dart';
import '../api/nexus/nexus_voice_client.dart';
import 'account_provider.dart';

/// The Voice client bound to the signed-in account token, or null when signed
/// out. Voice/PBX features are gateway-only (Subscription mode).
final nexusVoiceClientProvider = Provider<NexusVoiceClient?>((ref) {
  final auth = ref.watch(authProvider);
  if (!auth.isSignedIn) return null;
  final client = NexusVoiceClient(token: auth.token!);
  ref.onDispose(client.close);
  return client;
});

/// The Knowledge/RAG client bound to the signed-in account token, or null.
final nexusKnowledgeClientProvider = Provider<NexusKnowledgeClient?>((ref) {
  final auth = ref.watch(authProvider);
  if (!auth.isSignedIn) return null;
  final client = NexusKnowledgeClient(token: auth.token!);
  ref.onDispose(client.close);
  return client;
});

/// The AI Call Tasks client bound to the signed-in account token, or null.
final nexusCallTasksClientProvider = Provider<NexusCallTasksClient?>((ref) {
  final auth = ref.watch(authProvider);
  if (!auth.isSignedIn) return null;
  final client = NexusCallTasksClient(token: auth.token!);
  ref.onDispose(client.close);
  return client;
});

/// Client for AI agent profiles / HTTP tools / agent knowledge pages, or null.
final nexusAgentsClientProvider = Provider<NexusAgentsClient?>((ref) {
  final auth = ref.watch(authProvider);
  if (!auth.isSignedIn) return null;
  final client = NexusAgentsClient(token: auth.token!);
  ref.onDispose(client.close);
  return client;
});

/// Client for billing & entitlements (capabilities, wallet, memberships), or null.
final nexusBillingClientProvider = Provider<NexusBillingClient?>((ref) {
  final auth = ref.watch(authProvider);
  if (!auth.isSignedIn) return null;
  final client = NexusBillingClient(token: auth.token!);
  ref.onDispose(client.close);
  return client;
});
