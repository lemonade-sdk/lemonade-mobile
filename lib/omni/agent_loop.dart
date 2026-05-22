import 'dart:async';
import 'dart:convert';

import '../api/lemonade_client.dart';
import '../api/types/chat_message.dart';
import '../api/types/chat_request.dart';
import '../api/types/tool_call.dart';
import '../api/types/tool_definition.dart';
import 'capability_resolver.dart';
import 'tool_definitions.dart';
import 'tool_executor.dart';

/// Maximum tool-call iterations per user turn. Mirrors the desktop reference.
const int kAgentMaxIterations = 5;

/// Result emitted by the agent loop on each iteration.
sealed class AgentEvent {
  const AgentEvent();
}

/// Status update for UI ("Thinking…", "Generating image…", etc.).
class AgentStatus extends AgentEvent {
  final String message;
  const AgentStatus(this.message);
}

/// A tool was executed; its artifact (image/audio) is available now.
class AgentArtifact extends AgentEvent {
  final Artifact artifact;
  const AgentArtifact(this.artifact);
}

/// The LLM invoked an app-control tool that signals the host should end
/// the current session (e.g. `end_call` in voice mode). The loop still
/// gives the model one final iteration so it can speak its goodbye, but
/// consumers should set up to tear down the session after the next
/// [AgentDone].
class AgentEndCall extends AgentEvent {
  const AgentEndCall();
}

/// Final assistant text + accumulated artifacts. Stream ends after this.
class AgentDone extends AgentEvent {
  final String text;
  final List<Artifact> artifacts;
  const AgentDone({required this.text, required this.artifacts});
}

/// Stream-style agent loop. Consumes [history] (raw chat messages including
/// any user attachments), drives the LLM through up to [kAgentMaxIterations]
/// rounds of tool calling, and emits [AgentEvent]s for the UI.
class AgentLoop {
  final LemonadeApiClient client;
  final String llmModelId;
  final CapabilitySnapshot capabilities;
  final OmniToolExecutor executor;

  AgentLoop({
    required this.client,
    required this.llmModelId,
    required this.capabilities,
    required this.executor,
  });

  /// Runs the loop. [history] is a sequence of `(role, content)` pairs where
  /// content is either a plain string or a list of OpenAI-style content parts
  /// (used for vision/audio uploads in the *current user turn*).
  Stream<AgentEvent> run({
    required List<AgentMessage> history,
    String? extraSystemPrompt,
  }) async* {
    final extracted = _extractBinaryContext(history);
    final processed = _stripBinariesForLlm(history, extracted);

    final activeTools = capabilities.tools.map((t) => t.definition).toList();
    final systemPrompt = OmniToolCatalog.buildSystemPrompt(activeTools);
    final mergedSystem = (extraSystemPrompt == null || extraSystemPrompt.isEmpty)
        ? systemPrompt
        : '$systemPrompt\n\n$extraSystemPrompt';

    final llmMessages = <ApiChatMessage>[];
    if (processed.firstOrNull?.role == 'system') {
      llmMessages.add(ApiChatMessage.system(
        '$mergedSystem\n\n${processed.first.text ?? ''}',
      ));
      llmMessages.addAll(processed.skip(1).map(_toApiMessage));
    } else {
      llmMessages.add(ApiChatMessage.system(mergedSystem));
      llmMessages.addAll(processed.map(_toApiMessage));
    }

    final ctx = ToolExecutionContext(
      extractedAudio: extracted.audio,
      extractedImages: extracted.images,
      sourceArtifacts: extracted.priorArtifacts,
      turnArtifacts: <Artifact>[],
    );

    yield const AgentStatus('Thinking…');

    var lastAssistantText = '';

    for (var iteration = 0; iteration < kAgentMaxIterations; iteration++) {
      final response = await client.chat.create(ChatCompletionRequest(
        model: llmModelId,
        messages: llmMessages,
        tools: activeTools,
        stream: false,
      ));

      final assistant = response.message;
      lastAssistantText = assistant.content ?? '';

      final toolCalls = assistant.toolCalls ?? const <ToolCall>[];
      if (toolCalls.isEmpty) {
        yield AgentDone(
          text: _humanizeReactJson(lastAssistantText),
          artifacts: ctx.turnArtifacts,
        );
        return;
      }

      llmMessages.add(ApiChatMessage.assistantToolCalls(
        toolCalls,
        content: lastAssistantText.isEmpty ? null : lastAssistantText,
      ));

      for (final tc in toolCalls) {
        yield AgentStatus(_statusForTool(tc.name));
        final result = await executor.execute(tc, ctx);
        final summary = _applyResult(result, ctx);
        if (result is ImageResult || result is AudioResult) {
          yield AgentArtifact(ctx.turnArtifacts.last);
        }
        if (result is EndCallResult) {
          yield const AgentEndCall();
        }
        llmMessages.add(ApiChatMessage.tool(summary, toolCallId: tc.id));
      }
    }

    yield AgentDone(
      text: lastAssistantText.isEmpty
          ? 'I ran out of iterations before completing the request.'
          : _humanizeReactJson(lastAssistantText),
      artifacts: ctx.turnArtifacts,
    );
  }

  /// Some Lemonade-served LLMs (especially small open-weights models) emit a
  /// ReAct-style JSON block — `{"action": "...", "action_input": "...",
  /// "thought": "..."}` — as their assistant content instead of natural prose.
  /// The tool runs (the artifact appears) but the chat ends up showing raw
  /// JSON. Rewrite that to a readable `**Thoughts:** ...` line plus a caption
  /// derived from the action input. Non-ReAct content passes through unchanged.
  String _humanizeReactJson(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) return text;

    final Map<String, dynamic>? parsed = _tryDecodeJsonObject(trimmed);
    if (parsed == null) return text;

    final hasReactKeys = parsed.containsKey('action') ||
        parsed.containsKey('action_input') ||
        parsed.containsKey('thought');
    if (!hasReactKeys) return text;

    final out = <String>[];

    final thought = parsed['thought'];
    if (thought is String && thought.trim().isNotEmpty) {
      out.add('**Thoughts:** ${thought.trim()}');
    }

    final caption = _captionForActionInput(parsed['action_input']);
    if (caption != null && caption.isNotEmpty) {
      out.add(caption);
    } else if (parsed['action'] is String) {
      out.add('_Used ${parsed['action']}._');
    }

    return out.isEmpty ? text : out.join('\n\n');
  }

  /// `action_input` is usually a JSON object, but models sometimes emit it as
  /// a JSON-encoded string (occasionally with single quotes). Pull the most
  /// human-meaningful field out — image_prompt for image gen, prompt for
  /// edit/general, text_to_speak for TTS — and fall back to the raw value.
  String? _captionForActionInput(dynamic actionInput) {
    Map<String, dynamic>? asMap;
    if (actionInput is Map) {
      asMap = actionInput.cast<String, dynamic>();
    } else if (actionInput is String) {
      asMap = _tryDecodeJsonObject(actionInput) ??
          _tryDecodeJsonObject(actionInput.replaceAll("'", '"'));
      if (asMap == null) {
        final s = actionInput.trim();
        return s.isEmpty ? null : s;
      }
    }
    if (asMap == null) return null;
    for (final key in const [
      'image_prompt',
      'prompt',
      'text_to_speak',
      'question',
    ]) {
      final v = asMap[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  Map<String, dynamic>? _tryDecodeJsonObject(String raw) {
    try {
      final v = jsonDecode(raw);
      if (v is Map) return v.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  String _applyResult(ToolExecutionResult result, ToolExecutionContext ctx) {
    switch (result) {
      case TextResult():
        return result.text.isEmpty ? 'Done.' : result.text;
      case ImageResult():
        final art = Artifact(
          kind: ArtifactKind.image,
          mime: result.mime,
          base64Data: result.base64Data,
        );
        if (result.mode == 'edit') {
          // Replace the most recent image in this turn, if any.
          final lastIdx = ctx.turnArtifacts.lastIndexWhere(
            (a) => a.kind == ArtifactKind.image,
          );
          if (lastIdx >= 0) {
            ctx.turnArtifacts[lastIdx] = art;
          } else {
            ctx.turnArtifacts.add(art);
          }
          return 'Image edited successfully.';
        }
        ctx.turnArtifacts.add(art);
        return 'Image generated successfully.';
      case AudioResult():
        ctx.turnArtifacts.add(Artifact(
          kind: ArtifactKind.audio,
          mime: result.mime,
          base64Data: result.base64Data,
        ));
        return 'Audio generated successfully.';
      case EndCallResult():
        // Feed a confirmation back to the LLM so its final iteration knows
        // to wrap up gracefully — usually a short "Goodbye!" or similar.
        return 'Call ending — say a brief goodbye.';
      case ErrorResult():
        return 'Error: ${result.message}';
    }
  }

  String _statusForTool(String name) {
    switch (name) {
      case 'generate_image':
        return 'Generating image…';
      case 'edit_image':
        return 'Editing image…';
      case 'text_to_speech':
        return 'Synthesizing speech…';
      case 'transcribe_audio':
        return 'Transcribing audio…';
      case 'analyze_image':
        return 'Analyzing image…';
      default:
        return 'Running $name…';
    }
  }

  ApiChatMessage _toApiMessage(AgentMessage m) {
    final parts = m.parts;
    if (parts != null && parts.isNotEmpty) {
      switch (m.role) {
        case 'user':
          return ApiChatMessage.userParts(parts);
        case 'assistant':
          return ApiChatMessage.assistant(m.text ?? '');
        default:
          return ApiChatMessage.system(m.text ?? '');
      }
    }
    final text = m.text ?? '';
    switch (m.role) {
      case 'user':
        return ApiChatMessage.user(text);
      case 'assistant':
        return ApiChatMessage.assistant(text);
      case 'tool':
        return ApiChatMessage.tool(text, toolCallId: m.toolCallId ?? '');
      default:
        return ApiChatMessage.system(text);
    }
  }

  // ---------------------------------------------------------------------------
  // Binary extraction & placeholder substitution
  // ---------------------------------------------------------------------------

  _ExtractedBinaries _extractBinaryContext(List<AgentMessage> history) {
    final audio = <({String data, String mime})>[];
    final images = <({String dataUrl, String mime, String base64})>[];
    final priorArtifacts = <Artifact>[];

    for (final msg in history) {
      final parts = msg.parts;
      if (parts == null) continue;
      final isUser = msg.role == 'user';
      for (final p in parts) {
        if (p.type == 'image_url' && p.imageUrl != null) {
          final url = p.imageUrl!;
          if (isUser && url.startsWith('data:image/')) {
            final mime = url.substring(5, url.indexOf(';'));
            final commaIdx = url.indexOf(',');
            final b64 = commaIdx > 0 ? url.substring(commaIdx + 1) : '';
            images.add((dataUrl: url, mime: mime, base64: b64));
          } else if (!isUser && url.startsWith('data:image/')) {
            final mime = url.substring(5, url.indexOf(';'));
            final commaIdx = url.indexOf(',');
            final b64 = commaIdx > 0 ? url.substring(commaIdx + 1) : '';
            priorArtifacts.add(Artifact(
              kind: ArtifactKind.image,
              mime: mime,
              base64Data: b64,
            ));
          }
        } else if (p.type == 'input_audio' &&
            p.audioBase64 != null &&
            p.audioFormat != null &&
            isUser) {
          audio.add((
            data: p.audioBase64!,
            mime: 'audio/${p.audioFormat}',
          ));
        }
      }
    }
    return _ExtractedBinaries(
      audio: audio,
      images: images,
      priorArtifacts: priorArtifacts,
    );
  }

  /// Replace binary content parts with `[User provided audio file #N]` /
  /// `[User provided image #N]` placeholders so the LLM sees a slim transcript.
  List<AgentMessage> _stripBinariesForLlm(
    List<AgentMessage> history,
    _ExtractedBinaries extracted,
  ) {
    var audioCount = 0;
    var imageCount = 0;
    final out = <AgentMessage>[];
    for (final msg in history) {
      final parts = msg.parts;
      if (parts == null) {
        out.add(msg);
        continue;
      }
      final newParts = <ApiContentPart>[];
      for (final p in parts) {
        if (p.type == 'image_url') {
          if (msg.role == 'user') {
            imageCount++;
            newParts.add(ApiContentPart.text('[User provided image #$imageCount]'));
          } else {
            newParts.add(const ApiContentPart.text('[Generated image]'));
          }
        } else if (p.type == 'input_audio') {
          if (msg.role == 'user') {
            audioCount++;
            newParts.add(
                ApiContentPart.text('[User provided audio file #$audioCount]'));
          }
          // assistant audio is dropped silently
        } else {
          newParts.add(p);
        }
      }
      out.add(AgentMessage(
        role: msg.role,
        text: null,
        parts: newParts,
        toolCallId: msg.toolCallId,
      ));
    }
    return out;
  }
}

/// Slim message DTO used by the agent loop. Distinct from the wire-format
/// [ApiChatMessage] so the loop can re-encode messages with placeholders.
class AgentMessage {
  /// 'system' | 'user' | 'assistant' | 'tool'
  final String role;
  final String? text;
  final List<ApiContentPart>? parts;
  final String? toolCallId;

  const AgentMessage({
    required this.role,
    this.text,
    this.parts,
    this.toolCallId,
  });

  AgentMessage.user(String text) : this(role: 'user', text: text);
  AgentMessage.assistant(String text) : this(role: 'assistant', text: text);
  AgentMessage.system(String text) : this(role: 'system', text: text);
  AgentMessage.userParts(List<ApiContentPart> parts)
      : this(role: 'user', parts: parts);
}

class _ExtractedBinaries {
  final List<({String data, String mime})> audio;
  final List<({String dataUrl, String mime, String base64})> images;
  final List<Artifact> priorArtifacts;

  _ExtractedBinaries({
    required this.audio,
    required this.images,
    required this.priorArtifacts,
  });
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

extension on List<ToolDefinition> {
  // ignore: unused_element
  bool any(bool Function(ToolDefinition) test) {
    for (final t in this) {
      if (test(t)) return true;
    }
    return false;
  }
}
