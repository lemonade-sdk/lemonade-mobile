import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';

import '../models/chat_history.dart';
import '../models/chat_message.dart';
import '../models/model_defaults.dart';
import 'database.dart';
import 'entities/attachment_entity.dart';
import 'entities/chat_history_entity.dart';
import 'entities/message_entity.dart';
import 'file_storage.dart';

/// Converts between Isar entities and the in-memory `ChatHistory` / `ChatMessage`
/// domain models the UI consumes. Owns all chat-related Isar reads and writes.
class ChatRepository {
  static AppDatabase get _db => AppDatabase.instance;

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  static Future<List<ChatHistory>> loadAll() async {
    if (!AppDatabase.isOpen) return const [];
    final chatRows = await _db.chats.where().sortByLastUpdatedDesc().findAll();
    final result = <ChatHistory>[];
    for (final chat in chatRows) {
      final messages = await _loadMessages(chat.uuid);
      result.add(ChatHistory(
        id: chat.uuid,
        title: chat.title ?? '',
        messages: messages,
        createdAt: chat.createdAt,
        lastUpdated: chat.lastUpdated,
        isActive: chat.isActive,
        modelOverrides: _decodeOverrides(chat.modelOverridesJson),
        folderId: chat.folderUuid,
      ));
    }
    return result;
  }

  static Future<List<ChatMessage>> _loadMessages(String chatUuid) async {
    final rows = await _db.messages
        .filter()
        .chatUuidEqualTo(chatUuid)
        .sortBySortIndex()
        .findAll();

    final attachmentsByMsg = <String, List<AttachmentEntity>>{};
    final attachmentUuids = <String>{
      for (final m in rows) ...m.attachmentUuids,
    };
    if (attachmentUuids.isNotEmpty) {
      final atts = await _db.attachments
          .filter()
          .anyOf(attachmentUuids, (q, uuid) => q.uuidEqualTo(uuid))
          .findAll();
      for (final a in atts) {
        if (a.messageUuid == null) continue;
        attachmentsByMsg.putIfAbsent(a.messageUuid!, () => []).add(a);
      }
    }

    final out = <ChatMessage>[];
    for (final m in rows) {
      final contents = <MessageContent>[];
      if (m.content != null && m.content!.isNotEmpty) {
        contents.add(MessageContent(type: MessageContentType.text, value: m.content!));
      }
      final atts = attachmentsByMsg[m.uuid] ?? const <AttachmentEntity>[];
      for (final a in atts) {
        final dataUrl = await _attachmentToDataUrl(a);
        if (dataUrl == null) continue;
        switch (a.kind) {
          case AttachmentKind.image:
            contents.add(MessageContent(type: MessageContentType.image, value: dataUrl));
          case AttachmentKind.audio:
            contents.add(MessageContent(type: MessageContentType.audio, value: dataUrl));
          case AttachmentKind.file:
            // Generic files aren't surfaced into ChatMessage today.
            break;
        }
      }
      out.add(ChatMessage(
        role: m.role == 'user' ? MessageRole.user : MessageRole.assistant,
        content: contents,
        timestamp: m.createdAt,
      ));
    }
    return out;
  }

  static Future<String?> _attachmentToDataUrl(AttachmentEntity a) async {
    final f = File(a.filePath);
    if (!await f.exists()) return null;
    final bytes = await f.readAsBytes();
    return 'data:${a.mimeType};base64,${base64Encode(bytes)}';
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  static Future<void> upsertChat(ChatHistory chat) async {
    if (!AppDatabase.isOpen) return;
    await _db.isar.writeTxn(() async {
      var existing = await _db.chats.filter().uuidEqualTo(chat.id).findFirst();
      existing ??= ChatHistoryEntity()
        ..uuid = chat.id
        ..createdAt = chat.createdAt;
      existing
        ..title = chat.title.isEmpty ? null : chat.title
        ..folderUuid = chat.folderId
        ..lastUpdated = chat.lastUpdated
        ..isActive = chat.isActive
        ..modelOverridesJson = chat.modelOverrides == null
            ? null
            : jsonEncode(chat.modelOverrides!.toJson());
      await _db.chats.put(existing);
    });
  }

  static Future<void> setActive(String chatUuid) async {
    if (!AppDatabase.isOpen) return;
    await _db.isar.writeTxn(() async {
      final all = await _db.chats.where().findAll();
      for (final c in all) {
        c.isActive = c.uuid == chatUuid;
      }
      await _db.chats.putAll(all);
    });
  }

  static Future<void> deleteChat(String chatUuid) async {
    if (!AppDatabase.isOpen) return;
    await _db.isar.writeTxn(() async {
      final messages = await _db.messages.filter().chatUuidEqualTo(chatUuid).findAll();
      final messageUuids = messages.map((m) => m.uuid).toSet();
      if (messageUuids.isNotEmpty) {
        await _db.attachments
            .filter()
            .anyOf(messageUuids, (q, uuid) => q.messageUuidEqualTo(uuid))
            .deleteAll();
      }
      await _db.messages.filter().chatUuidEqualTo(chatUuid).deleteAll();
      await _db.chats.filter().uuidEqualTo(chatUuid).deleteAll();
    });
  }

  /// Replace the message log for a chat. Existing messages + their attachments
  /// are deleted; [messages] are written. Image content carrying a base64 data
  /// URL is split out onto disk as an [AttachmentEntity] (sha256-deduped).
  static Future<void> replaceMessages(
    String chatUuid,
    List<ChatMessage> messages,
  ) async {
    if (!AppDatabase.isOpen) return;

    // Pre-persist any inline base64 image bytes to disk *outside* the Isar txn.
    // Build a list of (msg, attachmentEntities) so the txn body just writes rows.
    final pending = <_PendingMessage>[];
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final messageUuid =
          '${chatUuid}_${i}_${m.timestamp.microsecondsSinceEpoch}';
      final attachments = <AttachmentEntity>[];
      for (final part in m.content) {
        if (part.type == MessageContentType.image) {
          final att = await _persistDataUrlPart(part.value, messageUuid, AttachmentKind.image);
          if (att != null) attachments.add(att);
        } else if (part.type == MessageContentType.audio) {
          final att = await _persistDataUrlPart(part.value, messageUuid, AttachmentKind.audio);
          if (att != null) attachments.add(att);
        }
      }
      pending.add(_PendingMessage(
        uuid: messageUuid,
        message: m,
        sortIndex: i,
        attachments: attachments,
      ));
    }

    await _db.isar.writeTxn(() async {
      final existing =
          await _db.messages.filter().chatUuidEqualTo(chatUuid).findAll();
      final existingUuids = existing.map((m) => m.uuid).toSet();
      if (existingUuids.isNotEmpty) {
        await _db.attachments
            .filter()
            .anyOf(existingUuids, (q, uuid) => q.messageUuidEqualTo(uuid))
            .deleteAll();
      }
      await _db.messages.filter().chatUuidEqualTo(chatUuid).deleteAll();

      for (final p in pending) {
        if (p.attachments.isNotEmpty) {
          await _db.attachments.putAll(p.attachments);
        }
        await _db.messages.put(MessageEntity()
          ..uuid = p.uuid
          ..chatUuid = chatUuid
          ..role = p.message.isUser ? 'user' : 'assistant'
          ..content =
              p.message.textContent.isEmpty ? null : p.message.textContent
          ..attachmentUuids = p.attachments.map((a) => a.uuid).toList()
          ..createdAt = p.message.timestamp
          ..sortIndex = p.sortIndex);
      }
    });
  }

  static Future<AttachmentEntity?> _persistDataUrlPart(
    String value,
    String messageUuid,
    AttachmentKind kind,
  ) async {
    if (!value.startsWith('data:')) return null;
    final semiIdx = value.indexOf(';');
    final commaIdx = value.indexOf(',');
    if (semiIdx <= 0 || commaIdx <= semiIdx) return null;
    final mime = value.substring(5, semiIdx);
    final base64Data = value.substring(commaIdx + 1);
    try {
      final kindString = switch (kind) {
        AttachmentKind.image => 'image',
        AttachmentKind.audio => 'audio',
        AttachmentKind.file => 'file',
      };
      final result = await AttachmentStore.writeBase64(
        base64Data: base64Data,
        kind: kindString,
        extension: '.${mime.split('/').last}',
      );
      return AttachmentEntity()
        ..uuid =
            '${messageUuid}_att_${DateTime.now().microsecondsSinceEpoch}'
        ..messageUuid = messageUuid
        ..kind = kind
        ..filePath = result.path
        ..mimeType = mime
        ..sha256 = result.sha256
        ..sizeBytes = result.sizeBytes
        ..createdAt = DateTime.now();
    } catch (_) {
      return null;
    }
  }

  static ModelDefaults? _decodeOverrides(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      return ModelDefaults.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

class _PendingMessage {
  final String uuid;
  final ChatMessage message;
  final int sortIndex;
  final List<AttachmentEntity> attachments;
  _PendingMessage({
    required this.uuid,
    required this.message,
    required this.sortIndex,
    required this.attachments,
  });
}
