import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/nexus/nexus_agents_models.dart';
import 'account_provider.dart' show CacheForExtension;
import 'nexus_gateway_provider.dart';

/// AI agent profiles list.
final agentsProvider =
    FutureProvider.autoDispose<List<NexusAgentSummary>>((ref) async {
  ref.cacheFor(const Duration(minutes: 5));
  final client = ref.watch(nexusAgentsClientProvider);
  if (client == null) return const [];
  return client.listAgents();
});

/// Editor pickers (chat models, sms numbers, knowledge collections).
final agentOptionsProvider =
    FutureProvider.autoDispose<NexusAgentOptions>((ref) async {
  ref.cacheFor(const Duration(minutes: 5));
  final client = ref.watch(nexusAgentsClientProvider);
  if (client == null) return const NexusAgentOptions();
  return client.agentOptions();
});

/// Custom HTTP tools list.
final httpToolsProvider =
    FutureProvider.autoDispose<List<NexusHttpToolSummary>>((ref) async {
  ref.cacheFor(const Duration(minutes: 5));
  final client = ref.watch(nexusAgentsClientProvider);
  if (client == null) return const [];
  return client.listTools();
});

/// Agent knowledge pages list.
final knowledgePagesProvider =
    FutureProvider.autoDispose<List<NexusKnowledgePageSummary>>((ref) async {
  ref.cacheFor(const Duration(minutes: 5));
  final client = ref.watch(nexusAgentsClientProvider);
  if (client == null) return const [];
  return client.listPages();
});
