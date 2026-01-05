import 'dart:async';
import 'package:dart_openai/dart_openai.dart';
import 'package:lemonade_mobile/models/chat_message.dart';
import 'package:lemonade_mobile/models/server_config.dart';

class OpenaiService {
  OpenaiService(ServerConfig server) {
    // OpenAI library automatically adds /v1, so remove it if present
    String baseUrl = server.baseUrl;
    if (baseUrl.endsWith('/v1')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 3);
      // Remove trailing slash if present after removing /v1
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
    }
    OpenAI.baseUrl = baseUrl;

    // Use provided API key or default to "lemonade" if none provided
    OpenAI.apiKey = server.apiKey ?? 'lemonade';
  }

  Future<List<String>> fetchModels() async {
    try {
      final modelsResponse = await OpenAI.instance.model.list();
      return modelsResponse.map((model) => model.id).toList();
    } catch (e) {
      // Return empty list if API call fails - no default models
      return [];
    }
  }

  Future<bool> testServer() async {
    try {
      // Try to fetch models as a simple connectivity test
      await OpenAI.instance.model.list();
      return true;
    } catch (e) {
      return false;
    }
  }

  Stream<String> streamChat(List<ChatMessage> messages, {String model = ''}) async* {
    final chatMessages = messages.map((message) {
      return OpenAIChatCompletionChoiceMessageModel(
        role: message.isUser
            ? OpenAIChatMessageRole.user
            : OpenAIChatMessageRole.assistant,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(message.content),
        ],
      );
    }).toList();

    final chatStream = OpenAI.instance.chat.createStream(
      model: model,
      messages: chatMessages,
      maxTokens: 1000,
    );

    await for (final response in chatStream) {
      final delta = response.choices.first.delta;
      final content = delta.content;
      if (content != null && content.isNotEmpty) {
        final firstContent = content.first;
        if (firstContent != null) {
          final text = firstContent.text;
          if (text != null && text.isNotEmpty) {
            yield text;
          }
        }
      }
    }
  }

  Future<String> sendChat(List<ChatMessage> messages, {String model = ''}) async {
    final chatMessages = messages.map((message) {
      return OpenAIChatCompletionChoiceMessageModel(
        role: message.isUser
            ? OpenAIChatMessageRole.user
            : OpenAIChatMessageRole.assistant,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(message.content),
        ],
      );
    }).toList();

    final response = await OpenAI.instance.chat.create(
      model: model,
      messages: chatMessages,
      maxTokens: 1000,
    );

    final content = response.choices.first.message.content;
    if (content != null && content.isNotEmpty) {
      return content.first.text ?? '';
    }
    return '';
  }
}
