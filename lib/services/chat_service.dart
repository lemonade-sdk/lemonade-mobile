import 'dart:async';

import '../api/lemonade_client.dart';
import '../api/types/chat_message.dart';
import '../api/types/chat_request.dart';
import '../api/types/chat_response.dart';
import '../models/chat_message.dart' as ui;
import '../omni/agent_loop.dart';
import '../omni/capability_resolver.dart';
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

  /// Run a chat turn. Caller passes the full conversation [history] (already
  /// containing the new user message).
  Stream<ChatTurnEvent> run({
    required String llmModel,
    required List<ui.ChatMessage> history,
    bool omniRouterEnabled = true,
    CapabilitySnapshot? capabilities,
    OmniToolExecutor? executor,
    String? extraSystemPrompt,
  }) {
    final useOmni = omniRouterEnabled &&
        capabilities != null &&
        capabilities.isUsable &&
        executor != null;

    if (useOmni) {
      return _runOmni(
        llmModel: llmModel,
        history: history,
        capabilities: capabilities,
        executor: executor,
        extraSystemPrompt: extraSystemPrompt,
      );
    }
    return _runPlainStream(llmModel: llmModel, history: history);
  }

  Stream<ChatTurnEvent> _runOmni({
    required String llmModel,
    required List<ui.ChatMessage> history,
    required CapabilitySnapshot capabilities,
    required OmniToolExecutor executor,
    String? extraSystemPrompt,
  }) async* {
    final loop = AgentLoop(
      client: client,
      llmModelId: llmModel,
      capabilities: capabilities,
      executor: executor,
    );

    final agentMessages = history.map(_toAgentMessage).toList(growable: false);

    await for (final event in loop.run(
      history: agentMessages,
      extraSystemPrompt: extraSystemPrompt,
    )) {
      switch (event) {
        case AgentStatus():
          yield ChatTurnEvent.status(event.message);
        case AgentArtifact():
          yield ChatTurnEvent.artifact(event.artifact);
        case AgentEndCall():
          // end_call is a voice-mode control signal; plain chat ignores it.
          break;
        case AgentDone():
          yield ChatTurnEvent.done(text: event.text, artifacts: event.artifacts);
      }
    }
  }

  Stream<ChatTurnEvent> _runPlainStream({
    required String llmModel,
    required List<ui.ChatMessage> history,
  }) async* {
    final apiMessages = _buildApiHistory(history);

    final stream = client.chat.stream(ChatCompletionRequest(
      model: llmModel,
      messages: apiMessages,
      stream: true,
    ));

    final buf = StringBuffer();
    await for (final ev in stream) {
      switch (ev) {
        case ChatContentDelta():
          buf.write(ev.text);
          yield ChatTurnEvent.tokens(ev.text);
        case ChatToolCallDelta():
          // Plain mode: ignore tool deltas (we didn't request tools).
          break;
        case ChatStreamFinish():
          yield ChatTurnEvent.done(text: buf.toString(), artifacts: const []);
      }
    }
  }

  AgentMessage _toAgentMessage(ui.ChatMessage m) {
    final role = m.isUser ? 'user' : 'assistant';
    if (!m.hasImages) {
      return AgentMessage(role: role, text: m.textContent);
    }
    final parts = <ApiContentPart>[];
    if (m.textContent.isNotEmpty) parts.add(ApiContentPart.text(m.textContent));
    for (final c in m.content) {
      if (c.type == ui.MessageContentType.image && c.value.startsWith('data:')) {
        parts.add(ApiContentPart.imageUrl(c.value));
      }
    }
    return AgentMessage(role: role, parts: parts);
  }

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
  factory ChatTurnEvent.artifact(Artifact artifact) = ChatArtifact;
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
  const ChatArtifact(this.artifact);
}

class ChatDone extends ChatTurnEvent {
  final String text;
  final List<Artifact> artifacts;
  const ChatDone({required this.text, required this.artifacts});
}
