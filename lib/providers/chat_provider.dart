import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:lemonade_mobile/models/chat_message.dart';
import 'package:lemonade_mobile/services/openai_service.dart';
import 'package:lemonade_mobile/providers/servers_provider.dart';
import 'package:lemonade_mobile/providers/chat_history_provider.dart';
import 'package:lemonade_mobile/providers/models_provider.dart';
import 'package:lemonade_mobile/constants/messages.dart';

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
  Future<void> sendMessage(String message, {List<String>? imagePaths, ScrollController? scrollController}) async {
    final selectedServer = ref.read(selectedServerProvider);
    if (selectedServer == null) {
      // Add error message directly to chat history
      final errorMessage = ChatMessage.text(
        role: MessageRole.assistant,
        text: AppMessages.noServerSelected,
      );
      final updatedMessages = [...state, errorMessage];
      await ref.read(chatHistoryProvider.notifier).updateActiveChat(updatedMessages);
      return;
    }

    // Ensure selected model is loaded from preferences
    final selectedModelNotifier = ref.read(selectedModelProvider.notifier);
    String selectedModel = selectedModelNotifier.state ?? '';

    // If model is not loaded yet, wait for it
    if (selectedModel.isEmpty) {
      // Wait a short time for async loading to complete
      await Future.delayed(const Duration(milliseconds: 100));
      selectedModel = selectedModelNotifier.state ?? '';
      print('Selected model after delay: $selectedModel');
    }

    // Check if trying to send images to non-vision model (moved to service layer like JavaScript)
    final openaiService = OpenaiService(selectedServer);
    if ((imagePaths != null && imagePaths.isNotEmpty) && !openaiService.isVisionModel(selectedModel)) {
      final errorMessage = ChatMessage.text(
        role: MessageRole.assistant,
        text: 'Cannot send images to model "$selectedModel" as it does not support vision. Please load a model with "Vision" capabilities or remove the attached images.',
      );
      final updatedMessages = [...state, errorMessage];
      await ref.read(chatHistoryProvider.notifier).updateActiveChat(updatedMessages);
      return;
    }

    // Create user message with text and/or images
    final messageContent = <MessageContent>[];

    // Add text if present
    if (message.isNotEmpty) {
      messageContent.add(MessageContent(type: MessageContentType.text, value: message));
    }

    // Add images if present (already converted to data URLs in chat input)
    if (imagePaths != null) {
      for (final imageData in imagePaths) {
        messageContent.add(MessageContent(
          type: MessageContentType.image,
          value: imageData, // Already a data URL like 'data:image/jpeg;base64,...'
        ));
      }
    }

    final userMessage = ChatMessage(
      role: MessageRole.user,
      content: messageContent,
    );
    final updatedMessages = [...state, userMessage];

    // Update chat history immediately with user message
    await ref.read(chatHistoryProvider.notifier).updateActiveChat(updatedMessages);

    // Scroll to bottom to show the user's message
    if (scrollController != null && scrollController!.hasClients) {
      scrollController!.animateTo(
        scrollController!.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    // Add placeholder for assistant message
    final assistantMessage = ChatMessage.text(role: MessageRole.assistant, text: '');
    final messagesWithPlaceholder = [...updatedMessages, assistantMessage];
    await ref.read(chatHistoryProvider.notifier).updateActiveChat(messagesWithPlaceholder);

    try {
      final openaiService = OpenaiService(selectedServer);

      // Check if this is an image generation request
      if (openaiService.isImageGenerationRequest(message)) {
        print('Image generation request detected: $message');

        // Parse size from prompt
        final (cleanPrompt, imageSize) = openaiService.parseImagePrompt(message);
        print('Parsed prompt: "$cleanPrompt", size: $imageSize');

        // Try to generate an image
        String? imageBase64;
        Object? imageGenerationError;
        try {
          imageBase64 = await openaiService.generateImage(cleanPrompt, model: selectedModel, size: imageSize);
        } catch (e) {
          // Handle specific error types
          print('Image generation exception: $e');
          imageGenerationError = e;
          imageBase64 = null; // Ensure it's null so we fall through to error handling
        }

        if (imageBase64 != null) {
          print('Image generation succeeded, creating image message');
          // Create assistant message with generated image
          final imageMessage = ChatMessage(
            role: MessageRole.assistant,
            content: [
              MessageContent(type: MessageContentType.image, value: imageBase64),
            ],
          );
          final finalMessages = [
            ...messagesWithPlaceholder.sublist(
                0, messagesWithPlaceholder.length - 1),
            imageMessage,
          ];
          await ref.read(chatHistoryProvider.notifier).updateActiveChat(
              finalMessages);
          return;
        } else {
          print('Image generation failed, falling back to text chat');
          // Check model capabilities for better error messages
          String errorText;
          if (selectedModel.isEmpty) {
            errorText = AppMessages.noModelSelectedForImage;
          } else {
            // Ensure models are loaded before checking capabilities
            final availableModels = ref.read(modelsProvider);
            if (availableModels.isEmpty) {
              // Models not loaded yet, fetch them
              await ref.read(modelsProvider.notifier).fetchModels();
              // Re-read after fetching
              final updatedModels = ref.read(modelsProvider);
              final selectedModelNotifier = ref.read(selectedModelProvider.notifier);

              if (!selectedModelNotifier.isModelSelectedAndAvailable(updatedModels)) {
                errorText = AppMessages.noModelSelectedForImage;
              } else {
                errorText = _getImageGenerationErrorMessage(updatedModels, selectedModel, imageGenerationError);
              }
            } else {
              // Models are loaded, check normally
              final selectedModelNotifier = ref.read(selectedModelProvider.notifier);
              if (!selectedModelNotifier.isModelSelectedAndAvailable(availableModels)) {
                errorText = AppMessages.noModelSelectedForImage;
              } else {
                errorText = _getImageGenerationErrorMessage(availableModels, selectedModel, imageGenerationError);
              }
            }
          }
          final errorMessage = ChatMessage.text(
            role: MessageRole.assistant,
            text: errorText,
          );
          final finalMessages = [
            ...messagesWithPlaceholder.sublist(
                0, messagesWithPlaceholder.length - 1),
            errorMessage,
          ];
          await ref.read(chatHistoryProvider.notifier).updateActiveChat(finalMessages);
          return;
        }
      }

      final stream = openaiService.streamChat(updatedMessages, model: selectedModel);

      String accumulatedResponse = '';

      // Auto-scroll during streaming response
      void scrollToBottom() {
        if (scrollController != null && scrollController!.hasClients) {
          scrollController!.animateTo(
            scrollController!.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }

      await for (final chunk in stream) {
        accumulatedResponse += chunk;

        final lastMessage = messagesWithPlaceholder.last;
        if (lastMessage.role == MessageRole.assistant) {
          final updatedAssistantMessage = ChatMessage.text(
            role: MessageRole.assistant,
            text: accumulatedResponse,
            timestamp: lastMessage.timestamp,
          );

          final finalMessages = [
            ...messagesWithPlaceholder.sublist(0, messagesWithPlaceholder.length - 1),
            updatedAssistantMessage,
          ];

          await ref.read(chatHistoryProvider.notifier).updateActiveChat(finalMessages);

          // Auto-scroll to show new text as it arrives
          scrollToBottom();
        }
      }
    } catch (e) {
      // Replace last message with error
      String errorText;
      if (e.toString().contains("Model '' was not found") || e.toString().contains("model") && e.toString().contains("not found")) {
        errorText = AppMessages.noModelSelected;
      } else {
        errorText = AppMessages.genericError(e.toString());
      }

      final errorMessage = ChatMessage.text(
        role: MessageRole.assistant,
        text: errorText,
        timestamp: DateTime.now(),
      );

      final finalMessages = [
        ...messagesWithPlaceholder.sublist(0, messagesWithPlaceholder.length - 1),
        errorMessage,
      ];

      await ref.read(chatHistoryProvider.notifier).updateActiveChat(finalMessages);
    }
  }

  String _getImageGenerationErrorMessage(List<ModelInfo> availableModels, String selectedModel, Object? error) {
    // Check for specific error types first
    if (error != null) {
      if (error is TimeoutException) {
        return AppMessages.imageGenerationTimeout;
      }
    }

    final selectedModelInfo = availableModels.firstWhere(
      (model) => model.id == selectedModel,
      orElse: () => ModelInfo(selectedModel),
    );

    if (selectedModelInfo.capabilities == ModelCapabilities.textOnly) {
      return AppMessages.textOnlyModelError(selectedModel);
    } else if (selectedModelInfo.capabilities == ModelCapabilities.vision) {
      return AppMessages.visionModelServerError(selectedModel);
    } else {
      return AppMessages.imageGenerationServerError(selectedModel);
    }
  }

  void clearChat() {
    ref.read(chatHistoryProvider.notifier).updateActiveChat([]);
  }
}
