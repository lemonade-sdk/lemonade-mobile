import 'dart:async';
import 'dart:convert';

import '../api/lemonade_client.dart';
import '../api/types/chat_message.dart';
import '../api/types/chat_request.dart';
import '../api/types/chat_response.dart';
import '../api/types/tool_call.dart';
import '../api/types/tool_definition.dart';
import 'capability_resolver.dart';
import 'tool_definitions.dart';
import 'tool_executor.dart';

/// Hard upper bound on tool-call iterations per user turn. Set
/// generously (30) so the model effectively decides when it's done —
/// it stops whenever it produces a tool_calls-free response. The
/// ceiling is just a runaway guard for pathological cases (a model
/// that gets stuck re-issuing the same call), not a tight budget.
///
/// Even if the ceiling IS hit, we make one final tool-less chat call
/// to force a real text reply (see end of [run]), so the user is
/// never stuck with the canned "ran out of iterations" message.
const int kAgentMaxIterations = 30;

/// Result emitted by the agent loop on each iteration.
sealed class AgentEvent {
  const AgentEvent();
}

/// A streamed text token from the model. Emitted live while the LLM is
/// producing a response so the UI can render token-by-token; the final
/// [AgentDone] text supersedes the accumulated deltas (it may differ — e.g.
/// ReAct JSON gets humanized).
class AgentDelta extends AgentEvent {
  final String text;
  const AgentDelta(this.text);
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
      // Stream the model's turn so text renders token-by-token — the SSE
      // layer assembles indexed tool-call deltas into complete ToolCalls at
      // finish, so tool-calling loses nothing by streaming. (This used to be
      // a blocking create(), which made every collection/omni chat appear
      // all at once.)
      var toolCalls = const <ToolCall>[];
      lastAssistantText = '';
      await for (final ev in client.chat.stream(ChatCompletionRequest(
        model: llmModelId,
        messages: llmMessages,
        tools: activeTools,
        stream: true,
      ))) {
        switch (ev) {
          case ChatContentDelta():
            yield AgentDelta(ev.text);
          case ChatToolCallDelta():
            // Partial tool-call fragments — nothing user-visible until the
            // assembled result arrives with the finish event.
            break;
          case ChatStreamFinish():
            toolCalls = ev.toolCalls;
            lastAssistantText = ev.contentSoFar;
        }
      }
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

      // Tool calls within a single LLM iteration are independent — kick
      // them off concurrently so research-heavy turns (e.g. two
      // web_search calls + a find_places) don't serialize. We still
      // apply results in the original order so the conversation thread
      // stays deterministic.
      final inFlight = <Future<ToolExecutionResult>>[];
      for (final tc in toolCalls) {
        yield AgentStatus(_statusForTool(tc.name));
        inFlight.add(executor.execute(tc, ctx));
      }
      final results = await Future.wait(inFlight);

      for (var i = 0; i < toolCalls.length; i++) {
        final tc = toolCalls[i];
        final result = results[i];
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

    // We hit the iteration ceiling without the model ever choosing to stop
    // tool-calling. Common cause: a small/instruction-following LLM keeps
    // re-issuing tool calls instead of summarizing. Make one last chat
    // call WITHOUT tools — the model is now forced to produce text, given
    // the tool history already in `llmMessages`. Most of the time this
    // produces a perfectly reasonable wrap-up; if the call itself errors
    // we fall back to the last text we have or a canned message so the
    // user is never left without a reply.
    yield const AgentStatus('Wrapping up…');
    String wrapUpText = lastAssistantText;
    try {
      final wrapUp = await client.chat.create(ChatCompletionRequest(
        model: llmModelId,
        messages: [
          ...llmMessages,
          ApiChatMessage.system(
            'You have completed your research. Without calling any more '
            'tools, give the user a short, helpful final reply based on '
            'what you found above. If you ran into errors, apologize '
            'briefly and tell them what was missing.',
          ),
        ],
        stream: false,
      ));
      final text = wrapUp.message.content?.trim() ?? '';
      if (text.isNotEmpty) wrapUpText = text;
    } catch (_) {
      // Network/model error on the wrap-up — fall through to whatever
      // lastAssistantText already has, or the canned fallback.
    }

    yield AgentDone(
      text: wrapUpText.isEmpty
          ? "Sorry — I couldn't find what you were looking for."
          : _humanizeReactJson(wrapUpText),
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
