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
    final candidate = Folder(
      id: _uuid.v4(),
      name: inboxName,
      parentFolderId: null,
      sortOrder: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    if (!AppDatabase.isOpen) return candidate;
    // Check + create inside one writeTxn so concurrent callers can't both
    // miss the lookup and create duplicate Inboxes.
    return _db.isar.writeTxn(() async {
      final existing = await _db.folders
          .filter()
          .parentFolderUuidIsNull()
          .nameEqualTo(inboxName)
          .findFirst();
      if (existing != null) return _toModel(existing);
      await _db.folders.put(_toEntity(candidate));
      return candidate;
    });
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
    // Match the silent no-op convention of the other methods when the DB
    // isn't open: return the in-memory model without persisting.
    if (!AppDatabase.isOpen) return folder;
    await _db.isar.writeTxn(() async {
      await _db.folders.put(_toEntity(folder));
    });
    return folder;
  }

  static Future<void> rename(String folderId, String newName) async {
    if (!AppDatabase.isOpen) return;
    // Read inside the txn so a concurrent remove() can't have its delete
    // undone by this put resurrecting the folder.
    await _db.isar.writeTxn(() async {
      final entity =
          await _db.folders.filter().uuidEqualTo(folderId).findFirst();
      if (entity == null) return;
      entity
        ..name = newName
        ..updatedAt = DateTime.now();
      await _db.folders.put(entity);
    });
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
    // Read inside the txn (see rename) so a concurrently removed folder
    // can't be resurrected, and verify the target parent still exists.
    await _db.isar.writeTxn(() async {
      final entity =
          await _db.folders.filter().uuidEqualTo(folderId).findFirst();
      if (entity == null) return;
      if (newParentId != null) {
        final parent =
            await _db.folders.filter().uuidEqualTo(newParentId).findFirst();
        if (parent == null) return;
      }
      entity
        ..parentFolderUuid = newParentId
        ..updatedAt = DateTime.now();
      await _db.folders.put(entity);
    });
  }

  static Future<void> setChatFolder(String chatId, String? folderId) async {
    if (!AppDatabase.isOpen) return;
    // Read + verify inside the txn so the chat can't end up pointing at a
    // folder that a concurrent remove() just deleted.
    await _db.isar.writeTxn(() async {
      final chat = await _db.chats.filter().uuidEqualTo(chatId).findFirst();
      if (chat == null) return;
      if (folderId != null) {
        final target =
            await _db.folders.filter().uuidEqualTo(folderId).findFirst();
        if (target == null) return;
      }
      chat
        ..folderUuid = folderId
        ..lastUpdated = DateTime.now();
      await _db.chats.put(chat);
    });
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
