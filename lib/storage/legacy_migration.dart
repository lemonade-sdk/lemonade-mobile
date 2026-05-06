import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'entities/attachment_entity.dart';
import 'entities/chat_history_entity.dart';
import 'entities/message_entity.dart';
import 'entities/server_config_entity.dart';
import 'entities/transcription_entity.dart';
import 'file_storage.dart';
import 'secure_storage.dart';

/// One-time migration from SharedPreferences (pre-Isar shape) to Isar.
///
/// Safety: before doing anything, dumps every relevant SharedPreferences key into
/// `{appDocDir}/legacy-backup-<ts>.json` so a botched migration can be hand-recovered.
///
/// Idempotent: gated on [AppPrefsEntity.legacyMigrationCompleted].
class LegacyMigration {
  static const _kChatHistories = 'chat_histories';
  static const _kServers = 'servers';
  static const _kSelectedServerName = 'selected_server_name';
  static const _kSelectedModel = 'selected_model';
  static const _kGlobalModelDefaults = 'global_model_defaults';
  static const _kTranscriptionHistory = 'transcription_history';

  static const _uuid = Uuid();

  /// Run the migration if it hasn't already run. Returns true if migration ran on
  /// this call, false if it was already complete.
  static Future<bool> runIfNeeded() async {
    final db = AppDatabase.instance;
    final prefsRow = await db.readOrCreatePrefs();
    if (prefsRow.legacyMigrationCompleted) return false;

    final sp = await SharedPreferences.getInstance();

    // 1. Safety net.
    await _writeBackup(sp);

    // 2. Migrate.
    await _migrateServers(sp);
    await _migrateChats(sp);
    await _migrateTranscriptions(sp);
    await _migrateModelDefaults(sp);
    await _migrateSelectedServerAndModel(sp);

    // 3. Mark done.
    prefsRow.legacyMigrationCompleted = true;
    await db.isar.writeTxn(() async => db.appPrefs.put(prefsRow));
    return true;
  }

  // ---------------------------------------------------------------------------
  // Safety net
  // ---------------------------------------------------------------------------

  static Future<void> _writeBackup(SharedPreferences sp) async {
    final backup = <String, dynamic>{
      _kChatHistories: sp.getStringList(_kChatHistories),
      _kServers: sp.getStringList(_kServers),
      _kSelectedServerName: sp.getString(_kSelectedServerName),
      _kSelectedModel: sp.getString(_kSelectedModel),
      _kGlobalModelDefaults: sp.getString(_kGlobalModelDefaults),
      _kTranscriptionHistory: sp.getStringList(_kTranscriptionHistory),
      'backupCreatedAt': DateTime.now().toIso8601String(),
    };
    final docs = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().toUtc().millisecondsSinceEpoch;
    final path = p.join(docs.path, 'legacy-backup-$ts.json');
    final file = File(path);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(backup), flush: true);
  }

  // ---------------------------------------------------------------------------
  // Servers + API keys (api keys move into secure storage)
  // ---------------------------------------------------------------------------

  static Future<void> _migrateServers(SharedPreferences sp) async {
    final db = AppDatabase.instance;
    final list = sp.getStringList(_kServers) ?? const <String>[];

    final entities = <ServerConfigEntity>[];
    for (final raw in list) {
      Map<String, dynamic> json;
      try {
        json = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final name = json['name'] as String?;
      final baseUrl = json['baseUrl'] as String?;
      final apiKey = json['apiKey'] as String?;
      if (name == null || baseUrl == null) continue;

      var keyPersisted = false;
      if (apiKey != null && apiKey.isNotEmpty) {
        try {
          await SecureKeyStore.writeApiKey(name, apiKey);
          keyPersisted = true;
        } catch (_) {
          // Keychain unavailable (e.g. unsigned macOS build) — drop the key on
          // the floor rather than blocking app startup. User will need to
          // re-enter it once signing is sorted.
        }
      }

      entities.add(ServerConfigEntity()
        ..name = name
        ..baseUrl = baseUrl
        ..hasApiKey = keyPersisted
        ..createdAt = DateTime.now());
    }

    if (entities.isEmpty) return;
    await db.isar.writeTxn(() async {
      await db.serverConfigs.putAll(entities);
    });
  }

  // ---------------------------------------------------------------------------
  // Chat histories: each chat → ChatHistoryEntity + N MessageEntity (+ attachments)
  // ---------------------------------------------------------------------------

  static Future<void> _migrateChats(SharedPreferences sp) async {
    final db = AppDatabase.instance;
    final list = sp.getStringList(_kChatHistories) ?? const <String>[];

    final chatRows = <ChatHistoryEntity>[];
    final messageRows = <MessageEntity>[];
    final attachmentRows = <AttachmentEntity>[];

    for (final raw in list) {
      Map<String, dynamic> chatJson;
      try {
        chatJson = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      final chatUuid = (chatJson['id'] as String?) ?? _uuid.v4();
      final chatRow = ChatHistoryEntity()
        ..uuid = chatUuid
        ..title = chatJson['title'] as String?
        ..folderUuid = null
        ..createdAt = _parseDate(chatJson['createdAt']) ?? DateTime.now()
        ..lastUpdated = _parseDate(chatJson['lastUpdated']) ?? DateTime.now()
        ..isActive = (chatJson['isActive'] as bool?) ?? false
        ..modelOverridesJson = chatJson['modelOverrides'] is Map
            ? jsonEncode(chatJson['modelOverrides'])
            : null;
      chatRows.add(chatRow);

      final messages = chatJson['messages'];
      if (messages is! List) continue;

      var sortIndex = 0;
      for (final m in messages) {
        if (m is! Map<String, dynamic>) continue;

        final messageUuid = _uuid.v4();
        final role = m['role'] as String? ?? 'user';
        final timestamp = _parseDate(m['timestamp']) ?? DateTime.now();

        // Legacy `content` was either a String OR a List<{type,value}> with
        // type ∈ {'text','image'}. Walk it, collecting text + extracting images.
        String? collectedText;
        final attachmentUuids = <String>[];
        final raw = m['content'];

        if (raw is String) {
          collectedText = raw;
        } else if (raw is List) {
          final textParts = <String>[];
          for (final item in raw) {
            if (item is! Map<String, dynamic>) continue;
            final type = item['type'] as String?;
            final value = item['value'] as String?;
            if (type == 'text' && value != null) {
              textParts.add(value);
            } else if (type == 'image' && value != null) {
              final att = await _persistImageContent(value, messageUuid);
              if (att != null) {
                attachmentRows.add(att);
                attachmentUuids.add(att.uuid);
              }
            }
          }
          if (textParts.isNotEmpty) collectedText = textParts.join('\n');
        }

        messageRows.add(MessageEntity()
          ..uuid = messageUuid
          ..chatUuid = chatUuid
          ..role = role
          ..content = collectedText
          ..attachmentUuids = attachmentUuids
          ..createdAt = timestamp
          ..sortIndex = sortIndex++);
      }
    }

    if (chatRows.isEmpty) return;
    await db.isar.writeTxn(() async {
      await db.chats.putAll(chatRows);
      if (messageRows.isNotEmpty) await db.messages.putAll(messageRows);
      if (attachmentRows.isNotEmpty) await db.attachments.putAll(attachmentRows);
    });
  }

  /// Decode legacy image content into an [AttachmentEntity], persisting bytes to disk.
  /// Supports data URLs, raw base64, and absolute file paths from older versions.
  /// Network URLs (http/https) are skipped — we keep the URL inline by re-emitting
  /// the original content; for migration we drop them rather than fetching at startup.
  static Future<AttachmentEntity?> _persistImageContent(
    String value,
    String messageUuid,
  ) async {
    if (value.startsWith('data:image/')) {
      final commaIdx = value.indexOf(',');
      if (commaIdx <= 0) return null;
      final header = value.substring(5, value.indexOf(';')); // "image/jpeg"
      final base64 = value.substring(commaIdx + 1);
      try {
        final result = await AttachmentStore.writeBase64(
          base64Data: base64,
          kind: 'image',
          extension: '.${header.split('/').last}',
        );
        return AttachmentEntity()
          ..uuid = _uuid.v4()
          ..messageUuid = messageUuid
          ..kind = AttachmentKind.image
          ..filePath = result.path
          ..mimeType = header
          ..sha256 = result.sha256
          ..sizeBytes = result.sizeBytes
          ..createdAt = DateTime.now();
      } catch (_) {
        return null;
      }
    }

    if (value.startsWith('http://') || value.startsWith('https://')) {
      // Skip remote URL images during migration; user can re-upload if needed.
      return null;
    }

    // Could be a raw base64 blob or a file path. Try base64 first.
    if (_looksLikeBase64(value)) {
      try {
        final result = await AttachmentStore.writeBase64(
          base64Data: value,
          kind: 'image',
          extension: '.jpg',
        );
        return AttachmentEntity()
          ..uuid = _uuid.v4()
          ..messageUuid = messageUuid
          ..kind = AttachmentKind.image
          ..filePath = result.path
          ..mimeType = 'image/jpeg'
          ..sha256 = result.sha256
          ..sizeBytes = result.sizeBytes
          ..createdAt = DateTime.now();
      } catch (_) {}
    }

    if (await File(value).exists()) {
      final f = File(value);
      final size = await f.length();
      final hash = await AttachmentStore.sha256OfFile(value);
      return AttachmentEntity()
        ..uuid = _uuid.v4()
        ..messageUuid = messageUuid
        ..kind = AttachmentKind.image
        ..filePath = value
        ..mimeType = 'image/jpeg'
        ..sha256 = hash
        ..sizeBytes = size
        ..createdAt = DateTime.now();
    }

    return null;
  }

  static bool _looksLikeBase64(String s) {
    if (s.length < 100) return false;
    return RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(s);
  }

  // ---------------------------------------------------------------------------
  // Transcriptions
  // ---------------------------------------------------------------------------

  static Future<void> _migrateTranscriptions(SharedPreferences sp) async {
    final db = AppDatabase.instance;
    final list = sp.getStringList(_kTranscriptionHistory) ?? const <String>[];

    final entities = <TranscriptionEntity>[];
    for (final raw in list) {
      Map<String, dynamic> json;
      try {
        json = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      entities.add(TranscriptionEntity()
        ..uuid = (json['id'] as String?) ?? _uuid.v4()
        ..text = json['text'] as String? ?? ''
        ..modelId = json['modelId'] as String?
        ..mode = json['mode'] as String? ?? 'http'
        ..serverName = json['serverName'] as String?
        ..audioFilePath = json['audioFilePath'] as String?
        ..audioDurationMs = (json['audioDurationMs'] as num?)?.toInt()
        ..createdAt = _parseDate(json['createdAt']) ?? DateTime.now());
    }

    if (entities.isEmpty) return;
    await db.isar.writeTxn(() async => db.transcriptions.putAll(entities));
  }

  // ---------------------------------------------------------------------------
  // Global model defaults (singleton row)
  // ---------------------------------------------------------------------------

  static Future<void> _migrateModelDefaults(SharedPreferences sp) async {
    final db = AppDatabase.instance;
    final raw = sp.getString(_kGlobalModelDefaults);
    if (raw == null || raw.isEmpty) return;

    Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final row = await db.readOrCreateDefaults();
    row
      ..llmModel = json['llmModel'] as String?
      ..audioToTextModel = json['audioToTextModel'] as String?
      ..textToAudioModel = json['textToAudioModel'] as String?
      ..imageGenerationModel = json['imageGenerationModel'] as String?;

    await db.isar.writeTxn(() async => db.modelDefaults.put(row));
  }

  // ---------------------------------------------------------------------------
  // Selected server / model -> AppPrefs
  // ---------------------------------------------------------------------------

  static Future<void> _migrateSelectedServerAndModel(SharedPreferences sp) async {
    final db = AppDatabase.instance;
    final prefs = await db.readOrCreatePrefs();
    prefs
      ..selectedServerName = sp.getString(_kSelectedServerName)
      ..selectedModelId = sp.getString(_kSelectedModel);
    await db.isar.writeTxn(() async => db.appPrefs.put(prefs));
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static DateTime? _parseDate(dynamic v) {
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {}
    }
    if (v is int) {
      return DateTime.fromMillisecondsSinceEpoch(v);
    }
    return null;
  }
}
