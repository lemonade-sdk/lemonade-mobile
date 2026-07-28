import 'dart:async';
import 'dart:convert';

import '../api/lemonade_client.dart';
import '../api/net.dart';
import '../api/types/chat_message.dart';
import '../api/types/chat_request.dart';
import '../api/types/chat_response.dart';
import '../api/types/tool_call.dart';
import '../api/types/tool_definition.dart';
import '../constants/messages.dart';
import 'cancel_token.dart';
import 'capability_resolver.dart';
import 'tool_definitions.dart';
import 'tool_executor.dart';

// Re-export so existing `import agent_loop.dart` sites keep working.
export '../api/net.dart' show isRetryableTransportError;

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

  /// True when this artifact REPLACES the previously emitted image artifact
  /// of this turn (edit_image applied to a generate_image result) instead of
  /// adding a new one. Consumers rendering artifacts incrementally must swap
  /// the prior image out, or a generate-then-edit turn shows both.
  final bool replacesPrevious;

  const AgentArtifact(this.artifact, {this.replacesPrevious = false});
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
  final CancelToken? cancelToken;

  AgentLoop({
    required this.client,
    required this.llmModelId,
    required this.capabilities,
    required this.executor,
    this.cancelToken,
  });

  bool get _cancelled => cancelToken?.isCancelled ?? false;

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
      if (_cancelled) {
        yield AgentDone(
          text: _humanizeReactJson(lastAssistantText),
          artifacts: ctx.turnArtifacts,
        );
        return;
      }
      // Stream the model's turn so text renders token-by-token — the SSE
      // layer assembles indexed tool-call deltas into complete ToolCalls at
      // finish, so tool-calling loses nothing by streaming. (This used to be
      // a blocking create(), which made every collection/omni chat appear
      // all at once.)
      final request = ChatCompletionRequest(
        model: llmModelId,
        messages: llmMessages,
        tools: activeTools,
        stream: true,
      );
      var toolCalls = const <ToolCall>[];
      lastAssistantText = '';
      var streamedAny = false;
      var interrupted = false;
      try {
        await for (final ev in client.chat.stream(request)) {
          switch (ev) {
            case ChatContentDelta():
              streamedAny = true;
              yield AgentDelta(ev.text);
            case ChatToolCallDelta():
              // Partial tool-call fragments — nothing user-visible until the
              // assembled result arrives with the finish event.
              break;
            case ChatStreamFinish():
              toolCalls = ev.toolCalls;
              lastAssistantText = ev.contentSoFar;
              // The API layer reports mid-stream truncation as
              // finishReason 'interrupted' (partial content preserved)
              // instead of fabricating a clean 'stop'.
              interrupted = ev.finishReason == 'interrupted';
          }
        }
      } catch (e) {
        // The SSE connection dropped mid-flight ("Connection closed while
        // receiving data" — a proxy/node streaming hiccup, common on vision +
        // tool turns). For TRANSPORT-level failures only, silently start a
        // fresh NON-streaming request for this same turn (what the loop did
        // before streaming, and proven reliable) instead of surfacing the
        // error. Deterministic request errors (4xx, model mismatch, auth)
        // propagate — retrying them just re-fails slower. Reset any
        // partially-streamed text via a status so the retried result doesn't
        // render doubled.
        if (!isRetryableTransportError(e)) rethrow;
        if (streamedAny) yield const AgentStatus('Thinking…');
        final response = await client.chat.create(ChatCompletionRequest(
          model: llmModelId,
          messages: llmMessages,
          tools: activeTools,
          stream: false,
        ));
        lastAssistantText = response.message.content ?? '';
        toolCalls = response.message.toolCalls ?? const <ToolCall>[];
        interrupted = false;
      }
      if (interrupted && toolCalls.isEmpty) {
        if (lastAssistantText.isEmpty) {
          // Truncated before any content arrived — silent non-streaming retry.
          final response = await client.chat.create(ChatCompletionRequest(
            model: llmModelId,
            messages: llmMessages,
            tools: activeTools,
            stream: false,
          ));
          lastAssistantText = response.message.content ?? '';
          toolCalls = response.message.toolCalls ?? const <ToolCall>[];
        } else {
          // Partial content arrived — keep it and flag the interruption.
          lastAssistantText =
              '$lastAssistantText\n\n${AppMessages.streamInterruptedNotice}';
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

      // Execute the round's tool calls SEQUENTIALLY, in order. Tool calls in
      // one round are NOT independent: models chain context-dependent tools
      // (generate_image → edit_image) within a single round, and edit_image
      // reads the generate_image result out of ctx.turnArtifacts — running
      // them concurrently made the edit see a context missing the image.
      //
      // Cancellation: [cancelToken] is checked before each tool; the status
      // yield is also a tear-down point if the consumer cancelled the stream.
      for (final tc in toolCalls) {
        if (_cancelled) {
          yield AgentDone(
            text: _humanizeReactJson(lastAssistantText),
            artifacts: ctx.turnArtifacts,
          );
          return;
        }
        yield AgentStatus(_statusForTool(tc.name));
        if (_cancelled) {
          yield AgentDone(
            text: _humanizeReactJson(lastAssistantText),
            artifacts: ctx.turnArtifacts,
          );
          return;
        }
        final result = await executor.execute(tc, ctx, isCancelled: () => _cancelled);
        if (_cancelled) {
          // Keep any artifact the tool already produced; stop further tools.
          final applied = _applyResult(result, ctx);
          if (applied.artifact != null) {
            yield AgentArtifact(applied.artifact!,
                replacesPrevious: applied.replacedPrevious);
          }
          yield AgentDone(
            text: _humanizeReactJson(lastAssistantText),
            artifacts: ctx.turnArtifacts,
          );
          return;
        }
        final applied = _applyResult(result, ctx);
        final artifact = applied.artifact;
        if (artifact != null) {
          yield AgentArtifact(artifact,
              replacesPrevious: applied.replacedPrevious);
        }
        if (result is EndCallResult) {
          yield const AgentEndCall();
        }
        llmMessages.add(ApiChatMessage.tool(applied.summary, toolCallId: tc.id));
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

  /// Applies a tool result to the turn context. Returns the tool-message
  /// summary for the LLM, plus the artifact this call produced (if any) and
  /// whether it replaced a prior turn artifact — so the caller emits the
  /// ACTUAL artifact rather than guessing from `turnArtifacts.last`.
  ({String summary, Artifact? artifact, bool replacedPrevious}) _applyResult(
      ToolExecutionResult result, ToolExecutionContext ctx) {
    switch (result) {
      case TextResult():
        return (
          summary: result.text.isEmpty ? 'Done.' : result.text,
          artifact: null,
          replacedPrevious: false,
        );
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
          final replaced = lastIdx >= 0;
          if (replaced) {
            ctx.turnArtifacts[lastIdx] = art;
          } else {
            ctx.turnArtifacts.add(art);
          }
          return (
            summary: 'Image edited successfully.',
            artifact: art,
            replacedPrevious: replaced,
          );
        }
        ctx.turnArtifacts.add(art);
        return (
          summary: 'Image generated successfully.',
          artifact: art,
          replacedPrevious: false,
        );
      case AudioResult():
        final art = Artifact(
          kind: ArtifactKind.audio,
          mime: result.mime,
          base64Data: result.base64Data,
        );
        ctx.turnArtifacts.add(art);
        return (
          summary: 'Audio generated successfully.',
          artifact: art,
          replacedPrevious: false,
        );
      case EndCallResult():
        // Feed a confirmation back to the LLM so its final iteration knows
        // to wrap up gracefully — usually a short "Goodbye!" or similar.
        return (
          summary: 'Call ending — say a brief goodbye.',
          artifact: null,
          replacedPrevious: false,
        );
      case ErrorResult():
        return (
          summary: 'Error: ${result.message}',
          artifact: null,
          replacedPrevious: false,
        );
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
