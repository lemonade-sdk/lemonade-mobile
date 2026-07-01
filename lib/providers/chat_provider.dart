import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/lemonade_client.dart';
import '../api/types/chat_message.dart';
import '../api/types/chat_request.dart';
import '../constants/messages.dart';
import '../models/chat_message.dart';
import '../omni/tool_executor.dart';
import '../providers/chat_history_provider.dart';
import '../providers/lemonade_client_provider.dart';
import '../providers/models_provider.dart';
import '../providers/omni_router_provider.dart';
import '../providers/servers_provider.dart';
import '../services/chat_service.dart';
import '../storage/file_storage.dart';

/// Active chat messages. Mirrors whatever ChatHistory the chat-history provider
/// has marked active, plus any in-flight assistant placeholder.
final chatProvider =
    StateNotifierProvider<ChatNotifier, List<ChatMessage>>((ref) => ChatNotifier(ref));

/// True while a chat turn is in flight. The composer uses this to swap the
/// send button for a stop button and to block double-sends.
final chatStreamingProvider = StateProvider<bool>((ref) => false);

class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref ref;

  ChatNotifier(this.ref) : super([]) {
    ref.listen(chatHistoryProvider, (_, __) => _syncFromActiveChat());
    _syncFromActiveChat();
  }

  void _syncFromActiveChat() {
    final active = ref.read(chatHistoryProvider.notifier).getActiveChat();
    state = active?.messages ?? [];
  }

  bool _sending = false;
  bool _stopRequested = false;

  /// Ask the in-flight turn to stop after the next event. Keeps whatever text
  /// has already streamed in.
  void stopStreaming() => _stopRequested = true;

  /// Pre-flight check for the composer: returns the reason a send can't start
  /// (no server / no model / non-vision model with an image), or null if it
  /// can. Lets the composer keep the user's text and attachments instead of
  /// discarding them into an error bubble.
  String? sendBlockedReason({bool hasImages = false}) {
    if (ref.read(selectedServerProvider) == null) {
      return AppMessages.noServerSelected;
    }
    final selectedModel = ref.read(wireLlmModelProvider) ?? '';
    if (selectedModel.isEmpty) return AppMessages.noModelSelected;
    if (_modelListOutOfSync()) return AppMessages.modelListSyncing;
    if (hasImages) {
      final modelInfo = ref.read(modelsProvider).firstWhere(
            (m) => m.id == selectedModel,
            orElse: () => ModelInfo(selectedModel, const []),
          );
      if (!modelInfo.supportsVision) {
        return AppMessages.visionModelServerError(selectedModel);
      }
    }
    return null;
  }

  /// True while the selected model isn't present in the fetched model list —
  /// e.g. right after a mode/server switch, before the new catalog lands.
  /// Sending in that window is dangerous: the wire resolver can't decompose a
  /// Collection it can't see, so the raw meta-id (e.g. "NXS-PJX-Chat") goes
  /// to /chat/completions and the node 400s with "not an LLM". When out of
  /// sync, a catalog refresh is kicked off so the state self-heals instead of
  /// blocking forever.
  bool _modelListOutOfSync() {
    final selectedId = ref.read(selectedModelProvider);
    if (selectedId == null) return false;
    final models = ref.read(modelsProvider);
    final outOfSync = models.isEmpty || !models.any((m) => m.id == selectedId);
    if (outOfSync) {
      debugPrint('Model list out of sync: selected="$selectedId", '
          'catalog has ${models.length} entries — refreshing.');
      // Fire-and-forget: re-fetch validates the selection and re-picks a
      // valid default if the saved one is gone.
      ref.read(modelsProvider.notifier).fetchModels();
    }
    return outOfSync;
  }

  Future<void> sendMessage(
    String message, {
    List<String>? imagePaths,
    ScrollController? scrollController,
  }) async {
    if (_sending) return; // one turn at a time — no interleaved histories
    final server = ref.read(selectedServerProvider);
    if (server == null) {
      await _appendError(AppMessages.noServerSelected);
      return;
    }

    // Resolve the actual LLM id. If the user picked a Collection, the
    // wire provider substitutes its chat-shaped component so we don't
    // post the Collection meta-id to /chat/completions (server returns a
    // "GGUF file not found for checkpoint" 500 in that case).
    final selectedModel = ref.read(wireLlmModelProvider) ?? '';
    if (selectedModel.isEmpty) {
      await _appendError(AppMessages.noModelSelected);
      return;
    }

    if (_modelListOutOfSync()) {
      await _appendError(AppMessages.modelListSyncing);
      return;
    }

    final availableModels = ref.read(modelsProvider);
    final modelInfo = availableModels.firstWhere(
      (m) => m.id == selectedModel,
      orElse: () => ModelInfo(selectedModel, const []),
    );

    final hasImages = imagePaths != null && imagePaths.isNotEmpty;
    if (hasImages && !modelInfo.supportsVision) {
      await _appendError(AppMessages.visionModelServerError(selectedModel));
      return;
    }

    debugPrint('Chat turn → wire model "$selectedModel" '
        '(selected "${ref.read(selectedModelProvider)}")');

    _sending = true;
    _stopRequested = false;
    ref.read(chatStreamingProvider.notifier).state = true;
    try {
      await _runTurn(
        message,
        imagePaths: imagePaths,
        scrollController: scrollController,
        selectedModel: selectedModel,
      );
    } finally {
      _sending = false;
      ref.read(chatStreamingProvider.notifier).state = false;
    }
  }

  Future<void> _runTurn(
    String message, {
    required List<String>? imagePaths,
    required ScrollController? scrollController,
    required String selectedModel,
  }) async {
    final hasImages = imagePaths != null && imagePaths.isNotEmpty;

    // Build & persist the user message immediately.
    final userParts = <MessageContent>[];
    if (message.isNotEmpty) {
      userParts.add(MessageContent(type: MessageContentType.text, value: message));
    }
    if (hasImages) {
      for (final dataUrl in imagePaths) {
        userParts.add(MessageContent(type: MessageContentType.image, value: dataUrl));
      }
    }
    final userMessage = ChatMessage(role: MessageRole.user, content: userParts);
    final history = [...state, userMessage];
    await ref.read(chatHistoryProvider.notifier).updateActiveChat(history);
    _scroll(scrollController, animated: true, force: true);

    // Add the assistant placeholder.
    final placeholder = ChatMessage.text(role: MessageRole.assistant, text: '');
    var working = [...history, placeholder];
    await ref.read(chatHistoryProvider.notifier).updateActiveChat(working);

    final client = ref.read(lemonadeClientProvider);
    if (client == null) {
      await _replaceLast(working, AppMessages.noServerSelected);
      return;
    }

    // Force omni mode on for Collection selections — the whole point of a
    // Collection is "use this bundle of components", which is exactly what
    // the agent loop drives. The toggle still controls regular models.
    final omniEnabled = ref.read(omniRouterEnabledProvider) ||
        ref.read(selectedIsCollectionProvider);
    final caps = ref.read(omniCapabilitiesProvider);
    final executor = ref.read(omniToolExecutorProvider);

    final svc = ChatService(client);

    var assistantText = '';
    final artifactParts = <MessageContent>[];

    try {
      final stream = svc.run(
        llmModel: selectedModel,
        history: history,
        omniRouterEnabled: omniEnabled,
        capabilities: caps,
        executor: executor,
      );

      await for (final ev in stream) {
        // Breaking out of the await-for cancels the underlying stream.
        if (_stopRequested) break;
        switch (ev) {
          case ChatTokens():
            assistantText += ev.delta;
            working = await _updateAssistant(
              working,
              text: assistantText,
              extra: artifactParts,
            );
            _scroll(scrollController);
          case ChatStatus():
            // Show the status as the in-flight assistant text. Final text overwrites it.
            working = await _updateAssistant(
              working,
              text: ev.message,
              extra: artifactParts,
            );
          case ChatArtifact():
            final part = await _persistArtifact(ev.artifact);
            if (part != null) artifactParts.add(part);
            working = await _updateAssistant(
              working,
              text: assistantText,
              extra: artifactParts,
            );
            _scroll(scrollController);
          case ChatDone():
            assistantText = ev.text;
            // Replace artifact parts with whatever the agent produced this turn,
            // but don't double-add ones we already persisted incrementally.
            if (artifactParts.isEmpty) {
              for (final art in ev.artifacts) {
                final part = await _persistArtifact(art);
                if (part != null) artifactParts.add(part);
              }
            }
            working = await _updateAssistant(
              working,
              text: assistantText,
              extra: artifactParts,
            );
            _scroll(scrollController);
        }
      }
      await _maybeAutoTitle(client, selectedModel);
    } catch (e) {
      final errText = AppMessages.genericError(e.toString());
      await _replaceLast(working, errText);
    }
  }

  /// After the first full exchange, ask the model for a short conversation title
  /// and persist it for the sidebar. Best-effort: any failure leaves the
  /// existing first-message fallback title untouched.
  Future<void> _maybeAutoTitle(LemonadeApiClient client, String model) async {
    try {
      final notifier = ref.read(chatHistoryProvider.notifier);
      final active = notifier.getActiveChat();
      if (active == null || active.title.trim().isNotEmpty) return;

      final msgs = active.messages;
      final firstUser =
          msgs.where((m) => m.role == MessageRole.user).firstOrNull;
      final firstAssistant =
          msgs.where((m) => m.role == MessageRole.assistant).firstOrNull;
      if (firstUser == null || firstAssistant == null) return;

      String textOf(ChatMessage m) => m.content
          .where((c) => c.type == MessageContentType.text)
          .map((c) => c.value)
          .join(' ')
          .trim();
      final userText = textOf(firstUser);
      final assistantText = textOf(firstAssistant);
      if (userText.isEmpty) return;

      final res = await client.chat.create(
        ChatCompletionRequest(
          model: model,
          messages: [
            ApiChatMessage.system(
                'You generate a concise chat title. Reply with ONLY a 3–6 word '
                'title in Title Case — no quotes, no trailing punctuation, no '
                'prefixes or explanation.'),
            ApiChatMessage.user('First message: $userText\n'
                '${assistantText.isEmpty ? '' : 'Assistant reply: $assistantText\n'}'
                '\nTitle:'),
          ],
          stream: false,
        ),
        timeout: const Duration(seconds: 20),
      );

      var title = (res.message.content ?? '').trim();
      // Sanitize: strip quotes/newlines, a trailing period, and clamp length.
      title = title.replaceAll('"', '').replaceAll('\n', ' ').trim();
      if (title.endsWith('.')) {
        title = title.substring(0, title.length - 1).trim();
      }
      if (title.length > 60) title = '${title.substring(0, 57).trim()}…';
      if (title.isEmpty) return;

      // Only apply if still untitled (guard against a manual rename mid-flight).
      final still = notifier.getActiveChat();
      if (still != null &&
          still.id == active.id &&
          still.title.trim().isEmpty) {
        await notifier.updateChatTitle(active.id, title);
      }
    } catch (_) {
      // best-effort — keep the first-message fallback title
    }
  }

  Future<List<ChatMessage>> _updateAssistant(
    List<ChatMessage> messages, {
    required String text,
    List<MessageContent> extra = const [],
  }) async {
    final last = messages.last;
    final parts = <MessageContent>[];
    if (text.isNotEmpty) {
      parts.add(MessageContent(type: MessageContentType.text, value: text));
    }
    parts.addAll(extra);
    final updated = ChatMessage(
      role: MessageRole.assistant,
      content: parts.isEmpty
          ? [MessageContent(type: MessageContentType.text, value: '')]
          : parts,
      timestamp: last.timestamp,
    );
    final next = [...messages.sublist(0, messages.length - 1), updated];
    await ref.read(chatHistoryProvider.notifier).updateActiveChat(next);
    return next;
  }

  Future<MessageContent?> _persistArtifact(Artifact artifact) async {
    try {
      final ext = '.${artifact.mime.split('/').last}';
      final kind = artifact.kind == ArtifactKind.image ? 'image' : 'audio';
      await AttachmentStore.writeBase64(
        base64Data: artifact.base64Data,
        kind: kind,
        extension: ext,
      );
      final dataUrl = 'data:${artifact.mime};base64,${artifact.base64Data}';
      return MessageContent(
        type: artifact.kind == ArtifactKind.image
            ? MessageContentType.image
            : MessageContentType.audio,
        value: dataUrl,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _appendError(String text) async {
    final errMessage = ChatMessage.text(role: MessageRole.assistant, text: text);
    final next = [...state, errMessage];
    await ref.read(chatHistoryProvider.notifier).updateActiveChat(next);
  }

  Future<void> _replaceLast(List<ChatMessage> working, String text) async {
    final next = [
      ...working.sublist(0, working.length - 1),
      ChatMessage.text(
        role: MessageRole.assistant,
        text: text,
        timestamp: DateTime.now(),
      ),
    ];
    await ref.read(chatHistoryProvider.notifier).updateActiveChat(next);
  }

  void _scroll(ScrollController? controller,
      {bool animated = false, bool force = false}) {
    if (controller == null || !controller.hasClients) return;
    // Don't yank the view to the bottom while the user is reading earlier
    // messages — only follow the stream when already pinned near the bottom.
    final pos = controller.position;
    if (!force && pos.maxScrollExtent - pos.pixels > 160) return;
    if (animated) {
      controller.animateTo(
        controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      controller.jumpTo(controller.position.maxScrollExtent);
    }
  }

  void clearChat() {
    ref.read(chatHistoryProvider.notifier).updateActiveChat([]);
  }
}

// jsonEncode kept around for any future tool-calls payload persistence.
// ignore: unused_element
String _unused() => jsonEncode({'_': null});
