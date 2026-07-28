import 'dart:async';

import '../api/lemonade_client.dart';
import '../api/types/chat_message.dart';
import '../api/types/chat_request.dart';
import '../api/types/chat_response.dart';
import '../constants/messages.dart';
import '../models/chat_message.dart' as ui;
import '../omni/agent_loop.dart';
import '../omni/cancel_token.dart';
import '../omni/capability_resolver.dart';
import '../omni/message_mapper.dart';
import '../omni/tool_executor.dart';

/// Orchestrates a chat turn against the active server. Two paths:
///   • OmniRouter mode → drives the [AgentLoop] for multimodal tool calling.
///   • Plain mode      → streams `/v1/chat/completions` token-by-token.
///
/// Both paths emit a unified [ChatTurnEvent] stream so callers can render the
/// turn the same way regardless of mode.
class ChatService {
  final LemonadeApiClient client;
  ChatService(this.client);

  /// Default character budget for the wire history when the model doesn't
  /// advertise [maxContextTokens] (~6k tokens at ~4 chars/token). Local
  /// models often run 4k–8k-token contexts; unbounded history is what made
  /// chats die with HTTP 500 after a few rounds.
  static const int kHistoryCharBudget = 24000;

  /// Run a chat turn. Caller passes the full conversation [history] (already
  /// containing the new user message). Older turns beyond the char budget are
  /// dropped from the wire request (the on-device chat log keeps everything).
  ///
  /// [maxContextTokens] (from `ModelInfo.maxContextWindow`) sizes the budget
  /// when known; ~3 chars/token with 25% headroom left for system/tools.
  Stream<ChatTurnEvent> run({
    required String llmModel,
    required List<ui.ChatMessage> history,
    bool omniRouterEnabled = true,
    CapabilitySnapshot? capabilities,
    OmniToolExecutor? executor,
    String? extraSystemPrompt,
    int? maxContextTokens,
    CancelToken? cancelToken,
  }) async* {
    final budget = _charBudgetFor(maxContextTokens);
    // Expand file-backed attachment refs to data URLs for the wire only
    // (cold-start history keeps paths in RAM until here).
    final resolved = await _resolveMediaForWire(history);
    final trimmed = _trimHistory(_sanitizeHistory(resolved), budget);
    final useOmni = omniRouterEnabled &&
        capabilities != null &&
        capabilities.isUsable &&
        executor != null;

    if (useOmni) {
      yield* _runOmni(
        llmModel: llmModel,
        history: trimmed,
        capabilities: capabilities,
        executor: executor,
        extraSystemPrompt: extraSystemPrompt,
        cancelToken: cancelToken,
      );
    } else {
      yield* _runPlainStream(llmModel: llmModel, history: trimmed);
    }
  }

  /// Load disk-backed attachments into data URLs for the model API.
  Future<List<ui.ChatMessage>> _resolveMediaForWire(
      List<ui.ChatMessage> history) async {
    final out = <ui.ChatMessage>[];
    for (final m in history) {
      final parts = <ui.MessageContent>[];
      for (final c in m.content) {
        if ((c.type == ui.MessageContentType.image ||
                c.type == ui.MessageContentType.audio) &&
            c.isFileRef) {
          try {
            parts.add(ui.MessageContent(
                type: c.type, value: await c.resolveDataUrl()));
          } catch (_) {
            // Drop unreadable attachment for the wire; UI still has the ref.
          }
        } else {
          parts.add(c);
        }
      }
      out.add(ui.ChatMessage(
        id: m.id,
        role: m.role,
        content: parts,
        timestamp: m.timestamp,
      ));
    }
    return out;
  }

  /// Map a token context window to a character budget for history trimming.
  static int _charBudgetFor(int? maxContextTokens) {
    if (maxContextTokens == null || maxContextTokens <= 0) {
      return kHistoryCharBudget;
    }
    // ~3 chars/token for mixed text; reserve ~25% for system + tools + reply.
    final chars = ((maxContextTokens * 3) * 0.75).floor();
    return chars.clamp(8000, 200000);
  }

  /// Remove error/interruption notices (assistant-bubble lines marked with
  /// [AppMessages.errorNoticeMarker]) from the wire history. They're UI-only:
  /// replaying "Can't reach the server…" back to the model as assistant
  /// content pollutes the context on every later turn. Assistant messages
  /// that were PURE error bubbles are dropped entirely.
  List<ui.ChatMessage> _sanitizeHistory(List<ui.ChatMessage> history) {
    final out = <ui.ChatMessage>[];
    for (final m in history) {
      final hasMarker = m.content.any((c) =>
          c.type == ui.MessageContentType.text &&
          c.value.contains(AppMessages.errorNoticeMarker));
      if (!hasMarker) {
        out.add(m);
        continue;
      }
      final parts = <ui.MessageContent>[];
      for (final c in m.content) {
        if (c.type != ui.MessageContentType.text) {
          parts.add(c);
          continue;
        }
        final stripped = AppMessages.stripErrorNotices(c.value);
        if (stripped.isNotEmpty) {
          parts.add(ui.MessageContent(
              type: ui.MessageContentType.text, value: stripped));
        }
      }
      if (parts.isEmpty) continue;
      out.add(ui.ChatMessage(
        id: m.id,
        role: m.role,
        content: parts,
        timestamp: m.timestamp,
      ));
    }
    return out;
  }

  /// Keep the most recent messages that fit the char budget. The newest
  /// message is always kept, and we prefer starting the window on a user turn
  /// so the model doesn't see a conversation opening mid-answer.
  List<ui.ChatMessage> _trimHistory(List<ui.ChatMessage> history, int budget) {
    if (history.isEmpty) return history;
    var used = 0;
    var start = history.length;
    for (var i = history.length - 1; i >= 0; i--) {
      final cost = history[i].textContent.length + 64; // ≈ per-message overhead
      if (start < history.length && used + cost > budget) break;
      start = i;
      used += cost;
    }
    // Slide forward past any leading assistant turns left by the cut.
    while (start < history.length - 1 && !history[start].isUser) {
      start++;
    }
    return start == 0 ? history : history.sublist(start);
  }

  Stream<ChatTurnEvent> _runOmni({
    required String llmModel,
    required List<ui.ChatMessage> history,
    required CapabilitySnapshot capabilities,
    required OmniToolExecutor executor,
    String? extraSystemPrompt,
    CancelToken? cancelToken,
  }) async* {
    final loop = AgentLoop(
      client: client,
      llmModelId: llmModel,
      capabilities: capabilities,
      executor: executor,
      cancelToken: cancelToken,
    );

    final agentMessages = history.map(_toAgentMessage).toList(growable: false);

    try {
      await for (final event in loop.run(
        history: agentMessages,
        extraSystemPrompt: extraSystemPrompt,
      )) {
        switch (event) {
          case AgentDelta():
            yield ChatTurnEvent.tokens(event.text);
          case AgentStatus():
            yield ChatTurnEvent.status(event.message);
          case AgentArtifact():
            yield ChatTurnEvent.artifact(event.artifact,
                replacesPrevious: event.replacesPrevious);
          case AgentEndCall():
            // end_call is a voice-mode control signal; plain chat ignores it.
            break;
          case AgentDone():
            yield ChatTurnEvent.done(
                text: event.text, artifacts: event.artifacts);
        }
      }
    } on TurnCancelledException {
      // Stop pressed mid-tools — surface whatever we already had as done.
      yield ChatTurnEvent.done(text: '', artifacts: const []);
    }
  }

  Stream<ChatTurnEvent> _runPlainStream({
    required String llmModel,
    required List<ui.ChatMessage> history,
  }) async* {
    final apiMessages = _buildApiHistory(history);

    final buf = StringBuffer();
    var streamedAny = false;
    var interrupted = false;
    try {
      final stream = client.chat.stream(ChatCompletionRequest(
        model: llmModel,
        messages: apiMessages,
        stream: true,
      ));
      await for (final ev in stream) {
        switch (ev) {
          case ChatContentDelta():
            buf.write(ev.text);
            streamedAny = true;
            yield ChatTurnEvent.tokens(ev.text);
          case ChatToolCallDelta():
            // Plain mode: ignore tool deltas (we didn't request tools).
            break;
          case ChatStreamFinish():
            // The API layer reports mid-stream truncation as finishReason
            // 'interrupted' (partial content preserved) instead of
            // fabricating a clean 'stop'.
            interrupted = ev.finishReason == 'interrupted';
            if (!interrupted) {
              yield ChatTurnEvent.done(text: buf.toString(), artifacts: const []);
            }
        }
      }
    } catch (e) {
      // Only TRANSPORT-level drops (socket died, timeout, truncated SSE) get
      // the silent retry — deterministic request errors (4xx, model
      // mismatch, auth) propagate to the caller's error handling.
      if (!isRetryableTransportError(e)) rethrow;
      if (streamedAny) {
        // Partial content already rendered — keep it, flag the interruption.
        yield ChatTurnEvent.done(
          text: '$buf\n\n${AppMessages.streamInterruptedNotice}',
          artifacts: const [],
        );
        return;
      }
      final response = await client.chat.create(ChatCompletionRequest(
        model: llmModel,
        messages: apiMessages,
        stream: false,
      ));
      yield ChatTurnEvent.done(
          text: response.message.content ?? '', artifacts: const []);
      return;
    }
    if (interrupted) {
      if (streamedAny) {
        // Partial content arrived — keep it and append the interruption
        // notice (marked so it's stripped from later model payloads).
        yield ChatTurnEvent.done(
          text: '$buf\n\n${AppMessages.streamInterruptedNotice}',
          artifacts: const [],
        );
      } else {
        // Truncated before any content — silent non-streaming retry.
        final response = await client.chat.create(ChatCompletionRequest(
          model: llmModel,
          messages: apiMessages,
          stream: false,
        ));
        yield ChatTurnEvent.done(
            text: response.message.content ?? '', artifacts: const []);
      }
    }
  }

  AgentMessage _toAgentMessage(ui.ChatMessage m) => agentMessageFromUi(m);

  /// Build the wire history for plain chat, keeping the (large) base64 image
  /// parts ONLY on the most recent image-bearing message. Older images collapse
  /// to a text placeholder so the request payload doesn't grow unbounded across
  /// turns — re-sending every image each round is a common cause of server 500s.
  List<ApiChatMessage> _buildApiHistory(List<ui.ChatMessage> history) {
    int lastImageIdx = -1;
    for (int i = 0; i < history.length; i++) {
      if (history[i].hasImages) lastImageIdx = i;
    }
    return [
      for (int i = 0; i < history.length; i++)
        _toApiMessage(history[i], keepImages: i == lastImageIdx),
    ];
  }

  ApiChatMessage _toApiMessage(ui.ChatMessage m, {bool keepImages = true}) {
    if (!m.hasImages) {
      return m.isUser ? ApiChatMessage.user(m.textContent) : ApiChatMessage.assistant(m.textContent);
    }
    if (!keepImages) {
      // Drop the base64 image(s) from older turns; leave a marker so the
      // conversation still reads coherently.
      final placeholder =
          m.textContent.isEmpty ? '[image]' : '${m.textContent} [image]';
      return m.isUser
          ? ApiChatMessage.user(placeholder)
          : ApiChatMessage.assistant(placeholder);
    }
    final parts = <ApiContentPart>[];
    if (m.textContent.isNotEmpty) parts.add(ApiContentPart.text(m.textContent));
    for (final c in m.content) {
      if (c.type == ui.MessageContentType.image && c.value.startsWith('data:')) {
        parts.add(ApiContentPart.imageUrl(c.value));
      }
    }
    return m.isUser
        ? ApiChatMessage.userParts(parts)
        : ApiChatMessage.assistant(m.textContent);
  }
}

/// Unified event stream for a single chat turn.
sealed class ChatTurnEvent {
  const ChatTurnEvent();

  factory ChatTurnEvent.tokens(String delta) = ChatTokens;
  factory ChatTurnEvent.status(String message) = ChatStatus;
  factory ChatTurnEvent.artifact(Artifact artifact, {bool replacesPrevious}) =
      ChatArtifact;
  factory ChatTurnEvent.done({required String text, required List<Artifact> artifacts}) = ChatDone;
}

class ChatTokens extends ChatTurnEvent {
  final String delta;
  const ChatTokens(this.delta);
}

class ChatStatus extends ChatTurnEvent {
  final String message;
  const ChatStatus(this.message);
}

class ChatArtifact extends ChatTurnEvent {
  final Artifact artifact;

  /// True when this artifact replaces the previously emitted image artifact
  /// of the turn (edit_image over a generate_image) instead of adding one.
  final bool replacesPrevious;

  const ChatArtifact(this.artifact, {this.replacesPrevious = false});
}

class ChatDone extends ChatTurnEvent {
  final String text;
  final List<Artifact> artifacts;
  const ChatDone({required this.text, required this.artifacts});
}
