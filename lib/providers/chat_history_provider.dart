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

final activeChatProvider =
    StateNotifierProvider<ActiveChatNotifier, ChatHistory?>(
  (ref) => ActiveChatNotifier(),
);

class ChatHistoryNotifier extends StateNotifier<List<ChatHistory>> {
  final _uuid = const Uuid();

  ChatHistoryNotifier() : super([]) {
    _loadChats();
  }

  Future<void> _loadChats() async {
    final chats = await ChatRepository.loadAll();

    if (chats.isEmpty) {
      state = const [];
      await createNewChat();
      return;
    }

    state = chats;

    final hasActive = chats.any((c) => c.isActive);
    if (!hasActive) await loadChat(chats.first.id);
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
    final activeIdx = state.indexWhere((c) => c.isActive);
    if (activeIdx == -1) return;

    final active = state[activeIdx];
    final updated = active.copyWith(
      messages: messages,
      title: title ?? active.title,
      lastUpdated: DateTime.now(),
    );

    state = [
      ...state.sublist(0, activeIdx),
      updated,
      ...state.sublist(activeIdx + 1),
    ];

    await ChatRepository.upsertChat(updated);
    await ChatRepository.replaceMessages(updated.id, messages);
  }

  Future<void> deleteChat(String chatId) async {
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

  ModelDefaults? getChatOverrides(String chatId) {
    try {
      final chat = state.firstWhere((c) => c.id == chatId);
      return chat.modelOverrides;
    } catch (_) {
      return null;
    }
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

class ActiveChatNotifier extends StateNotifier<ChatHistory?> {
  ActiveChatNotifier() : super(null);

  void setActiveChat(ChatHistory? chat) {
    state = chat;
  }
}
