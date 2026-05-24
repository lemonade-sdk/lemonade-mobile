import 'package:isar_community/isar.dart';

part 'message_entity.g.dart';

@collection
class MessageEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uuid;

  /// FK to [ChatHistoryEntity.uuid].
  @Index(composite: [CompositeIndex('sortIndex')])
  late String chatUuid;

  /// 'system' | 'user' | 'assistant' | 'tool'
  late String role;

  /// Plain text content. Null when message is purely tool_calls or has parts attached.
  String? content;

  /// Multi-modal content parts (text/image_url/input_audio) as JSON.
  /// When present, [content] is typically null.
  String? contentPartsJson;

  /// For role='tool' messages.
  String? toolCallId;

  /// JSON list of ToolCall wire shapes (assistant messages with tool_calls).
  String? toolCallsJson;

  /// FKs into [AttachmentEntity.uuid]. Stored as a list rather than a relation
  /// for simpler ordering and faster reads.
  List<String> attachmentUuids = const [];

  late DateTime createdAt;

  /// Stable ordering within a chat. We use the message's monotonically increasing
  /// creation epoch-millis to avoid colliding with concurrent writes.
  late int sortIndex;

  int schemaVersion = 1;
}
