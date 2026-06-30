import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/nexus/nexus_knowledge_models.dart';
import 'nexus_gateway_provider.dart';

/// KB collections (Docs tab). Empty when signed out.
final kbCollectionsProvider =
    FutureProvider.autoDispose<List<NexusCollection>>((ref) async {
  final client = ref.watch(nexusKnowledgeClientProvider);
  if (client == null) return const [];
  return client.listCollections();
});

/// The collection currently selected in the Docs tab (by id). Null = first.
final selectedCollectionIdProvider = StateProvider<int?>((ref) => null);

/// Documents in the selected collection.
final kbDocumentsProvider =
    FutureProvider.autoDispose<List<NexusDocument>>((ref) async {
  final client = ref.watch(nexusKnowledgeClientProvider);
  if (client == null) return const [];
  final collections = await ref.watch(kbCollectionsProvider.future);
  if (collections.isEmpty) return const [];
  final selectedId = ref.watch(selectedCollectionIdProvider);
  final collection = collections.firstWhere(
    (c) => c.id == selectedId,
    orElse: () => collections.first,
  );
  return client.listDocuments(collection.id);
});

/// The live Docs search query.
final kbQueryTextProvider = StateProvider<String>((ref) => '');

/// Hybrid search results for the current query against the selected collection.
final kbSearchProvider =
    FutureProvider.autoDispose<List<NexusKnowledgeHit>>((ref) async {
  final query = ref.watch(kbQueryTextProvider).trim();
  if (query.isEmpty) return const [];
  final client = ref.watch(nexusKnowledgeClientProvider);
  if (client == null) return const [];
  final collections = await ref.watch(kbCollectionsProvider.future);
  if (collections.isEmpty) return const [];
  final selectedId = ref.watch(selectedCollectionIdProvider);
  final collection = collections.firstWhere(
    (c) => c.id == selectedId,
    orElse: () => collections.first,
  );
  return client.query(collection.id, query, topK: 8);
});
