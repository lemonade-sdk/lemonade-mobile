import '../api/types/tool_definition.dart';

/// Canonical OmniRouter tool catalog. Mirrors `lemonade-sdk/lemonade`
/// `src/app/src/renderer/utils/toolDefinitions.json`. Bumping these is fine
/// — keep names stable, the `requires_labels` set is the contract with
/// Lemonade's model registry.
class OmniToolCatalog {
  static const String systemPromptTemplate =
      "Answer in clear, short sentences. Use a tool only when it fits the user's request. "
      "Otherwise, answer with text. After a tool call, answer the user.\n\n"
      "Tools:\n{tool_list}";

  static final List<ToolDefinition> all = [
    ToolDefinition(
      name: 'generate_image',
      description:
          'Make a new image when the user asks for one. Do not change an earlier image.',
      parameters: const {
        'type': 'object',
        'properties': {
          'image_prompt': {
            'type': 'string',
            'description': 'Describe the new image and its key details.',
          },
          'aspect_ratio': {
            'type': 'string',
            'enum': ['4:3', '1:1', '16:9', '9:16'],
            'description': 'Image shape. Use 4:3 by default.',
          },
          'style': {
            'type': 'string',
            'enum': ['photographic', 'anime', 'digital_art', 'sketch'],
            'description': 'Use the style the user asks for.',
          },
        },
        'required': ['image_prompt', 'aspect_ratio', 'style'],
      },
      requiresLabels: const ['image'],
    ),
    ToolDefinition(
      name: 'edit_image',
      description:
          'Change an existing image when the user asks. The app supplies the last image.',
      parameters: const {
        'type': 'object',
        'properties': {
          'prompt': {'type': 'string', 'description': 'Describe the change.'},
          'size': {
            'type': 'string',
            'description': 'Output size, such as 512x512.',
            'default': '512x512',
          },
        },
        'required': ['prompt'],
      },
      // Any-of semantics: prefer a dedicated 'edit' model, but image models
      // serve /v1/images/edits too. Requiring the rare 'edit' label alone
      // meant photo editing silently never activated on typical servers even
      // though the endpoint was fully wired up.
      requiresLabels: const ['edit', 'image'],
    ),
    ToolDefinition(
      name: 'text_to_speech',
      description: 'Speak text when the user asks to hear it.',
      parameters: const {
        'type': 'object',
        'properties': {
          'text_to_speak': {'type': 'string', 'description': 'Text to speak.'},
          'voice_profile': {
            'type': 'string',
            'enum': [
              'calm_female',
              'energetic_male',
              'professional_neutral',
              'storyteller',
            ],
            'description': 'Voice. Use professional_neutral by default.',
          },
        },
        'required': ['text_to_speak', 'voice_profile'],
      },
      requiresLabels: const ['tts', 'speech'],
    ),
    ToolDefinition(
      name: 'transcribe_audio',
      description:
          'Write the words from the audio file the user supplied. The app supplies the file.',
      parameters: const {
        'type': 'object',
        'properties': {
          'language': {
            'type': 'string',
            'description': 'Two-letter language code, such as en.',
            'default': 'en',
          },
        },
        'required': <String>[],
      },
      requiresLabels: const ['audio', 'transcription'],
    ),
    ToolDefinition(
      name: 'get_device_schedule',
      description:
          'Read calendar events and Lemonade activity for the user\'s day or schedule. '
          'Read 1 to 31 days. This tool does not change data.',
      parameters: const {
        'type': 'object',
        'properties': <String, dynamic>{
          'start_date': {
            'type': 'string',
            'description': 'First local date: YYYY-MM-DD. Omit for today.',
          },
          'days': {
            'type': 'integer',
            'minimum': 1,
            'maximum': 31,
            'default': 1,
            'description': 'Number of days to read.',
          },
          'include_calendar': {
            'type': 'boolean',
            'default': true,
            'description': 'Read calendar events.',
          },
          'include_app_activity': {
            'type': 'boolean',
            'default': true,
            'description': 'Read Lemonade chats and transcriptions.',
          },
        },
        'required': <String>[],
      },
      isAppControl: true,
    ),
    ToolDefinition(
      name: 'web_search',
      description:
          'Search the web for current facts, such as news or prices. Give source links in your answer.',
      parameters: const {
        'type': 'object',
        'properties': <String, dynamic>{
          'query': {'type': 'string', 'description': 'Search terms.'},
        },
        'required': <String>['query'],
      },
      isAppControl: true,
    ),
    ToolDefinition(
      name: 'find_places',
      description: 'Find a place, business, or address on a map.',
      parameters: const {
        'type': 'object',
        'properties': <String, dynamic>{
          'query': {
            'type': 'string',
            'description': 'Place, type of business, or address.',
          },
          'near': {
            'type': 'string',
            'description': 'Area to search near, if given.',
          },
        },
        'required': <String>['query'],
      },
      isAppControl: true,
    ),
    ToolDefinition(
      name: 'end_call',
      description:
          "End an active voice call when the user says goodbye or asks to stop. Do not use for 'thanks' alone.",
      parameters: const {
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
      },
      // App-control tool — no model gating; always advertised to the LLM.
      isAppControl: true,
    ),
    ToolDefinition(
      name: 'analyze_image',
      description:
          'Answer a question about an image in the chat. The app supplies the image.',
      parameters: const {
        'type': 'object',
        'properties': {
          'question': {
            'type': 'string',
            'description': 'Question about the image.',
          },
        },
        'required': ['question'],
      },
      requiresLlmLabels: const ['vision'],
    ),
  ];

  static ToolDefinition byName(String name) {
    return all.firstWhere((t) => t.name == name);
  }

  /// Build the system prompt with the actual tool list interpolated.
  static String buildSystemPrompt(Iterable<ToolDefinition> activeTools) {
    final list = activeTools
        .map((t) => '- ${t.name}: ${t.description}')
        .join('\n');
    return systemPromptTemplate.replaceFirst('{tool_list}', list);
  }
}
