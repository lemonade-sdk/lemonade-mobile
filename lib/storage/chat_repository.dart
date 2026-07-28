import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

  /// Cache of attachment parts that already live on disk, keyed by the
  /// MessageContent object identity. During a streaming turn the exact same
  /// MessageContent instances get re-submitted on every save — without this,
  /// each save base64-decoded, sha256-hashed and re-wrote every attachment in
  /// the chat on the UI isolate.
  static final Expando<_StoredAttachment> _persistedParts =
      Expando<_StoredAttachment>('ChatRepository.persistedParts');

  static void _logClosed(String op) => debugPrint(
      'ChatRepository.$op skipped — database is not open; data was NOT persisted.');

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  static Future<List<ChatHistory>> loadAll() async {
    if (!AppDatabase.isOpen) {
      debugPrint('ChatRepository.loadAll: database is not open — returning no chats.');
      return const [];
    }
    final chatRows = await _db.chats.where().sortByLastUpdatedDesc().findAll();
    final result = <ChatHistory>[];
    for (final chat in chatRows) {
      // One corrupt chat (bad rows, unreadable attachment) must not blank the
      // entire history — skip it and keep loading the rest. Its rows stay on
      // disk untouched.
      try {
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
      } catch (e) {
        debugPrint('ChatRepository.loadAll: failed to load chat ${chat.uuid} — skipping: $e');
      }
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
        // Cold start: keep a file-backed ref only — do NOT base64 the whole
        // attachment into provider memory. Bytes load on demand in the UI.
        MessageContent? content;
        try {
          content = await _attachmentToFileRef(a);
        } catch (e) {
          debugPrint('ChatRepository: skipping unreadable attachment ${a.uuid} '
              '(${a.filePath}): $e');
        }
        if (content == null) continue;
        _persistedParts[content] = _StoredAttachment(
          filePath: content.fileRefPath ?? a.filePath,
          mimeType: a.mimeType,
          sha256: a.sha256,
          sizeBytes: a.sizeBytes,
        );
        contents.add(content);
      }
      out.add(ChatMessage(
        id: m.uuid,
        role: m.role == 'user' ? MessageRole.user : MessageRole.assistant,
        content: contents,
        timestamp: m.createdAt,
      ));
    }
    return out;
  }

  /// Resolve attachment to a [MessageContent.fileRef] without reading bytes.
  static Future<MessageContent?> _attachmentToFileRef(AttachmentEntity a) async {
    final kind = switch (a.kind) {
      AttachmentKind.image => 'image',
      AttachmentKind.audio => 'audio',
      AttachmentKind.file => 'file',
    };
    final f = await AttachmentStore.resolveExisting(kind, a.filePath);
    if (f == null) return null;
    final path = f.path;
    final type = switch (a.kind) {
      AttachmentKind.image => MessageContentType.image,
      AttachmentKind.audio => MessageContentType.audio,
      AttachmentKind.file => null,
    };
    if (type == null) return null;
    return MessageContent(
      type: type,
      value: MessageContent.fileRef(mime: a.mimeType, path: path),
    );
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  /// Write a chat row. With [updateOnly] the write is dropped when the row no
  /// longer exists — the streaming autosave path uses this so a save queued
  /// behind the write lock can't resurrect a chat deleted moments earlier.
  static Future<void> upsertChat(ChatHistory chat, {bool updateOnly = false}) async {
    if (!AppDatabase.isOpen) {
      _logClosed('upsertChat');
      return;
    }
    await _db.isar.writeTxn(() async {
      var existing = await _db.chats.filter().uuidEqualTo(chat.id).findFirst();
      if (existing == null && updateOnly) {
        debugPrint('ChatRepository.upsertChat: chat ${chat.id} no longer exists '
            '— dropping update-only write.');
        return;
      }
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
    if (!AppDatabase.isOpen) {
      _logClosed('setActive');
      return;
    }
    await _db.isar.writeTxn(() async {
      // Only touch the rows that actually change: the previously-active
      // chat(s) and the new one — not every chat row in the table.
      final toPut = <ChatHistoryEntity>[];
      final stale = await _db.chats
          .filter()
          .isActiveEqualTo(true)
          .not()
          .uuidEqualTo(chatUuid)
          .findAll();
      for (final c in stale) {
        toPut.add(c..isActive = false);
      }
      final target = await _db.chats.filter().uuidEqualTo(chatUuid).findFirst();
      if (target != null && !target.isActive) {
        toPut.add(target..isActive = true);
      }
      if (toPut.isNotEmpty) await _db.chats.putAll(toPut);
    });
  }

  static Future<void> deleteChat(String chatUuid) async {
    if (!AppDatabase.isOpen) {
      _logClosed('deleteChat');
      return;
    }
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

  /// Persist the message log for a chat with **differential** updates.
  ///
  /// Messages carry a stable [ChatMessage.id] (Isar uuid). Unchanged messages
  /// (same id + content fingerprint + sort index) are left alone — streaming
  /// autosave only rewrites the trailing assistant row instead of delete-all
  /// + reinsert. Attachments are file-backed / sha256-deduped.
  ///
  /// If the chat was deleted while this save was queued, the write is dropped.
  static Future<void> replaceMessages(
    String chatUuid,
    List<ChatMessage> messages,
  ) async {
    if (!AppDatabase.isOpen) {
      _logClosed('replaceMessages');
      return;
    }

    // Snapshot existing rows + fingerprints so we can skip no-ops.
    final existingRows =
        await _db.messages.filter().chatUuidEqualTo(chatUuid).findAll();
    final existingById = {for (final m in existingRows) m.uuid: m};
    final existingFp = <String, String>{};
    for (final m in existingRows) {
      existingFp[m.uuid] =
          '${m.role}|${m.content ?? ''}|${m.attachmentUuids.join(",")}|${m.sortIndex}';
    }

    // Pre-persist media *outside* the Isar txn (disk I/O).
    final pending = <_PendingMessage>[];
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final messageUuid = m.id;
      final attachments = <AttachmentEntity>[];
      for (final part in m.content) {
        if (part.type == MessageContentType.image) {
          final att =
              await _persistMediaPart(part, messageUuid, AttachmentKind.image);
          if (att != null) attachments.add(att);
        } else if (part.type == MessageContentType.audio) {
          final att =
              await _persistMediaPart(part, messageUuid, AttachmentKind.audio);
          if (att != null) attachments.add(att);
        }
      }
      final attIds = attachments.map((a) => a.uuid).toList()..sort();
      final fp =
          '${m.isUser ? 'user' : 'assistant'}|${m.textContent}|${attIds.join(",")}|$i';
      final prior = existingById[messageUuid];
      final unchanged = prior != null && existingFp[messageUuid] == fp;
      pending.add(_PendingMessage(
        uuid: messageUuid,
        message: m,
        sortIndex: i,
        attachments: attachments,
        skipWrite: unchanged,
      ));
    }

    final keepIds = {for (final p in pending) p.uuid};

    await _db.isar.writeTxn(() async {
      final chatRow =
          await _db.chats.filter().uuidEqualTo(chatUuid).findFirst();
      if (chatRow == null) {
        debugPrint('ChatRepository.replaceMessages: chat $chatUuid no longer '
            'exists — dropping write.');
        return;
      }

      // Delete messages (and their attachments) that are no longer present.
      final stale = existingRows.where((m) => !keepIds.contains(m.uuid)).toList();
      if (stale.isNotEmpty) {
        final staleUuids = stale.map((m) => m.uuid).toSet();
        await _db.attachments
            .filter()
            .anyOf(staleUuids, (q, uuid) => q.messageUuidEqualTo(uuid))
            .deleteAll();
        await _db.messages
            .filter()
            .anyOf(staleUuids, (q, uuid) => q.uuidEqualTo(uuid))
            .deleteAll();
      }

      for (final p in pending) {
        if (p.skipWrite) continue;

        // Replace this message's attachments only (not the whole chat).
        await _db.attachments
            .filter()
            .messageUuidEqualTo(p.uuid)
            .deleteAll();
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

  /// Persist a media part from data URL or file ref. Reuses Expando cache and
  /// file refs so streaming saves don't re-hash.
  static Future<AttachmentEntity?> _persistMediaPart(
    MessageContent part,
    String messageUuid,
    AttachmentKind kind,
  ) async {
    final cached = _persistedParts[part];
    if (cached != null) {
      return _entityFor(cached, messageUuid, kind);
    }

    final value = part.value;
    final kindString = switch (kind) {
      AttachmentKind.image => 'image',
      AttachmentKind.audio => 'audio',
      AttachmentKind.file => 'file',
    };

    // Already on disk (cold-start file ref).
    final fileRef = MessageContent.parseFileRef(value);
    if (fileRef != null) {
      try {
        final hash = await AttachmentStore.sha256OfFile(fileRef.path);
        final size = await File(fileRef.path).length();
        final stored = _StoredAttachment(
          filePath: fileRef.path,
          mimeType: fileRef.mime,
          sha256: hash,
          sizeBytes: size,
        );
        _persistedParts[part] = stored;
        return _entityFor(stored, messageUuid, kind);
      } catch (_) {
        return null;
      }
    }

    if (!value.startsWith('data:')) return null;
    final semiIdx = value.indexOf(';');
    final commaIdx = value.indexOf(',');
    if (semiIdx <= 0 || commaIdx <= semiIdx) return null;
    final mime = value.substring(5, semiIdx);
    final base64Data = value.substring(commaIdx + 1);
    try {
      final result = await AttachmentStore.writeBase64(
        base64Data: base64Data,
        kind: kindString,
        extension: '.${mime.split('/').last}',
      );
      final stored = _StoredAttachment(
        filePath: result.path,
        mimeType: mime,
        sha256: result.sha256,
        sizeBytes: result.sizeBytes,
      );
      _persistedParts[part] = stored;
      return _entityFor(stored, messageUuid, kind);
    } catch (_) {
      return null;
    }
  }

  static AttachmentEntity _entityFor(
    _StoredAttachment stored,
    String messageUuid,
    AttachmentKind kind,
  ) {
    // Stable attachment uuid from content hash — re-saves don't churn rows.
    final attUuid =
        '${messageUuid}_att_${stored.sha256.substring(0, 16)}';
    return AttachmentEntity()
      ..uuid = attUuid
      ..messageUuid = messageUuid
      ..kind = kind
      ..filePath = stored.filePath
      ..mimeType = stored.mimeType
      ..sha256 = stored.sha256
      ..sizeBytes = stored.sizeBytes
      ..createdAt = DateTime.now();
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
  final bool skipWrite;
  _PendingMessage({
    required this.uuid,
    required this.message,
    required this.sortIndex,
    required this.attachments,
    this.skipWrite = false,
  });
}

/// On-disk location + metadata of an attachment part that has already been
/// persisted, cached per MessageContent instance (see `_persistedParts`).
class _StoredAttachment {
  final String filePath;
  final String mimeType;
  final String sha256;
  final int sizeBytes;
  const _StoredAttachment({
    required this.filePath,
    required this.mimeType,
    required this.sha256,
    required this.sizeBytes,
  });
}
