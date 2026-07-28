import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_history.dart';
import '../models/chat_message.dart';
import '../models/model_defaults.dart';
import '../storage/chat_repository.dart';

final chatHistoryProvider =
    StateNotifierProvider<ChatHistoryNotifier, List<ChatHistory>>(
  (ref) => ChatHistoryNotifier(),
);

/// The chat currently marked [ChatHistory.isActive]. Derived from the list —
/// never a separately-written state that can drift out of sync (the old
/// [ActiveChatNotifier] was never updated by any call site).
final activeChatProvider = Provider<ChatHistory?>((ref) {
  final chats = ref.watch(chatHistoryProvider);
  for (final c in chats) {
    if (c.isActive) return c;
  }
  return null;
});

class ChatHistoryNotifier extends StateNotifier<List<ChatHistory>> {
  final _uuid = const Uuid();

  /// True once the cold-start disk load has resolved. Deletes that happen
  /// before then are remembered so the loaded snapshot can't resurrect them.
  bool _loadCompleted = false;
  final Set<String> _preLoadDeleted = <String>{};

  ChatHistoryNotifier() : super([]) {
    _loadChats();
  }

  /// Fire-and-forget from the constructor — must never throw, and must leave
  /// the app with a usable (created + activated) chat even when storage is
  /// broken.
  Future<void> _loadChats() async {
    var loaded = const <ChatHistory>[];
    try {
      loaded = await ChatRepository.loadAll();
    } catch (e, st) {
      debugPrint('Chat history load failed — continuing with in-memory state: $e\n$st');
    }

    // Merge with anything already in state: chats created or mutated while
    // the disk load was in flight win over the (older) disk snapshot.
    final inMemory = state;
    final inMemoryIds = {for (final c in inMemory) c.id};
    final hasInMemoryActive = inMemory.any((c) => c.isActive);
    final merged = [
      ...inMemory,
      for (final c in loaded)
        if (!inMemoryIds.contains(c.id) && !_preLoadDeleted.contains(c.id))
          hasInMemoryActive ? c.copyWith(isActive: false) : c,
    ];
    _loadCompleted = true;
    _preLoadDeleted.clear();

    try {
      if (merged.isEmpty) {
        state = const [];
        await createNewChat();
        return;
      }

      state = merged;

      final hasActive = merged.any((c) => c.isActive);
      if (!hasActive) await loadChat(merged.first.id);
    } catch (e, st) {
      debugPrint('Chat history init failed: $e\n$st');
      if (state.isEmpty) {
        // Last resort: an in-memory-only chat so the UI still works.
        state = [
          ChatHistory(id: _uuid.v4(), title: '', messages: [], isActive: true),
        ];
      }
    }
  }

  Future<void> createNewChat({String? folderId}) async {
    final newChat = ChatHistory(
      id: _uuid.v4(),
      title: '',
      messages: [],
      isActive: true,
      folderId: folderId,
    );

    state = [
      newChat,
      ...state.map((c) => c.copyWith(isActive: false)),
    ];

    await ChatRepository.upsertChat(newChat);
    await ChatRepository.setActive(newChat.id);
  }

  Future<void> moveChatToFolder(String chatId, String? folderId) async {
    final idx = state.indexWhere((c) => c.id == chatId);
    if (idx == -1) return;
    final chat = state[idx];
    final updated = chat.copyWith(
      folderId: folderId,
      clearFolder: folderId == null,
      lastUpdated: DateTime.now(),
    );
    state = [
      ...state.sublist(0, idx),
      updated,
      ...state.sublist(idx + 1),
    ];
    await ChatRepository.upsertChat(updated);
  }

  Future<void> loadChat(String chatId) async {
    state = state
        .map((c) => c.copyWith(isActive: c.id == chatId))
        .toList(growable: false);
    await ChatRepository.setActive(chatId);
  }

  Future<void> updateActiveChat(List<ChatMessage> messages, {String? title}) async {
    final active = getActiveChat();
    if (active == null) return;
    await updateChat(active.id, messages, title: title);
  }

  /// Replace the message list of the chat with [uuid] — wherever it lives in
  /// state, NOT whichever chat happens to be active right now. Streaming turns
  /// key every write off the uuid captured at turn start so switching or
  /// deleting chats mid-stream can't clobber another chat's log.
  ///
  /// Returns false (and writes nothing) when the chat no longer exists.
  Future<bool> updateChat(String uuid, List<ChatMessage> messages, {String? title}) async {
    if (!updateChatInMemory(uuid, messages, title: title)) return false;
    await persistChat(uuid);
    return true;
  }

  /// In-memory-only variant of [updateChat] for per-token streaming updates;
  /// callers debounce [persistChat] separately. Returns false when the chat
  /// no longer exists (deleted mid-turn) — the caller must drop the turn.
  bool updateChatInMemory(String uuid, List<ChatMessage> messages, {String? title}) {
    final idx = state.indexWhere((c) => c.id == uuid);
    if (idx == -1) return false;

    final chat = state[idx];
    final updated = chat.copyWith(
      messages: messages,
      title: title ?? chat.title,
      lastUpdated: DateTime.now(),
    );

    state = [
      ...state.sublist(0, idx),
      updated,
      ...state.sublist(idx + 1),
    ];
    return true;
  }

  /// Persist the current in-memory snapshot of chat [uuid]. Update-only: a
  /// chat deleted while this write waited on the Isar lock is never
  /// re-inserted (see ChatRepository).
  Future<void> persistChat(String uuid) async {
    final idx = state.indexWhere((c) => c.id == uuid);
    if (idx == -1) return; // deleted — drop the write
    final chat = state[idx];
    await ChatRepository.upsertChat(chat, updateOnly: true);
    await ChatRepository.replaceMessages(chat.id, chat.messages);
  }

  Future<void> deleteChat(String chatId) async {
    if (!_loadCompleted) _preLoadDeleted.add(chatId);
    final wasActive = state.any((c) => c.id == chatId && c.isActive);
    state = state.where((c) => c.id != chatId).toList(growable: false);

    await ChatRepository.deleteChat(chatId);

    if (wasActive) {
      if (state.isEmpty) {
        await createNewChat();
      } else {
        await loadChat(state.first.id);
      }
    }
  }

  ChatHistory? getActiveChat() {
    try {
      return state.firstWhere((c) => c.isActive);
    } catch (_) {
      return null;
    }
  }

  /// The chat with [chatId], or null if it no longer exists.
  ChatHistory? getChatById(String chatId) {
    try {
      return state.firstWhere((c) => c.id == chatId);
    } catch (_) {
      return null;
    }
  }

  ModelDefaults? getChatOverrides(String chatId) => getChatById(chatId)?.modelOverrides;

  /// Set a chat's title (persisted). Only touches the title — does not rewrite
  /// the message list. Used by AI auto-titling after the first exchange.
  Future<void> updateChatTitle(String chatId, String title) async {
    final idx = state.indexWhere((c) => c.id == chatId);
    if (idx == -1) return;

    final chat = state[idx];
    final updated = chat.copyWith(title: title, lastUpdated: DateTime.now());

    state = [
      ...state.sublist(0, idx),
      updated,
      ...state.sublist(idx + 1),
    ];

    await ChatRepository.upsertChat(updated);
  }

  Future<void> updateChatOverrides(String chatId, ModelDefaults? overrides) async {
    final idx = state.indexWhere((c) => c.id == chatId);
    if (idx == -1) return;

    final chat = state[idx];
    final updated = chat.copyWith(
      modelOverrides: overrides,
      clearModelOverrides: overrides == null,
      lastUpdated: DateTime.now(),
    );

    state = [
      ...state.sublist(0, idx),
      updated,
      ...state.sublist(idx + 1),
    ];

    await ChatRepository.upsertChat(updated);
  }
}
