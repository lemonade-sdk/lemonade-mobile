import 'dart:async';
import 'dart:io';

import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'entities/app_prefs_entity.dart';
import 'entities/attachment_entity.dart';
import 'entities/chat_history_entity.dart';
import 'entities/folder_entity.dart';
import 'entities/message_entity.dart';
import 'entities/model_defaults_entity.dart';
import 'entities/server_config_entity.dart';
import 'entities/transcription_entity.dart';

/// Top-level handle to the app's Isar database. Use [AppDatabase.instance] after
/// calling [AppDatabase.open] once at startup.
class AppDatabase {
  static const String _isarName = 'lemonade_mobile';
  static AppDatabase? _instance;

  final Isar isar;

  AppDatabase._(this.isar);

  static AppDatabase get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError('AppDatabase.open() has not been called yet.');
    }
    return inst;
  }

  static bool get isOpen => _instance != null;

  /// Open (or return existing) Isar database. Idempotent.
  static Future<AppDatabase> open() async {
    if (_instance != null) return _instance!;

    final dir = await getApplicationDocumentsDirectory();
    final isarDir = p.join(dir.path, 'isar');
    final isarDirHandle = Directory(isarDir);
    if (!await isarDirHandle.exists()) {
      await isarDirHandle.create(recursive: true);
    }

    final isar = await Isar.open(
      [
        AppPrefsEntitySchema,
        AttachmentEntitySchema,
        ChatHistoryEntitySchema,
        FolderEntitySchema,
        MessageEntitySchema,
        ModelDefaultsEntitySchema,
        ServerConfigEntitySchema,
        TranscriptionEntitySchema,
      ],
      directory: isarDir,
      name: _isarName,
      inspector: false,
    );

    _instance = AppDatabase._(isar);
    return _instance!;
  }

  Future<void> close() async {
    await isar.close();
    _instance = null;
  }

  // ---------------------------------------------------------------------------
  // Convenience accessors for collections.
  // ---------------------------------------------------------------------------

  IsarCollection<AppPrefsEntity> get appPrefs => isar.appPrefsEntitys;
  IsarCollection<AttachmentEntity> get attachments => isar.attachmentEntitys;
  IsarCollection<ChatHistoryEntity> get chats => isar.chatHistoryEntitys;
  IsarCollection<FolderEntity> get folders => isar.folderEntitys;
  IsarCollection<MessageEntity> get messages => isar.messageEntitys;
  IsarCollection<ModelDefaultsEntity> get modelDefaults => isar.modelDefaultsEntitys;
  IsarCollection<ServerConfigEntity> get serverConfigs => isar.serverConfigEntitys;
  IsarCollection<TranscriptionEntity> get transcriptions => isar.transcriptionEntitys;

  // ---------------------------------------------------------------------------
  // Singleton row helpers.
  // ---------------------------------------------------------------------------

  /// Always returns a row. Creates a default if missing.
  Future<AppPrefsEntity> readOrCreatePrefs() async {
    final existing = await appPrefs.get(0);
    if (existing != null) return existing;
    final fresh = AppPrefsEntity();
    await isar.writeTxn(() async => appPrefs.put(fresh));
    return fresh;
  }

  Future<ModelDefaultsEntity> readOrCreateDefaults() async {
    final existing = await modelDefaults.get(0);
    if (existing != null) return existing;
    final fresh = ModelDefaultsEntity();
    await isar.writeTxn(() async => modelDefaults.put(fresh));
    return fresh;
  }
}
