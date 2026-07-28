/// DTOs for the Nexus gateway Knowledge / RAG API (`/api/v1/knowledge/*`).
/// Powers the redesign's Docs tab.
library;

import 'json_utils.dart';

DateTime? _date(dynamic v) => jsonDate(v);
int? _int(dynamic v) => jsonInt(v);
String _str(dynamic v) => jsonStr(v);

class NexusCollection {
  final int id;
  final String name;
  final String slug;
  final String? description;
  final DateTime? createdAt;

  const NexusCollection({
    required this.id,
    required this.name,
    this.slug = '',
    this.description,
    this.createdAt,
  });

  factory NexusCollection.fromJson(Map<String, dynamic> j) => NexusCollection(
        id: _int(j['id']) ?? 0,
        name: _str(j['name']),
        slug: _str(j['slug']),
        description: j['description']?.toString(),
        createdAt: _date(j['createdAt']),
      );
}

/// Indexing status for a document (`KnowledgeDocument.Status`).
enum DocStatus { pending, embedded, keywordOnly, noText, failed, unknown }

DocStatus _docStatus(dynamic v) {
  switch (_str(v).toLowerCase()) {
    case 'pending':
      return DocStatus.pending;
    case 'embedded':
      return DocStatus.embedded;
    case 'keywordonly':
      return DocStatus.keywordOnly;
    case 'notext':
      return DocStatus.noText;
    case 'failed':
      return DocStatus.failed;
    default:
      return DocStatus.unknown;
  }
}

/// A document in a collection (`DocumentDto`).
class NexusDocument {
  final int id;
  final int collectionId;
  final String title;
  final String? sourceType;
  final String? originalFilename;
  final int byteSize;
  final DocStatus status;
  final int chunkCount;
  final String? embeddingModel;
  final String? statusDetail;
  final DateTime? createdAt;

  const NexusDocument({
    required this.id,
    required this.collectionId,
    required this.title,
    this.sourceType,
    this.originalFilename,
    this.byteSize = 0,
    this.status = DocStatus.unknown,
    this.chunkCount = 0,
    this.embeddingModel,
    this.statusDetail,
    this.createdAt,
  });

  factory NexusDocument.fromJson(Map<String, dynamic> j) => NexusDocument(
        id: _int(j['id']) ?? 0,
        collectionId: _int(j['collectionId']) ?? 0,
        title: _str(j['title']),
        sourceType: j['sourceType']?.toString(),
        originalFilename: j['originalFilename']?.toString(),
        byteSize: _int(j['byteSize']) ?? 0,
        status: _docStatus(j['status']),
        chunkCount: _int(j['chunkCount']) ?? 0,
        embeddingModel: j['embeddingModel']?.toString(),
        statusDetail: j['statusDetail']?.toString(),
        createdAt: _date(j['createdAt']),
      );
}

/// One search hit (`KnowledgeHit`).
class NexusKnowledgeHit {
  final int collectionId;
  final int? documentId;
  final String pageId;
  final String title;
  final String text;
  final double score;

  const NexusKnowledgeHit({
    required this.collectionId,
    this.documentId,
    this.pageId = '',
    this.title = '',
    this.text = '',
    this.score = 0,
  });

  factory NexusKnowledgeHit.fromJson(Map<String, dynamic> j) =>
      NexusKnowledgeHit(
        collectionId: _int(j['collectionId']) ?? 0,
        documentId: _int(j['documentId']),
        pageId: _str(j['pageId']),
        title: _str(j['title']),
        text: _str(j['text']),
        score: (j['score'] is num) ? (j['score'] as num).toDouble() : 0,
      );
}
