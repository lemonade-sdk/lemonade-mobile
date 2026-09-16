import 'chat_message.dart';
import '../../models/thinking_level.dart';
import 'tool_definition.dart';

class ChatCompletionRequest {
  final String model;
  final List<ApiChatMessage> messages;
  final List<ToolDefinition>? tools;
  final bool stream;

  // Standard sampling params (all optional).
  final double? temperature;
  final double? topP;
  final int? topK;
  final double? repeatPenalty;
  final int? maxCompletionTokens;
  final List<String>? stop;

  // Lemonade / vLLM chat-template extension.
  final ThinkingLevel? thinkingLevel;

  /// Free-form additional fields (e.g. provider-specific extensions). Merged into the body last,
  /// so they override anything we set above. Use sparingly.
  final Map<String, dynamic>? extra;

  ChatCompletionRequest({
    required this.model,
    required this.messages,
    this.tools,
    this.stream = false,
    this.temperature,
    this.topP,
    this.topK,
    this.repeatPenalty,
    this.maxCompletionTokens,
    this.stop,
    this.thinkingLevel,
    this.extra,
  });

  Map<String, dynamic> toWireJson() {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages.map((m) => m.toWireJson()).toList(),
      'stream': stream,
    };
    if (tools != null && tools!.isNotEmpty) {
      body['tools'] = tools!.map((t) => t.toWireJson()).toList();
    }
    if (temperature != null) body['temperature'] = temperature;
    if (topP != null) body['top_p'] = topP;
    if (topK != null) body['top_k'] = topK;
    if (repeatPenalty != null) body['repeat_penalty'] = repeatPenalty;
    if (maxCompletionTokens != null) {
      body['max_completion_tokens'] = maxCompletionTokens;
    }
    if (stop != null && stop!.isNotEmpty) body['stop'] = stop;
    if (thinkingLevel != null) {
      final templateArgs = <String, dynamic>{
        'enable_thinking': thinkingLevel != ThinkingLevel.off,
      };
      if (thinkingLevel != ThinkingLevel.off) {
        templateArgs['reasoning_effort'] = thinkingLevel!.wire;
      }
      body['chat_template_kwargs'] = templateArgs;
    }
    if (extra != null) body.addAll(extra!);
    return body;
  }
}
