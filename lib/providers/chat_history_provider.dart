import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:lemonade_mobile/models/chat_history.dart';
import 'package:lemonade_mobile/models/chat_message.dart';

final chatHistoryProvider = StateNotifierProvider<ChatHistoryNotifier, List<ChatHistory>>(
  (ref) => ChatHistoryNotifier(),
);

final activeChatProvider = StateNotifierProvider<ActiveChatNotifier, ChatHistory?>(
  (ref) => ActiveChatNotifier(),
);

class ChatHistoryNotifier extends StateNotifier<List<ChatHistory>> {
  static const String _chatsKey = 'chat_histories';
  final _uuid = const Uuid();

  ChatHistoryNotifier() : super([]) {
    _loadChats();
  }

  Future<void> _loadChats() async {
    final prefs = await SharedPreferences.getInstance();
    final chatsJson = prefs.getStringList(_chatsKey) ?? [];
    final chats = chatsJson
        .map((json) => ChatHistory.fromJson(jsonDecode(json)))
        .toList();

    // Sort by last updated (newest first)
    chats.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));

    state = chats;

    // If no chats, create a default one
    if (chats.isEmpty) {
      await createNewChat();
    } else {
      // Set the first chat as active if none is active
      final hasActive = chats.any((chat) => chat.isActive);
      if (!hasActive && chats.isNotEmpty) {
        await loadChat(chats.first.id);
      }
    }
  }

  Future<void> _saveChats() async {
    final prefs = await SharedPreferences.getInstance();
    final chatsJson = state.map((chat) => jsonEncode(chat.toJson())).toList();
    await prefs.setStringList(_chatsKey, chatsJson);
  }

  Future<void> createNewChat() async {
    final newChat = ChatHistory(
      id: _uuid.v4(),
      title: '',
      messages: [],
      isActive: true,
    );

    // Mark all other chats as inactive
    state = state.map((chat) => chat.copyWith(isActive: false)).toList();

    // Add new chat
    state = [newChat, ...state];

    await _saveChats();
  }

  Future<void> loadChat(String chatId) async {
    final updatedChats = state.map((chat) {
      if (chat.id == chatId) {
        return chat.copyWith(isActive: true);
      } else {
        return chat.copyWith(isActive: false);
      }
    }).toList();

    state = updatedChats;
    await _saveChats();
  }

  Future<void> updateActiveChat(List<ChatMessage> messages, {String? title}) async {
    final activeChatIndex = state.indexWhere((chat) => chat.isActive);
    if (activeChatIndex == -1) return;

    final activeChat = state[activeChatIndex];
    final updatedChat = activeChat.copyWith(
      messages: messages,
      title: title ?? activeChat.title,
      lastUpdated: DateTime.now(),
    );

    state = [
      ...state.sublist(0, activeChatIndex),
      updatedChat,
      ...state.sublist(activeChatIndex + 1),
    ];

    await _saveChats();
  }

  Future<void> deleteChat(String chatId) async {
    final wasActive = state.any((chat) => chat.id == chatId && chat.isActive);

    state = state.where((chat) => chat.id != chatId).toList();

    // If we deleted the active chat, create a new one or activate another
    if (wasActive) {
      if (state.isEmpty) {
        await createNewChat();
      } else {
        await loadChat(state.first.id);
      }
    }

    await _saveChats();
  }

  ChatHistory? getActiveChat() {
    try {
      return state.firstWhere((chat) => chat.isActive);
    } catch (e) {
      return null;
    }
  }
}

class ActiveChatNotifier extends StateNotifier<ChatHistory?> {
  ActiveChatNotifier() : super(null);

  void setActiveChat(ChatHistory? chat) {
    state = chat;
  }
}
