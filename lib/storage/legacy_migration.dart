import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
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
/// Safety: before doing anything, dumps every relevant SharedPreferences key
/// (with API keys redacted) into `{appDocDir}/legacy-backup-<ts>.json` so a
/// botched migration can be hand-recovered. The backup is written at most once.
///
/// Idempotent: gated on [AppPrefsEntity.legacyMigrationCompleted], with
/// per-step SharedPreferences flags (`legacyMigrated.<step>`) so a crash
/// between a committed step and the final flag resumes on the next launch
/// instead of re-colliding on unique indexes.
class LegacyMigration {
  static const _kChatHistories = 'chat_histories';
  static const _kServers = 'servers';
  static const _kSelectedServerName = 'selected_server_name';
  static const _kSelectedModel = 'selected_model';
  static const _kGlobalModelDefaults = 'global_model_defaults';
  static const _kTranscriptionHistory = 'transcription_history';

  static const _kBackupWrittenFlag = 'legacy_backup_written';
  static const _kStepFlagPrefix = 'legacyMigrated.';
  static const _redactedMarker = '<redacted>';

  static const _uuid = Uuid();

  /// Run the migration if it hasn't already run. Returns true if migration ran on
  /// this call, false if it was already complete.
  static Future<bool> runIfNeeded() async {
    final db = AppDatabase.instance;
    final prefsRow = await db.readOrCreatePrefs();
    if (prefsRow.legacyMigrationCompleted) return false;

    final sp = await SharedPreferences.getInstance();

    // 1. Safety net — written once (flag-guarded) so a failing migration
    //    doesn't stack a fresh copy on every launch.
    if (!(sp.getBool(_kBackupWrittenFlag) ?? false)) {
      await _writeBackup(sp);
      await sp.setBool(_kBackupWrittenFlag, true);
    }
    // Older builds wrote backups containing plaintext API keys (the docs dir
    // is included in device/iCloud backups). Now that a redacted copy exists,
    // remove any key-bearing ones.
    await _deleteUnredactedBackups();

    // 2. Migrate. Each step is idempotent and skipped once its flag is set.
    await _runStep(sp, 'servers', () => _migrateServers(sp));
    await _runStep(sp, 'chats', () => _migrateChats(sp));
    await _runStep(sp, 'transcriptions', () => _migrateTranscriptions(sp));
    await _runStep(sp, 'modelDefaults', () => _migrateModelDefaults(sp));
    await _runStep(sp, 'selection', () => _migrateSelectedServerAndModel(sp));

    // 3. Mark done. Re-read the prefs row: the selection step above rewrote
    //    it, and putting the stale copy from the top of this method would
    //    clobber the migrated server/model selection.
    final donePrefs = await db.readOrCreatePrefs();
    donePrefs.legacyMigrationCompleted = true;
    await db.isar.writeTxn(() async => db.appPrefs.put(donePrefs));
    return true;
  }

  /// Run [body] unless [step] already completed on a previous (partial) run.
  static Future<void> _runStep(
    SharedPreferences sp,
    String step,
    Future<void> Function() body,
  ) async {
    final flag = '$_kStepFlagPrefix$step';
    if (sp.getBool(flag) ?? false) return;
    await body();
    await sp.setBool(flag, true);
  }

  // ---------------------------------------------------------------------------
  // Safety net
  // ---------------------------------------------------------------------------

  static Future<void> _writeBackup(SharedPreferences sp) async {
    final backup = <String, dynamic>{
      _kChatHistories: sp.getStringList(_kChatHistories),
      _kServers: _redactServers(sp.getStringList(_kServers)),
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

  /// Strip plaintext API keys from the legacy servers payload before it hits
  /// disk. The real keys move into secure storage during [_migrateServers].
  static List<String>? _redactServers(List<String>? servers) {
    if (servers == null) return null;
    return servers.map((raw) {
      try {
        final json = jsonDecode(raw);
        if (json is Map<String, dynamic>) {
          final key = json['apiKey'];
          if (key is String && key.isNotEmpty) {
            json['apiKey'] = _redactedMarker;
            return jsonEncode(json);
          }
        }
      } catch (_) {}
      return raw;
    }).toList(growable: false);
  }

  /// Delete any `legacy-backup-*.json` that still contains plaintext API keys.
  /// Safe: only called after a redacted backup has been written.
  static Future<void> _deleteUnredactedBackups() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      await for (final entry in docs.list(followLinks: false)) {
        if (entry is! File) continue;
        final name = p.basename(entry.path);
        if (!name.startsWith('legacy-backup-') || !name.endsWith('.json')) {
          continue;
        }
        try {
          if (await _containsPlaintextKeys(entry)) await entry.delete();
        } catch (_) {}
      }
    } catch (_) {
      // Best-effort cleanup; never block the migration on it.
    }
  }

  static Future<bool> _containsPlaintextKeys(File f) async {
    final content = await f.readAsString();
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        final servers = decoded[_kServers];
        if (servers is List) {
          for (final raw in servers) {
            if (raw is! String) continue;
            try {
              final json = jsonDecode(raw);
              if (json is Map) {
                final key = json['apiKey'];
                if (key is String && key.isNotEmpty && key != _redactedMarker) {
                  return true;
                }
              }
            } catch (_) {}
          }
        }
        return false;
      }
    } catch (_) {}
    // Unparseable — be conservative: treat any apiKey mention without the
    // redaction marker as sensitive.
    return content.contains('apiKey') && !content.contains(_redactedMarker);
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
      // Idempotent: `name` has a unique index with replace:false, so a
      // partially-committed previous run would make putAll throw. Skip rows
      // that already exist instead.
      for (final e in entities) {
        final exists =
            await db.serverConfigs.filter().nameEqualTo(e.name).findFirst();
        if (exists == null) await db.serverConfigs.put(e);
      }
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

    // Idempotent: skip chats whose uuid is already in Isar (committed by a
    // previous partial run) — re-inserting would violate the unique index.
    final seenUuids =
        (await db.chats.where().uuidProperty().findAll()).toSet();

    for (final raw in list) {
      Map<String, dynamic> chatJson;
      try {
        chatJson = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      final chatUuid = (chatJson['id'] as String?) ?? _uuid.v4();
      if (!seenUuids.add(chatUuid)) continue;
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

    // Legacy absolute file path: copy the bytes into the content-addressed
    // store rather than adopting the path as-is — the old absolute path goes
    // stale on the next iOS container move and the image is unrecoverable.
    try {
      final f = File(value);
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) return null;
        final ext = p.extension(value).toLowerCase();
        final extension = ext.isNotEmpty ? ext : '.jpg';
        final path = await AttachmentStore.writeBytes(
          bytes: bytes,
          kind: 'image',
          extension: extension,
        );
        return AttachmentEntity()
          ..uuid = _uuid.v4()
          ..messageUuid = messageUuid
          ..kind = AttachmentKind.image
          ..filePath = path
          ..mimeType = _mimeForExtension(extension)
          ..sha256 = AttachmentStore.sha256OfBytes(bytes)
          ..sizeBytes = bytes.length
          ..createdAt = DateTime.now();
      }
    } catch (_) {
      // Source unreadable — skip this image gracefully.
    }

    return null;
  }

  static String _mimeForExtension(String ext) => switch (ext) {
        '.png' => 'image/png',
        '.gif' => 'image/gif',
        '.webp' => 'image/webp',
        '.bmp' => 'image/bmp',
        _ => 'image/jpeg',
      };

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

    // Idempotent: skip transcriptions already committed by a partial run.
    final seenUuids =
        (await db.transcriptions.where().uuidProperty().findAll()).toSet();

    final entities = <TranscriptionEntity>[];
    for (final raw in list) {
      Map<String, dynamic> json;
      try {
        json = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final uuid = (json['id'] as String?) ?? _uuid.v4();
      if (!seenUuids.add(uuid)) continue;
      entities.add(TranscriptionEntity()
        ..uuid = uuid
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
