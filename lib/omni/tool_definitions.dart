import '../api/types/tool_definition.dart';

/// Canonical OmniRouter tool catalog. Mirrors `lemonade-sdk/lemonade`
/// `src/app/src/renderer/utils/toolDefinitions.json`. Bumping these is fine
/// — keep names stable, the `requires_labels` set is the contract with
/// Lemonade's model registry.
class OmniToolCatalog {
  static const String systemPromptTemplate =
      "You are a helpful multimodal AI assistant. Your DEFAULT mode is normal text (or spoken) "
      "conversation — answer questions, chat, explain, describe. You only call a tool when the user "
      "EXPLICITLY asks for the action that tool performs. If the user is just talking, asking a question, "
      "or describing something, REPLY WITH TEXT — do not invoke any tool.\n\n"
      "Available tools:\n\n"
      "{tool_list}\n\n"
      "Rules for tool use:\n"
      "  - generate_image / edit_image: ONLY when the user explicitly asks to make or change an image. "
      "Words like 'draw / make a picture of / show me an image of / create an image / generate an image' "
      "trigger generate_image. Words like 'add / remove / change / edit / modify / fix / make it …' on the "
      "existing image trigger edit_image. Otherwise, do not produce an image.\n"
      "  - text_to_speech: only when the user explicitly asks you to say/read/speak something aloud.\n"
      "  - transcribe_audio: only when the user provides an audio file or you see "
      "'[User provided audio file #N]' in their message.\n"
      "  - analyze_image: only when the user provides an image (image_url part) and asks about it.\n"
      "  - web_search: only when the user asks about current/changing information you "
      "may not know (news, prices, schedules, opening hours, sports scores, recent "
      "releases). Do NOT use it for definitions, math, or general explanations.\n"
      "  - find_places: only when the user asks for a place, business, restaurant, "
      "landmark, or address. You can call both find_places AND web_search in the "
      "same turn if the user asks something like 'find a pizza place near me and "
      "tell me the best one' — they will run in parallel.\n"
      "After using any tool, give a short friendly text reply describing what you did. "
      "When in doubt, just talk back — do not invoke any tool.";

  static final List<ToolDefinition> all = [
    ToolDefinition(
      name: 'generate_image',
      description:
          'Create a brand-new picture. ONLY call this when the user EXPLICITLY asks for an image with words like '
          '"make/draw/show me/create/generate/picture/photo/image of X". Examples that REQUIRE this tool: '
          '"make me a picture of a sunset", "draw a cat", "show me what a robot dog looks like", '
          '"generate an image of a woman and child". '
          'If the user is just chatting, asking questions, or describing things WITHOUT explicitly asking '
          'for an image to be made, DO NOT call this tool — reply with text instead. '
          'When the user names a new subject (different from any prior image), this is generate_image with a '
          'fresh random seed — not edit_image.',
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
            'enum': ['4:3', '1:1', '16:9', '9:16'],
            'description':
                "Aspect ratio. Use 4:3 as the default for general photos and scenes; "
                "1:1 for product / portrait close-ups; 16:9 for wide landscapes; "
                "9:16 for mobile wallpapers / vertical portraits.",
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
          'Modify the EXISTING image. ONLY call this when the user EXPLICITLY asks to change/update/edit '
          'the image already shown, with words like "add/remove/change/update/edit/modify/fix/adjust/make it/keep '
          'but…". The subject of the image stays the same; only details change. Examples that REQUIRE this tool: '
          '"add a hat to her", "make it brighter", "remove the background", "change the dress to blue", '
          '"edit the image to include a child". '
          'Do NOT call this when the user names a different subject — that is generate_image. '
          'Do NOT call this for general chat. The most recently generated OR user-uploaded image is used '
          'automatically as the source — do not pass an image_url. This works on photos the user uploads into '
          'the chat, not just images you generated.',
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
      name: 'web_search',
      description:
          'Search the live web for up-to-date information. Use this when the '
          'user asks about news, current events, prices, schedules, sports '
          'scores, opening hours, product reviews, or anything that may have '
          'changed after your training data. The tool returns the top web '
          'results with titles, URLs, and snippets — summarize them in your '
          'reply and cite the URLs. Do NOT call this for things you already '
          'know (definitions, general explanations, math).',
      parameters: const {
        'type': 'object',
        'properties': <String, dynamic>{
          'query': {
            'type': 'string',
            'description':
                'A clear, specific search query in natural language, e.g. '
                '"weather in Seattle tomorrow" or "latest iPhone 17 release date".',
          },
        },
        'required': <String>['query'],
      },
      isAppControl: true,
    ),
    ToolDefinition(
      name: 'find_places',
      description:
          'Look up places, businesses, addresses, or points of interest on a '
          'map. Use this when the user asks for restaurants, shops, '
          'landmarks, or addresses — anything that has a physical location. '
          'Returns name, full address, and (when available) coordinates and '
          'category. Can optionally bias by a "near" location.',
      parameters: const {
        'type': 'object',
        'properties': <String, dynamic>{
          'query': {
            'type': 'string',
            'description':
                'What to look for, e.g. "pizza", "coffee shop", "Eiffel Tower", '
                '"123 Main St". Use English unless the user specifically used '
                'another language.',
          },
          'near': {
            'type': 'string',
            'description':
                'Optional location to bias results toward, e.g. "Seattle, WA" '
                'or "my current location". Leave empty if the user gave an '
                'absolute place name.',
          },
        },
        'required': <String>['query'],
      },
      isAppControl: true,
    ),
    ToolDefinition(
      name: 'end_call',
      description:
          'End the current voice call / conversation when the user clearly wants to '
          'finish: "hang up", "end the call", "goodbye", "I\'m done", "bye", '
          '"we\'re done here", "stop the call", "talk to you later", etc. The host '
          'app will tear the call down right after your final reply. Only call this '
          'when the user is unambiguously signing off — do not invoke it on '
          'polite filler like "thanks", and never on the user\'s very first message.',
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
