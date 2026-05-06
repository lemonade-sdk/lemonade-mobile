import 'tool_call.dart';

/// Wire-format chat message. Distinct from the storage model (`lib/models/chat_message.dart`)
/// which has UI-shaped fields. Convert at the boundary.
enum WireRole { system, user, assistant, tool }

/// A piece of multi-modal user content. For assistant messages we typically use [ApiChatMessage.text].
class ApiContentPart {
  final String type; // 'text' | 'image_url' | 'input_audio'
  final String? text;
  final String? imageUrl; // data:image/...;base64,xxx OR https://...
  final String? audioBase64;
  final String? audioFormat; // 'wav' | 'mp3' | etc.

  const ApiContentPart._({
    required this.type,
    this.text,
    this.imageUrl,
    this.audioBase64,
    this.audioFormat,
  });

  const ApiContentPart.text(String text) : this._(type: 'text', text: text);
  const ApiContentPart.imageUrl(String url) : this._(type: 'image_url', imageUrl: url);
  const ApiContentPart.audio(String base64, {required String format})
      : this._(type: 'input_audio', audioBase64: base64, audioFormat: format);

  Map<String, dynamic> toWireJson() {
    switch (type) {
      case 'text':
        return {'type': 'text', 'text': text ?? ''};
      case 'image_url':
        return {
          'type': 'image_url',
          'image_url': {'url': imageUrl ?? ''},
        };
      case 'input_audio':
        return {
          'type': 'input_audio',
          'input_audio': {'data': audioBase64 ?? '', 'format': audioFormat ?? 'wav'},
        };
      default:
        return {'type': type};
    }
  }
}

class ApiChatMessage {
  final WireRole role;

  /// String content (for simple messages) or null when [contentParts] is set or when
  /// [toolCalls] carries the payload (assistant tool-call messages have content=null).
  final String? content;
  final List<ApiContentPart>? contentParts;
  final List<ToolCall>? toolCalls;
  final String? toolCallId; // required for role=tool messages
  final String? name; // optional, for tool/function naming

  const ApiChatMessage({
    required this.role,
    this.content,
    this.contentParts,
    this.toolCalls,
    this.toolCallId,
    this.name,
  });

  ApiChatMessage.system(String text) : this(role: WireRole.system, content: text);
  ApiChatMessage.user(String text) : this(role: WireRole.user, content: text);
  ApiChatMessage.userParts(List<ApiContentPart> parts)
      : this(role: WireRole.user, contentParts: parts);
  ApiChatMessage.assistant(String text) : this(role: WireRole.assistant, content: text);
  ApiChatMessage.assistantToolCalls(List<ToolCall> calls, {String? content})
      : this(role: WireRole.assistant, content: content, toolCalls: calls);
  ApiChatMessage.tool(String result, {required String toolCallId, String? name})
      : this(role: WireRole.tool, content: result, toolCallId: toolCallId, name: name);

  Map<String, dynamic> toWireJson() {
    final json = <String, dynamic>{'role': _roleString(role)};

    if (contentParts != null) {
      json['content'] = contentParts!.map((p) => p.toWireJson()).toList();
    } else {
      // Use null for assistant messages whose payload is in tool_calls.
      json['content'] = content;
    }

    if (toolCalls != null && toolCalls!.isNotEmpty) {
      json['tool_calls'] = toolCalls!.map((c) => c.toWireJson()).toList();
    }
    if (toolCallId != null) json['tool_call_id'] = toolCallId;
    if (name != null) json['name'] = name;

    return json;
  }

  static String _roleString(WireRole r) {
    switch (r) {
      case WireRole.system:
        return 'system';
      case WireRole.user:
        return 'user';
      case WireRole.assistant:
        return 'assistant';
      case WireRole.tool:
        return 'tool';
    }
  }

  static WireRole _parseRole(String s) {
    switch (s) {
      case 'system':
        return WireRole.system;
      case 'user':
        return WireRole.user;
      case 'assistant':
        return WireRole.assistant;
      case 'tool':
        return WireRole.tool;
      default:
        return WireRole.user;
    }
  }

  factory ApiChatMessage.fromJson(Map<String, dynamic> json) {
    final role = _parseRole(json['role'] as String? ?? 'user');
    final rawContent = json['content'];
    final rawToolCalls = json['tool_calls'];

    String? contentString;
    List<ApiContentPart>? parts;
    if (rawContent is String) {
      contentString = rawContent;
    } else if (rawContent is List) {
      // We don't currently round-trip parts back to the storage layer here;
      // this branch exists for completeness on assistant responses.
      parts = [];
    }

    final calls = rawToolCalls is List
        ? rawToolCalls
            .whereType<Map<String, dynamic>>()
            .map(ToolCall.fromJson)
            .toList()
        : null;

    return ApiChatMessage(
      role: role,
      content: contentString,
      contentParts: parts,
      toolCalls: calls,
      toolCallId: json['tool_call_id'] as String?,
      name: json['name'] as String?,
    );
  }
}
