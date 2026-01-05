import 'package:lemonade_mobile/models/chat_message.dart';

class ChatHistory {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime lastUpdated;
  final bool isActive;

  ChatHistory({
    required this.id,
    required this.title,
    required this.messages,
    DateTime? createdAt,
    DateTime? lastUpdated,
    this.isActive = false,
  }) :
    createdAt = createdAt ?? DateTime.now(),
    lastUpdated = lastUpdated ?? DateTime.now();

  String get displayTitle {
    if (title.isNotEmpty) return title;
    if (messages.isNotEmpty) {
      final firstMessage = messages.first;
      return firstMessage.content.length > 50
          ? '${firstMessage.content.substring(0, 50)}...'
          : firstMessage.content;
    }
    return 'New Chat';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'messages': messages.map((msg) => msg.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'lastUpdated': lastUpdated.toIso8601String(),
      'isActive': isActive,
    };
  }

  factory ChatHistory.fromJson(Map<String, dynamic> json) {
    return ChatHistory(
      id: json['id'],
      title: json['title'],
      messages: (json['messages'] as List)
          .map((msg) => ChatMessage.fromJson(msg))
          .toList(),
      createdAt: DateTime.parse(json['createdAt']),
      lastUpdated: DateTime.parse(json['lastUpdated']),
      isActive: json['isActive'] ?? false,
    );
  }

  ChatHistory copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? lastUpdated,
    bool? isActive,
  }) {
    return ChatHistory(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isActive: isActive ?? this.isActive,
    );
  }
}
