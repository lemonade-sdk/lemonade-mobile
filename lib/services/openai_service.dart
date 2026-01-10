import 'dart:async';
import 'dart:convert';
import 'package:dart_openai/dart_openai.dart';
import 'package:http/http.dart' as http;
import 'package:lemonade_mobile/models/chat_message.dart';
import 'package:lemonade_mobile/models/server_config.dart';
import 'package:lemonade_mobile/utils/model_utils.dart';

class OpenaiService {
  final ServerConfig server;
  final Map<String, List<String>> _modelLabels = {};

  OpenaiService(this.server, {Map<String, List<String>>? modelLabels}) {
    // Initialize with provided labels if available
    if (modelLabels != null) {
      _modelLabels.addAll(modelLabels);
    }

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
    OpenAI.apiKey = server.apiKey ?? "lemonade";

    // Set longer timeout for image generation (10 minutes)
    OpenAI.requestsTimeOut = const Duration(minutes: 10);
  }

  Future<List<Map<String, dynamic>>> fetchModels() async {
    // Try direct HTTP request first to get labels
    try {
      String apiUrl = server.baseUrl;
      if (!apiUrl.endsWith('/v1')) {
        apiUrl = '${apiUrl}/v1';
      }
      final url = Uri.parse('$apiUrl/models');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${server.apiKey ?? "lemonade"}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = data['data'] as List<dynamic>? ?? [];

        _modelLabels.clear();
        final modelsData = <Map<String, dynamic>>[];
        for (final model in models) {
          final id = model['id'] as String?;
          final labels = (model['labels'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [];
          if (id != null) {
            _modelLabels[id] = labels;
            modelsData.add({'id': id, 'labels': labels});
          }
        }

        return modelsData;
      }
    } catch (e) {
      // Direct request failed, fall back to library method
    }

    // Fallback to original OpenAI library method
    try {
      final modelsResponse = await OpenAI.instance.model.list();
      final modelIds = modelsResponse.map((model) => model.id).toList();

      // For fallback, assume no labels
      _modelLabels.clear();
      final modelsData = <Map<String, dynamic>>[];
      for (final id in modelIds) {
        _modelLabels[id] = []; // No labels available
        modelsData.add({'id': id, 'labels': <String>[]});
      }

      return modelsData;
    } catch (e) {
      // Return empty list if all methods fail
      return [];
    }
  }

  Future<bool> testServer() async {
    try {
      // Try to fetch models as a connectivity test
      final models = await fetchModels();
      // Server is considered working only if we actually got some models
      return models.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Stream<String> streamChat(List<ChatMessage> messages, {String model = ''}) async* {
    // Create messages in the same format as JavaScript
    final chatMessages = <Map<String, dynamic>>[];

    for (final message in messages) {
      final messageContent = <Map<String, dynamic>>[];

      // Add text if present
      if (message.textContent.isNotEmpty) {
        messageContent.add({
          'type': 'text',
          'text': message.textContent,
        });
      }

      // Add images if present (supports multiple images like JavaScript)
      if (message.hasImages) {
        for (final imageContent in message.content.where((c) => c.type == MessageContentType.image)) {
          final imageData = imageContent.value;
          messageContent.add({
            'type': 'image_url',
            'image_url': {'url': imageData}, // Use full data URL like JavaScript
          });
        }
      }

      // Create message with content (string if single text, array if multiple items)
      final content = messageContent.length == 1 && messageContent[0]['type'] == 'text'
          ? messageContent[0]['text']
          : messageContent;

      chatMessages.add({
        'role': message.isUser ? 'user' : 'assistant',
        'content': content,
      });
    }

    final payload = {
      'model': model,
      'messages': chatMessages,
      'stream': true,
      'max_tokens': 1000,
    };

    // Handle base URL construction - some servers include /v1, some don't
    String apiUrl = server.baseUrl;
    if (!apiUrl.endsWith('/v1')) {
      apiUrl = '${apiUrl}/v1';
    }
    final url = Uri.parse('$apiUrl/chat/completions');
    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Bearer ${server.apiKey ?? "lemonade"}'
      ..body = jsonEncode(payload);

    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception('Request failed with status: ${response.statusCode}');
    }

    final stream = response.stream.transform(utf8.decoder).transform(LineSplitter());

    await for (final line in stream) {
      if (line.trim().isEmpty || !line.startsWith('data: ')) continue;

      final jsonStr = line.substring(6).trim();
      if (jsonStr == '[DONE]') break;

      try {
        final data = jsonDecode(jsonStr);
        final delta = data['choices']?[0]?['delta'];
        final content = delta?['content'];
        if (content != null && content is String && content.isNotEmpty) {
          yield content;
        }
      } catch (e) {
        // Skip malformed lines
        continue;
      }
    }
  }

  Future<String> sendChat(List<ChatMessage> messages, {String model = ''}) async {
    // Create messages in the same format as JavaScript
    final chatMessages = <Map<String, dynamic>>[];

    for (final message in messages) {
      final messageContent = <Map<String, dynamic>>[];

      // Add text if present
      if (message.textContent.isNotEmpty) {
        messageContent.add({
          'type': 'text',
          'text': message.textContent,
        });
      }

      // Add images if present (supports multiple images like JavaScript)
      if (message.hasImages) {
        for (final imageContent in message.content.where((c) => c.type == MessageContentType.image)) {
          final imageData = imageContent.value;
          messageContent.add({
            'type': 'image_url',
            'image_url': {'url': imageData}, // Use full data URL like JavaScript
          });
        }
      }

      // Create message with content (string if single text, array if multiple items)
      final content = messageContent.length == 1 && messageContent[0]['type'] == 'text'
          ? messageContent[0]['text']
          : messageContent;

      chatMessages.add({
        'role': message.isUser ? 'user' : 'assistant',
        'content': content,
      });
    }

    final payload = {
      'model': model,
      'messages': chatMessages,
      'stream': false,
      'max_tokens': 1000,
    };

    // Handle base URL construction - some servers include /v1, some don't
    String apiUrl = server.baseUrl;
    if (!apiUrl.endsWith('/v1')) {
      apiUrl = '${apiUrl}/v1';
    }
    final url = Uri.parse('$apiUrl/chat/completions');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${server.apiKey ?? "lemonade"}',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception('Request failed with status: ${response.statusCode}, body: ${response.body}');
    }

    final data = jsonDecode(response.body);
    final choices = data['choices'];
    if (choices != null && choices.isNotEmpty) {
      final message = choices[0]['message'];
      final content = message?['content'];
      if (content != null && content is String) {
        return content;
      }
    }

    return '';
  }

  Future<String?> generateImage(String prompt, {String model = '', int n = 1, String size = '512x512'}) async {
    try {
      // For llama.cpp and similar servers, image generation goes through chat completions
      // Use a special system prompt to instruct the model to generate images
      final chatMessages = [
        {
          'role': 'system',
          'content': "You are an AI that can generate images. When asked to generate an image, "
              "create a detailed description and then provide the image as base64 data. "
              "Format your response as: [DESCRIPTION] followed by base64 image data. "
              "The base64 data should start with 'data:image/png;base64,' or just be the raw base64."
        },
        {
          'role': 'user',
          'content': "Generate an image: $prompt"
        },
      ];

      print('Attempting image generation with model: $model, prompt: $prompt');

      final payload = {
        'model': model,
        'messages': chatMessages,
        'stream': false,
        'max_tokens': 2000, // Allow more tokens for image data
        'temperature': 0.8, // Add some creativity for image generation
      };

      // Handle base URL construction - some servers include /v1, some don't
      String apiUrl = server.baseUrl;
      if (!apiUrl.endsWith('/v1')) {
        apiUrl = '${apiUrl}/v1';
      }
      final url = Uri.parse('$apiUrl/chat/completions');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${server.apiKey ?? "lemonade"}',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(minutes: 4));

      if (response.statusCode != 200) {
        throw Exception('Image generation request failed with status: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final choices = data['choices'];
      if (choices != null && choices.isNotEmpty) {
        final message = choices[0]['message'];
        final responseText = message?['content'] ?? '';
        print('Image generation response: $responseText');

        // 1. JSON Check - look for JSON structure with image field
        try {
          final start = responseText.indexOf('{');
          final end = responseText.lastIndexOf('}');
          if (start != -1 && end != -1 && end > start) {
            final jsonStr = responseText.substring(start, end + 1);
            final jsonResponse = jsonDecode(jsonStr);
            if (jsonResponse['image'] != null) {
              print('Found base64 in JSON response');
              return jsonResponse['image'];
            }
          }
        } catch (_) {}

        // 2. Data URL Regex (strict pattern)
        final base64Regex = RegExp(r'data:image\/[a-zA-Z]+;base64,([a-zA-Z0-9+\/=]+)');
        final match = base64Regex.firstMatch(responseText);
        if (match != null) {
          print('Found base64 data URL');
          return match.group(0);
        }

        // 3. Raw Base64 Regex (optimized - look for continuous blocks)
        // Find base64 chars that are bounded by whitespace or string boundaries
        final rawBase64Regex = RegExp(r'(?:\s|^)([A-Za-z0-9+/=]{100,})(?:\s|$)');
        final rawMatch = rawBase64Regex.firstMatch(responseText);
        if (rawMatch != null) {
          final base64Data = rawMatch.group(1)!;
          // Additional validation: should be valid base64 length (multiple of 4)
          if (base64Data.length % 4 == 0) {
            print('Found raw base64 data');
            return base64Data;
          }
        }

        print('No base64 data found in response');
      } else {
        print('No content in response');
      }

      return null;
    } catch (e) {
      print('Image generation error: $e');
      // Re-throw the exception so the caller can handle specific error types
      rethrow;
    }
  }

  // Helper method to detect if a message is requesting image generation
  bool isImageGenerationRequest(String text) {
    final lowerText = text.toLowerCase();
    return lowerText.startsWith('/image') ||
           lowerText.startsWith('/draw');
  }

  // Helper method to detect if a model supports vision (similar to JavaScript isVisionModel)
  bool isVisionModel(String modelId) {
    final labels = _modelLabels[modelId] ?? [];
    return ModelUtils.isVisionModel(modelId, labels);
  }

  // Helper method to parse image size from prompt using command syntax
  (String, String) parseImagePrompt(String text) {
    String size = '512x512'; // Default size
    String cleanPrompt = text;

    // Check for command-style size specification: /image /small prompt or /draw /large prompt
    final commandRegex = RegExp(r'^/(image|draw)\s+/(small|medium|large)', caseSensitive: false);
    final match = commandRegex.firstMatch(text);

    if (match != null) {
      // Extract size from command
      final sizeCommand = match.group(2)!.toLowerCase();
      switch (sizeCommand) {
        case 'small':
          size = '256x256';
          break;
        case 'medium':
          size = '512x512';
          break;
        case 'large':
          size = '1024x1024';
          break;
      }

      // Remove the size command from prompt: /image /small red car -> red car
      cleanPrompt = text.replaceFirst(RegExp(r'^/(image|draw)\s+/(small|medium|large)\s*', caseSensitive: false), '').trim();
    } else {
      // No size command found, just remove the base command
      cleanPrompt = text.replaceAll(RegExp(r'^/(image|draw)\s*', caseSensitive: false), '').trim();
    }

    return (cleanPrompt, size);
  }
}
