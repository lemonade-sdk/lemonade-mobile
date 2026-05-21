import '../api/types/tool_definition.dart';

/// Canonical OmniRouter tool catalog. Mirrors `lemonade-sdk/lemonade`
/// `src/app/src/renderer/utils/toolDefinitions.json`. Bumping these is fine
/// — keep names stable, the `requires_labels` set is the contract with
/// Lemonade's model registry.
class OmniToolCatalog {
  static const String systemPromptTemplate =
      "You are a helpful multimodal AI assistant with access to the following tools:\n\n"
      "{tool_list}\n\n"
      "When the user asks you to perform an action that matches one of these tools, use the appropriate tool. "
      "You may call multiple tools if the request requires it. After using a tool, describe what you did to the user "
      "in a brief, friendly response. If the user's request does not require any tool, respond normally with text.\n"
      "IMPORTANT: When an image has already been generated in this conversation and the user wants to add something, "
      "remove something, change, modify, or adjust the image in any way, you MUST use the edit_image tool — NOT generate_image. "
      "Only use generate_image for creating a brand new image from scratch. The edit_image tool automatically uses the most "
      "recent image as its source.\n"
      "When the user sends an image (as an image_url in their message), use the analyze_image tool to look at the image "
      "before responding about it.\n"
      "When you see '[User provided audio file #N]' in a message, it means the user sent audio data. "
      "Call the transcribe_audio tool to transcribe it — the audio data is handled automatically by the system.";

  static final List<ToolDefinition> all = [
    ToolDefinition(
      name: 'generate_image',
      description:
          'Generate a NEW image from scratch based on a text description. Use this ONLY when the user asks you to create '
          'an entirely new image. Do NOT use this to modify or change an existing image — use edit_image instead.',
      parameters: const {
        'type': 'object',
        'properties': {
          'image_prompt': {
            'type': 'string',
            'description':
                "A highly detailed, comma-separated visual description optimized for an image generator "
                "(e.g. 'cyberpunk city, neon lights, 4k, photorealistic'). Rewrite the user's request into "
                "this format — don't pass the raw user text.",
          },
          'aspect_ratio': {
            'type': 'string',
            'enum': ['1:1', '16:9', '9:16'],
            'description':
                "Aspect ratio. Use 9:16 for mobile wallpapers / portraits, 16:9 for landscapes / scenes, "
                "1:1 as the default.",
          },
          'style': {
            'type': 'string',
            'enum': ['photographic', 'anime', 'digital_art', 'sketch'],
            'description': "Visual style inferred from the user's text.",
          },
        },
        'required': ['image_prompt', 'aspect_ratio', 'style'],
      },
      requiresLabels: const ['image'],
    ),
    ToolDefinition(
      name: 'edit_image',
      description:
          'Edit or modify a previously generated image. Use this when the user wants to add, remove, change, modify, '
          'update, fix, or adjust anything in an existing image from this conversation. The most recently generated image '
          'is used automatically as the source. Always prefer this over generate_image when an image already exists in the '
          'conversation.',
      parameters: const {
        'type': 'object',
        'properties': {
          'prompt': {
            'type': 'string',
            'description': 'A description of the desired edit or modification to apply to the image',
          },
          'size': {
            'type': 'string',
            'description': "Output image size (e.g. '512x512', '1024x1024')",
            'default': '512x512',
          },
        },
        'required': ['prompt'],
      },
      requiresLabels: const ['edit'],
    ),
    ToolDefinition(
      name: 'text_to_speech',
      description:
          'Convert text to spoken audio. Use this when the user asks you to speak, say, read aloud, or convert text to speech.',
      parameters: const {
        'type': 'object',
        'properties': {
          'text_to_speak': {
            'type': 'string',
            'description': 'The exact text to be spoken.',
          },
          'voice_profile': {
            'type': 'string',
            'enum': [
              'calm_female',
              'energetic_male',
              'professional_neutral',
              'storyteller',
            ],
            'description':
                "Pick the voice that best matches the context. Use storyteller for narrative content, "
                "calm_female for soothing replies, energetic_male for upbeat content, professional_neutral as default.",
          },
        },
        'required': ['text_to_speak', 'voice_profile'],
      },
      requiresLabels: const ['tts', 'speech'],
    ),
    ToolDefinition(
      name: 'transcribe_audio',
      description:
          "Transcribe audio to text (speech-to-text). Use this when the user provides an audio file or when you see "
          "'[User provided audio file #N]' placeholders in the conversation. The audio data is automatically provided by "
          "the system — just call this tool with the language parameter.",
      parameters: const {
        'type': 'object',
        'properties': {
          'language': {
            'type': 'string',
            'description': "Language of the audio (ISO 639-1 code, e.g. 'en', 'es', 'fr')",
            'default': 'en',
          },
        },
        'required': <String>[],
      },
      requiresLabels: const ['audio', 'transcription'],
    ),
    ToolDefinition(
      name: 'analyze_image',
      description:
          'Analyze, describe, or answer questions about an image. Use this when the user shares an image and asks you '
          "to look at it, describe it, read text from it, identify objects, or answer any question about what's in the image.",
      parameters: const {
        'type': 'object',
        'properties': {
          'image_url': {
            'type': 'string',
            'description': 'The URL or base64 data URI of the image to analyze',
          },
          'question': {
            'type': 'string',
            'description': "The question to answer about the image, or 'describe' for a general description",
          },
        },
        'required': ['image_url', 'question'],
      },
      requiresLlmLabels: const ['vision'],
    ),
  ];

  static ToolDefinition byName(String name) {
    return all.firstWhere((t) => t.name == name);
  }

  /// Build the system prompt with the actual tool list interpolated.
  static String buildSystemPrompt(Iterable<ToolDefinition> activeTools) {
    final list = activeTools.map((t) => '- ${t.name}: ${t.description}').join('\n');
    return systemPromptTemplate.replaceFirst('{tool_list}', list);
  }
}
