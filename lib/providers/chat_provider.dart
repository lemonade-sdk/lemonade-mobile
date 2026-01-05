import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/models/chat_message.dart';
import 'package:lemonade_mobile/services/openai_service.dart';
import 'package:lemonade_mobile/providers/servers_provider.dart';
import 'package:lemonade_mobile/providers/chat_history_provider.dart';
import 'package:lemonade_mobile/providers/models_provider.dart';

// Active chat messages provider
final chatProvider = StateNotifierProvider<ChatNotifier, List<ChatMessage>>(
  (ref) => ChatNotifier(ref),
);

class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref ref;

  ChatNotifier(this.ref) : super([]) {
    // Update messages when active chat changes
    ref.listen(chatHistoryProvider, (_, __) => _updateMessagesFromActiveChat());
    _updateMessagesFromActiveChat();
  }

  void _updateMessagesFromActiveChat() {
    final activeChat = ref.read(chatHistoryProvider.notifier).getActiveChat();
    state = activeChat?.messages ?? [];
  }

  Future<void> sendMessage(String message) async {
    final selectedServer = ref.read(selectedServerProvider);
    if (selectedServer == null) {
      // Add error message directly to chat history
      final errorMessage = ChatMessage(
        role: MessageRole.assistant,
        content: 'No server selected. Please select a server in settings.',
      );
      final updatedMessages = [...state, errorMessage];
      await ref.read(chatHistoryProvider.notifier).updateActiveChat(updatedMessages);
      return;
    }

    final selectedModel = ref.read(selectedModelProvider) ?? 'gpt-3.5-turbo';

    final userMessage = ChatMessage(role: MessageRole.user, content: message);
    final updatedMessages = [...state, userMessage];

    // Update chat history immediately with user message
    await ref.read(chatHistoryProvider.notifier).updateActiveChat(updatedMessages);

    // Add placeholder for assistant message
    final assistantMessage = ChatMessage(role: MessageRole.assistant, content: '');
    final messagesWithPlaceholder = [...updatedMessages, assistantMessage];
    await ref.read(chatHistoryProvider.notifier).updateActiveChat(messagesWithPlaceholder);

    try {
      final openaiService = OpenaiService(selectedServer);
      final stream = openaiService.streamChat(updatedMessages, model: selectedModel);

      String accumulatedResponse = '';

      await for (final chunk in stream) {
        accumulatedResponse += chunk;

        final lastMessage = messagesWithPlaceholder.last;
        if (lastMessage.role == MessageRole.assistant) {
          final updatedAssistantMessage = ChatMessage(
            role: MessageRole.assistant,
            content: accumulatedResponse,
            timestamp: lastMessage.timestamp,
          );

          final finalMessages = [
            ...messagesWithPlaceholder.sublist(0, messagesWithPlaceholder.length - 1),
            updatedAssistantMessage,
          ];

          await ref.read(chatHistoryProvider.notifier).updateActiveChat(finalMessages);
        }
      }
    } catch (e) {
      // Replace last message with error
      final errorMessage = ChatMessage(
        role: MessageRole.assistant,
        content: 'Error: ${e.toString()}',
        timestamp: DateTime.now(),
      );

      final finalMessages = [
        ...messagesWithPlaceholder.sublist(0, messagesWithPlaceholder.length - 1),
        errorMessage,
      ];

      await ref.read(chatHistoryProvider.notifier).updateActiveChat(finalMessages);
    }
  }

  void clearChat() {
    ref.read(chatHistoryProvider.notifier).updateActiveChat([]);
  }
}
