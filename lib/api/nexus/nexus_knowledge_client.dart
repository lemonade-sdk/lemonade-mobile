/// Client for the Nexus gateway Knowledge / RAG API (`/api/v1/knowledge/*`).
/// Powers the redesign's Docs tab: collections, PDF/text ingest, and hybrid
/// (keyword + semantic) search.
library;

import 'nexus_gateway_base.dart';
import 'nexus_knowledge_models.dart';

class NexusKnowledgeClient extends NexusGatewayClient {
  NexusKnowledgeClient({required super.token, super.client});

  Future<List<NexusCollection>> listCollections() async {
    final json = await getJson(uri('/knowledge/collections'));
    final list = (json['data'] as List?) ??
        (json['collections'] as List?) ??
        const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(NexusCollection.fromJson)
        .toList();
  }

  Future<NexusCollection> createCollection(String name,
      {String? slug, String? description}) async {
    final json = await postJson(uri('/knowledge/collections'), {
      'name': name,
      if (slug != null) 'slug': slug,
      if (description != null) 'description': description,
    });
    return NexusCollection.fromJson(json);
  }

  Future<List<NexusDocument>> listDocuments(int collectionId) async {
    final json =
        await getJson(uri('/knowledge/collections/$collectionId/documents'));
    final list = (json['data'] as List?) ??
        (json['documents'] as List?) ??
        const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(NexusDocument.fromJson)
        .toList();
  }

  /// POST /knowledge/collections/{id}/documents — multipart PDF/txt/md upload.
  Future<NexusDocument> uploadDocument({
    required int collectionId,
    required String filename,
    required List<int> bytes,
    String? title,
    String? mimeType,
  }) async {
    final json = await postMultipart(
      uri('/knowledge/collections/$collectionId/documents'),
      fileField: 'file',
      filename: filename,
      bytes: bytes,
      fields: {if (title != null) 'title': title},
    );
    return NexusDocument.fromJson(json);
  }

  Future<void> deleteDocument(int documentId) =>
      delete(uri('/knowledge/documents/$documentId'));

  /// POST /knowledge/collections/{id}/query — semantic / hybrid search.
  Future<List<NexusKnowledgeHit>> query(int collectionId, String text,
      {int? topK}) async {
    final json = await postJson(
        uri('/knowledge/collections/$collectionId/query'),
        {'query': text, if (topK != null) 'topK': topK});
    final results = (json['results'] as List?) ?? const [];
    return results
        .whereType<Map<String, dynamic>>()
        .map(NexusKnowledgeHit.fromJson)
        .toList();
  }
}
