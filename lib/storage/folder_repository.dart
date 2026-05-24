import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';

import '../models/folder.dart';
import 'database.dart';
import 'entities/chat_history_entity.dart';
import 'entities/folder_entity.dart';

class FolderRepository {
  static const _uuid = Uuid();
  static AppDatabase get _db => AppDatabase.instance;

  /// Inbox is the implicit root folder. We materialize it on first access so
  /// the rest of the codebase can treat it like any other folder.
  static const String inboxName = 'Inbox';

  static Future<List<Folder>> loadAll() async {
    if (!AppDatabase.isOpen) return const [];
    final rows = await _db.folders.where().sortBySortOrder().findAll();
    return rows.map(_toModel).toList(growable: false);
  }

  static Future<Folder> ensureInbox() async {
    final all = await loadAll();
    final existing = all
        .where((f) => f.parentFolderId == null && f.name == inboxName)
        .firstOrNull;
    if (existing != null) return existing;
    return create(name: inboxName);
  }

  static Future<Folder> create({
    required String name,
    String? parentFolderId,
    int sortOrder = 0,
  }) async {
    final folder = Folder(
      id: _uuid.v4(),
      name: name,
      parentFolderId: parentFolderId,
      sortOrder: sortOrder,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.isar.writeTxn(() async {
      await _db.folders.put(_toEntity(folder));
    });
    return folder;
  }

  static Future<void> rename(String folderId, String newName) async {
    if (!AppDatabase.isOpen) return;
    final entity = await _db.folders.filter().uuidEqualTo(folderId).findFirst();
    if (entity == null) return;
    entity
      ..name = newName
      ..updatedAt = DateTime.now();
    await _db.isar.writeTxn(() async => _db.folders.put(entity));
  }

  static Future<void> remove(String folderId) async {
    if (!AppDatabase.isOpen) return;
    await _db.isar.writeTxn(() async {
      // Promote any child folders + chats up one level (to root).
      final childFolders =
          await _db.folders.filter().parentFolderUuidEqualTo(folderId).findAll();
      for (final c in childFolders) {
        c.parentFolderUuid = null;
      }
      if (childFolders.isNotEmpty) await _db.folders.putAll(childFolders);

      final affectedChats =
          await _db.chats.filter().folderUuidEqualTo(folderId).findAll();
      for (final c in affectedChats) {
        c.folderUuid = null;
      }
      if (affectedChats.isNotEmpty) await _db.chats.putAll(affectedChats);

      await _db.folders.filter().uuidEqualTo(folderId).deleteAll();
    });
  }

  static Future<void> move({
    required String folderId,
    String? newParentId,
  }) async {
    if (!AppDatabase.isOpen) return;
    final entity = await _db.folders.filter().uuidEqualTo(folderId).findFirst();
    if (entity == null) return;
    entity
      ..parentFolderUuid = newParentId
      ..updatedAt = DateTime.now();
    await _db.isar.writeTxn(() async => _db.folders.put(entity));
  }

  static Future<void> setChatFolder(String chatId, String? folderId) async {
    if (!AppDatabase.isOpen) return;
    final chat = await _db.chats.filter().uuidEqualTo(chatId).findFirst();
    if (chat == null) return;
    chat
      ..folderUuid = folderId
      ..lastUpdated = DateTime.now();
    await _db.isar.writeTxn(() async => _db.chats.put(chat));
  }

  // ---------------------------------------------------------------------------

  static Folder _toModel(FolderEntity e) => Folder(
        id: e.uuid,
        name: e.name,
        parentFolderId: e.parentFolderUuid,
        sortOrder: e.sortOrder,
        createdAt: e.createdAt,
        updatedAt: e.updatedAt,
      );

  static FolderEntity _toEntity(Folder f) => FolderEntity()
    ..uuid = f.id
    ..name = f.name
    ..parentFolderUuid = f.parentFolderId
    ..sortOrder = f.sortOrder
    ..createdAt = f.createdAt
    ..updatedAt = f.updatedAt;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
