import 'chat_message.dart';
import 'tool_call.dart';

/// Non-streaming response shape.
class ChatCompletion {
  final String id;
  final String model;
  final ApiChatMessage message;
  final String? finishReason; // 'stop' | 'tool_calls' | 'length' | null
  final ChatUsage? usage;

  ChatCompletion({
    required this.id,
    required this.model,
    required this.message,
    this.finishReason,
    this.usage,
  });

  factory ChatCompletion.fromJson(Map<String, dynamic> json) {
    final choices = json['choices'] as List? ?? const [];
    final first = choices.isNotEmpty ? choices.first as Map<String, dynamic> : <String, dynamic>{};
    final msgJson = first['message'] as Map<String, dynamic>? ?? const {};
    return ChatCompletion(
      id: json['id'] as String? ?? '',
      model: json['model'] as String? ?? '',
      message: ApiChatMessage.fromJson(msgJson),
      finishReason: first['finish_reason'] as String?,
      usage: json['usage'] is Map
          ? ChatUsage.fromJson((json['usage'] as Map).cast<String, dynamic>())
          : null,
    );
  }
}

class ChatUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  ChatUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  factory ChatUsage.fromJson(Map<String, dynamic> json) => ChatUsage(
        promptTokens: (json['prompt_tokens'] as num?)?.toInt() ?? 0,
        completionTokens: (json['completion_tokens'] as num?)?.toInt() ?? 0,
        totalTokens: (json['total_tokens'] as num?)?.toInt() ?? 0,
      );
}

/// Streaming chunk events emitted by [ChatEndpoint.stream].
sealed class ChatStreamEvent {
  const ChatStreamEvent();
}

/// Plain content token delta. May be empty string between role/finish events.
class ChatContentDelta extends ChatStreamEvent {
  final String text;
  const ChatContentDelta(this.text);
}

/// One or more tool_call deltas — already assembled per-slot. The [calls] list contains
/// tool calls that have NEWLY received their `id`+`name` on this chunk OR whose
/// arguments string just grew.
///
/// You typically don't act on this until [ChatStreamFinish] arrives — that's when the
/// arguments are guaranteed complete. Provided here for live progress UI.
class ChatToolCallDelta extends ChatStreamEvent {
  final List<PartialToolCall> partials;
  const ChatToolCallDelta(this.partials);
}

/// Stream is finished. Provides the fully-assembled final tool_calls (if any) and
/// the finish reason. Stream then ends.
class ChatStreamFinish extends ChatStreamEvent {
  final String? finishReason; // 'stop' | 'tool_calls' | 'length'
  final List<ToolCall> toolCalls; // assembled from indexed deltas
  final String contentSoFar;
  const ChatStreamFinish({
    required this.finishReason,
    required this.toolCalls,
    required this.contentSoFar,
  });
}

/// In-progress tool call as observed during streaming. Once [ChatStreamFinish]
/// arrives, the assembler emits the finalized [ToolCall] objects.
class PartialToolCall {
  final int index;
  final String? id;
  final String? name;
  final String argumentsAccum; // accumulated arguments string so far

  PartialToolCall({
    required this.index,
    this.id,
    this.name,
    required this.argumentsAccum,
  });
}
