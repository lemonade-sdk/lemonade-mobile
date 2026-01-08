import 'dart:convert';
import 'dart:typed_data';

enum MessageRole { user, assistant }

enum MessageContentType { text, image }

class MessageContent {
  final MessageContentType type;
  final String value; // For text: the text content, for image: base64 encoded image
  Uint8List? _cachedImageBytes; // Cached decoded image bytes for performance

  MessageContent({
    required this.type,
    required this.value,
  });

  // Get cached image bytes, decode if not cached
  Uint8List? getCachedImageBytes() {
    if (_cachedImageBytes != null) return _cachedImageBytes;

    if (type == MessageContentType.image && value.startsWith('data:image/')) {
      try {
        final parts = value.split(',');
        if (parts.length >= 2) {
          _cachedImageBytes = base64Decode(parts[1]);
          return _cachedImageBytes;
        }
      } catch (e) {
        // If decoding fails, return null
        return null;
      }
    }

    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'value': value,
      // Note: cachedImageBytes is not serialized as it's computed on demand
    };
  }

  factory MessageContent.fromJson(Map<String, dynamic> json) {
    return MessageContent(
      type: MessageContentType.values.firstWhere(
        (e) => e.name == json['type'],
      ),
      value: json['value'],
    );
  }
}

class ChatMessage {
  final MessageRole role;
  final List<MessageContent> content;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  // Convenience constructor for text-only messages
  ChatMessage.text({
    required this.role,
    required String text,
    DateTime? timestamp,
  }) : content = [MessageContent(type: MessageContentType.text, value: text)],
       timestamp = timestamp ?? DateTime.now();

  // Convenience constructor for image messages
  ChatMessage.image({
    required this.role,
    required String imageBase64,
    DateTime? timestamp,
  }) : content = [MessageContent(type: MessageContentType.image, value: imageBase64)],
       timestamp = timestamp ?? DateTime.now();

  // Get text content (for backward compatibility)
  String get textContent {
    return content.where((c) => c.type == MessageContentType.text).map((c) => c.value).join(' ');
  }

  // Get image content
  String? get imageContent {
    return content.where((c) => c.type == MessageContentType.image).map((c) => c.value).firstOrNull;
  }

  // Check if message has images
  bool get hasImages {
    return content.any((c) => c.type == MessageContentType.image);
  }

  Map<String, dynamic> toJson() {
    return {
      'role': role.name,
      'content': content.map((c) => c.toJson()).toList(),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // Handle legacy format (string content)
    if (json['content'] is String) {
      return ChatMessage(
        role: MessageRole.values.firstWhere(
          (e) => e.name == json['role'],
        ),
        content: [MessageContent(type: MessageContentType.text, value: json['content'])],
        timestamp: DateTime.parse(json['timestamp']),
      );
    }

    // Handle new format (list of content)
    return ChatMessage(
      role: MessageRole.values.firstWhere(
        (e) => e.name == json['role'],
      ),
      content: (json['content'] as List<dynamic>)
          .map((c) => MessageContent.fromJson(c as Map<String, dynamic>))
          .toList(),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
}
