/// OpenAI function-calling tool schema.
class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  /// Component-model labels required for this tool's executor (e.g. ['image'], ['tts','speech']).
  /// Used by the capability resolver to decide whether to advertise the tool to the LLM.
  /// Null means the tool runs against the LLM itself (e.g. analyze_image).
  final List<String>? requiresLabels;

  /// LLM labels required for this tool (e.g. ['vision'] for analyze_image).
  /// Null means no LLM-side requirement.
  final List<String>? requiresLlmLabels;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    this.requiresLabels,
    this.requiresLlmLabels,
  });

  /// Wire format sent in `tools` field of chat completions request.
  Map<String, dynamic> toWireJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };

  factory ToolDefinition.fromCanonicalJson(Map<String, dynamic> entry) {
    final fn = entry['function'] as Map<String, dynamic>;
    final reqLabels = entry['requires_labels'];
    final reqLlmLabels = entry['requires_llm_labels'];
    return ToolDefinition(
      name: fn['name'] as String,
      description: fn['description'] as String? ?? '',
      parameters: (fn['parameters'] as Map?)?.cast<String, dynamic>() ?? {},
      requiresLabels: reqLabels is List ? reqLabels.whereType<String>().toList() : null,
      requiresLlmLabels:
          reqLlmLabels is List ? reqLlmLabels.whereType<String>().toList() : null,
    );
  }
}
