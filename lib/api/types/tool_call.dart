/// OpenAI tool_call as it appears on assistant messages.
///
/// In streaming, `arguments` may arrive in fragments via `delta.tool_calls[].function.arguments`
/// and are concatenated by the [ToolCallAssembler]. By the time you receive a [ToolCall],
/// the arguments string is the complete JSON.
class ToolCall {
  final String id;
  final String name;
  final String argumentsJson;

  ToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  Map<String, dynamic> toWireJson() => {
        'id': id,
        'type': 'function',
        'function': {
          'name': name,
          'arguments': argumentsJson,
        },
      };

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    final fn = json['function'] as Map<String, dynamic>? ?? const {};
    return ToolCall(
      id: json['id'] as String? ?? '',
      name: fn['name'] as String? ?? '',
      argumentsJson: fn['arguments'] as String? ?? '{}',
    );
  }
}
