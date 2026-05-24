import 'package:isar_community/isar.dart';

part 'attachment_entity.g.dart';

@collection
class AttachmentEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uuid;

  /// FK to [MessageEntity.uuid] (nullable for orphaned/scratch attachments).
  @Index()
  String? messageUuid;

  /// 'image' | 'audio' | 'file'
  @enumerated
  late AttachmentKind kind;

  /// Absolute path (within the app sandbox) to the attachment blob on disk.
  late String filePath;

  late String mimeType;

  /// Hex-encoded SHA-256 of the file contents. Used for de-duplication.
  @Index()
  late String sha256;

  late int sizeBytes;

  /// For audio attachments.
  int? durationMs;

  late DateTime createdAt;

  int schemaVersion = 1;
}

enum AttachmentKind { image, audio, file }
