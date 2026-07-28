import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/folder.dart';
import '../storage/folder_repository.dart';

final foldersProvider =
    StateNotifierProvider<FoldersNotifier, List<Folder>>((ref) => FoldersNotifier());

class FoldersNotifier extends StateNotifier<List<Folder>> {
  FoldersNotifier() : super([]) {
    _load();
  }

  /// Set on the first user mutation — a late-resolving [_load] must not
  /// overwrite state that already contains changes made during the
  /// cold-start window.
  bool _userDirty = false;

  Future<void> _load() async {
    final all = await FolderRepository.loadAll();
    if (_userDirty) return;
    if (all.isEmpty) {
      // Create Inbox on first run.
      final inbox = await FolderRepository.ensureInbox();
      if (_userDirty) return;
      state = [inbox];
      return;
    }
    state = all;
  }

  Future<Folder> create({String? parentFolderId, String name = 'New Folder'}) async {
    _userDirty = true;
    final folder = await FolderRepository.create(
      name: name,
      parentFolderId: parentFolderId,
      sortOrder: state.length,
    );
    state = [...state, folder];
    return folder;
  }

  Future<void> rename(String folderId, String newName) async {
    _userDirty = true;
    await FolderRepository.rename(folderId, newName);
    state = state
        .map((f) => f.id == folderId ? f.copyWith(name: newName, updatedAt: DateTime.now()) : f)
        .toList(growable: false);
  }

  Future<void> remove(String folderId) async {
    _userDirty = true;
    await FolderRepository.remove(folderId);
    state = state.where((f) => f.id != folderId).toList(growable: false);
    // Folders that previously parented to this one may have been promoted; reload to be safe.
    final reloaded = await FolderRepository.loadAll();
    state = reloaded;
  }

  Future<void> move(String folderId, String? newParentId) async {
    _userDirty = true;
    await FolderRepository.move(folderId: folderId, newParentId: newParentId);
    state = state
        .map((f) => f.id == folderId
            ? f.copyWith(
                parentFolderId: newParentId,
                clearParent: newParentId == null,
                updatedAt: DateTime.now(),
              )
            : f)
        .toList(growable: false);
  }
}

/// Folders that are direct children of [parentId] (null = root).
final childFoldersProvider = Provider.family<List<Folder>, String?>((ref, parentId) {
  final all = ref.watch(foldersProvider);
  return all.where((f) => f.parentFolderId == parentId).toList(growable: false);
});
