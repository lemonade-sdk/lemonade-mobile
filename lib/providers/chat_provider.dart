import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/lemonade_client.dart';
import '../api/types/chat_message.dart';
import '../api/types/chat_request.dart';
import '../constants/messages.dart';
import '../models/chat_message.dart';
import '../omni/cancel_token.dart';
import '../omni/tool_executor.dart';
import '../providers/chat_history_provider.dart';
import '../providers/lemonade_client_provider.dart';
import '../providers/models_provider.dart';
import '../providers/omni_router_provider.dart';
import '../providers/servers_provider.dart';
import '../services/chat_service.dart';
import '../storage/file_storage.dart';
import '../utils/friendly_error.dart';

/// Active chat messages. Mirrors whatever ChatHistory the chat-history provider
/// has marked active, plus any in-flight assistant placeholder.
final chatProvider =
    StateNotifierProvider<ChatNotifier, List<ChatMessage>>((ref) => ChatNotifier(ref));

/// True while a chat turn is in flight. The composer uses this to swap the
/// send button for a stop button and to block double-sends.
final chatStreamingProvider = StateProvider<bool>((ref) => false);

/// How long token-driven persistence coalesces before hitting disk. Every
/// streamed token updates in-memory state immediately (smooth UI); the
/// full-transcript Isar write only runs at most once per this window, plus a
/// mandatory flush at turn end.
const Duration _kPersistDebounce = Duration(milliseconds: 400);

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

  /// Live subscription for the in-flight turn stream. [stopStreaming] cancels
  /// it immediately so Stop works even when SSE is idle (no events to trip
  /// the `_stopRequested` check inside `await for`).
  StreamSubscription<ChatTurnEvent>? _turnSub;

  /// Cooperative cancel for the agent loop / tools (in addition to stream
  /// subscription cancel).
  CancelToken? _cancelToken;

  /// The uuid of the chat the in-flight turn belongs to. Captured at turn
  /// start; ALL persistence and state updates during the turn key off this,
  /// never off "whichever chat is active" — switching or deleting chats while
  /// tokens stream must not clobber another chat's log.
  String? _turnChatId;

  /// Bumped when an in-flight turn's writes must be abandoned (clearChat on
  /// the streaming chat). Writes capture the epoch at turn start and drop
  /// themselves when it moved on.
  int _turnEpoch = 0;

  Timer? _persistTimer;

  /// Ask the in-flight turn to stop.
  ///
  /// OpenAI-compatible Completions define **no cancel request** — Stop is
  /// dropping the HTTP connection ([LemonadeApiClient.abortInFlight]).
  /// Locally we also flip [CancelToken] so the omni tool loop does not start
  /// another tool after the stream dies, and cancel the Dart subscription.
  ///
  /// Keeps whatever text/artifacts have already arrived.
  void stopStreaming() {
    _stopRequested = true;
    _cancelToken?.cancel();
    unawaited(_turnSub?.cancel());
    // Spec: no cancel RPC — close the client (TCP) to abort mid-body SSE.
    ref.read(lemonadeClientProvider)?.abortInFlight();
  }

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
    // The vision check is a PLAIN-model rule: a bare LLM that can't see must
    // not receive image parts. A Collection routes attachments through the
    // omni pipeline instead (analyze_image / edit_image / placeholder
    // stripping), so gating on the wire component's labels here wrongly
    // blocked image sends on collections whose vision/image capability lives
    // in a DIFFERENT component.
    if (hasImages && !ref.read(selectedIsCollectionProvider)) {
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
    // The composer fires this unawaited — it must never throw into the void.
    try {
      await _sendMessage(message,
          imagePaths: imagePaths, scrollController: scrollController);
    } catch (e, st) {
      debugPrint('sendMessage failed: $e\n$st');
      _sending = false;
      ref.read(chatStreamingProvider.notifier).state = false;
      try {
        await _appendError(friendlyError(e, action: 'send your message'));
      } catch (_) {
        // Even the error bubble failed — nothing left to do but log above.
      }
    }
  }

  Future<void> _sendMessage(
    String message, {
    List<String>? imagePaths,
    ScrollController? scrollController,
  }) async {
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
    if (hasImages &&
        !modelInfo.supportsVision &&
        !ref.read(selectedIsCollectionProvider)) {
      await _appendError(AppMessages.visionModelServerError(selectedModel));
      return;
    }

    debugPrint('Chat turn → wire model "$selectedModel" '
        '(selected "${ref.read(selectedModelProvider)}")');

    _sending = true;
    _stopRequested = false;
    _cancelToken = CancelToken();
    ref.read(chatStreamingProvider.notifier).state = true;
    String? completedChatId;
    try {
      completedChatId = await _runTurn(
        message,
        imagePaths: imagePaths,
        scrollController: scrollController,
        selectedModel: selectedModel,
        cancelToken: _cancelToken!,
      );
    } finally {
      _sending = false;
      _cancelToken = null;
      ref.read(chatStreamingProvider.notifier).state = false;
    }

    // Auto-titling runs AFTER the composer is unblocked — it used to be
    // awaited inside the turn, keeping the send button dead for up to 20 s
    // after the reply visibly finished. It's keyed to the turn's chat uuid
    // and fully best-effort (swallows its own errors).
    if (completedChatId != null) {
      final client = ref.read(lemonadeClientProvider);
      if (client != null) {
        unawaited(_maybeAutoTitle(client, selectedModel, completedChatId));
      }
    }
  }

  /// Runs one chat turn. Returns the turn's chat uuid when the turn completed
  /// well enough to consider auto-titling, or null otherwise.
  Future<String?> _runTurn(
    String message, {
    required List<String>? imagePaths,
    required ScrollController? scrollController,
    required String selectedModel,
    required CancelToken cancelToken,
  }) async {
    final hasImages = imagePaths != null && imagePaths.isNotEmpty;
    final historyNotifier = ref.read(chatHistoryProvider.notifier);

    // Capture the turn's chat NOW — every write below keys off this uuid.
    var turnChat = historyNotifier.getActiveChat();
    if (turnChat == null) {
      await historyNotifier.createNewChat();
      turnChat = historyNotifier.getActiveChat();
    }
    if (turnChat == null) return null;
    final chatId = turnChat.id;
    final epoch = _turnEpoch;
    _turnChatId = chatId;

    try {
      // Build & persist the user message immediately.
      final userParts = <MessageContent>[];
      if (message.isNotEmpty) {
        userParts.add(MessageContent(type: MessageContentType.text, value: message));
      }
      if (hasImages) {
        for (final img in imagePaths) {
          userParts.add(MessageContent(
              type: MessageContentType.image, value: await _toImageDataUrl(img)));
        }
      }
      final userMessage = ChatMessage(role: MessageRole.user, content: userParts);
      final history = [...turnChat.messages, userMessage];
      if (!await historyNotifier.updateChat(chatId, history)) return null;
      _scroll(scrollController, animated: true, force: true);

      // Add the assistant placeholder.
      final placeholder = ChatMessage.text(role: MessageRole.assistant, text: '');
      var working = [...history, placeholder];
      if (!await historyNotifier.updateChat(chatId, working)) return null;

      final client = ref.read(lemonadeClientProvider);
      if (client == null) {
        working = _updateAssistant(working,
            chatId: chatId,
            epoch: epoch,
            text: AppMessages.errorNotice(AppMessages.noServerSelected));
        await _flushPersist(chatId, epoch);
        return null;
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
        final maxCtx = ref.read(modelsProvider).where((m) => m.id == selectedModel).map((m) => m.maxContextWindow).firstOrNull;
        final stream = svc.run(
          llmModel: selectedModel,
          history: history,
          omniRouterEnabled: omniEnabled,
          capabilities: caps,
          executor: executor,
          maxContextTokens: maxCtx,
          cancelToken: cancelToken,
        );

        // Bridge the turn stream so [stopStreaming] can cancel immediately
        // (even mid-idle SSE or mid-tool wait at the next event boundary).
        final bridge = StreamController<ChatTurnEvent>();
        _turnSub = stream.listen(
          bridge.add,
          onError: bridge.addError,
          onDone: bridge.close,
          cancelOnError: false,
        );
        try {
          await for (final ev in bridge.stream) {
            if (_stopRequested) break;
            switch (ev) {
              case ChatTokens():
                assistantText += ev.delta;
                working = _updateAssistant(
                  working,
                  chatId: chatId,
                  epoch: epoch,
                  text: assistantText,
                  extra: artifactParts,
                );
                _scroll(scrollController);
              case ChatStatus():
                // Show the status as the in-flight assistant text. Final text
                // overwrites it. A status marks a tool boundary — reset the token
                // buffer so the next iteration's streamed text starts clean
                // instead of appending to the pre-tool planning text.
                assistantText = '';
                working = _updateAssistant(
                  working,
                  chatId: chatId,
                  epoch: epoch,
                  text: ev.message,
                  extra: artifactParts,
                );
              case ChatArtifact():
                final part = await _persistArtifact(ev.artifact);
                if (part != null) {
                  if (ev.replacesPrevious) {
                    // An edit replacing this turn's prior image — swap it out
                    // instead of appending, or generate-then-edit shows both.
                    final lastImgIdx = artifactParts.lastIndexWhere(
                        (p) => p.type == MessageContentType.image);
                    if (lastImgIdx >= 0) {
                      artifactParts[lastImgIdx] = part;
                    } else {
                      artifactParts.add(part);
                    }
                  } else {
                    artifactParts.add(part);
                  }
                }
                working = _updateAssistant(
                  working,
                  chatId: chatId,
                  epoch: epoch,
                  text: assistantText,
                  extra: artifactParts,
                );
                _scroll(scrollController);
              case ChatDone():
                assistantText = ev.text;
                // Reconcile with the turn's final artifact list — it's the
                // ground truth (edits replace, incremental events can drift).
                final rebuilt = <MessageContent>[];
                for (final art in ev.artifacts) {
                  final part = await _persistArtifact(art);
                  if (part != null) rebuilt.add(part);
                }
                if (rebuilt.isNotEmpty || ev.artifacts.isEmpty) {
                  artifactParts
                    ..clear()
                    ..addAll(rebuilt);
                }
                working = _updateAssistant(
                  working,
                  chatId: chatId,
                  epoch: epoch,
                  text: assistantText,
                  extra: artifactParts,
                );
                _scroll(scrollController);
            }
          }
        } finally {
          await _turnSub?.cancel();
          _turnSub = null;
          if (!bridge.isClosed) await bridge.close();
        }
        await _flushPersist(chatId, epoch);
        return chatId;
      } catch (e) {
        // User Stop closes the TCP client mid-body — keep partial content
        // and do NOT paint an error bubble for an intentional abort.
        if (_stopRequested || cancelToken.isCancelled) {
          await _flushPersist(chatId, epoch);
          return assistantText.isNotEmpty || artifactParts.isNotEmpty
              ? chatId
              : null;
        }
        // Keep whatever streamed in (text AND artifacts) — throwing the
        // partial reply away made interruptions doubly destructive — and
        // append a short, friendly notice. The notice carries the
        // error-notice marker so it's stripped from later model payloads
        // instead of being replayed as assistant content forever.
        final notice = AppMessages.errorNotice(
            '⚠ ${friendlyError(e, action: 'get a response')}');
        final text =
            assistantText.isEmpty ? notice : '$assistantText\n\n$notice';
        working = _updateAssistant(
          working,
          chatId: chatId,
          epoch: epoch,
          text: text,
          extra: artifactParts,
        );
        await _flushPersist(chatId, epoch);
        return null;
      }
    } finally {
      _turnChatId = null;
      _persistTimer?.cancel();
      _persistTimer = null;
    }
  }

  /// After the first full exchange, ask the model for a short conversation title
  /// and persist it for the sidebar. Best-effort: any failure leaves the
  /// existing first-message fallback title untouched. Runs detached from the
  /// turn (composer already unblocked), keyed to the turn's chat uuid.
  Future<void> _maybeAutoTitle(
      LemonadeApiClient client, String model, String chatId) async {
    try {
      final notifier = ref.read(chatHistoryProvider.notifier);
      final chat = notifier.getChatById(chatId);
      if (chat == null || chat.title.trim().isNotEmpty) return;

      final msgs = chat.messages;
      final firstUser =
          msgs.where((m) => m.role == MessageRole.user).firstOrNull;
      final firstAssistant =
          msgs.where((m) => m.role == MessageRole.assistant).firstOrNull;
      if (firstUser == null || firstAssistant == null) return;

      String textOf(ChatMessage m) => AppMessages.stripErrorNotices(m.content
          .where((c) => c.type == MessageContentType.text)
          .map((c) => c.value)
          .join(' ')
          .trim());
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

      // Only apply if the chat still exists and is still untitled (guard
      // against deletion or a manual rename mid-flight).
      final still = notifier.getChatById(chatId);
      if (still != null && still.title.trim().isEmpty) {
        await notifier.updateChatTitle(chatId, title);
      }
    } catch (_) {
      // best-effort — keep the first-message fallback title
    }
  }

  /// Rewrites the trailing assistant message IN MEMORY (state update per
  /// token for smooth UI) and schedules a debounced persist. Returns the
  /// updated list, or [messages] unchanged when the write was dropped (turn
  /// aborted, or the chat was deleted mid-turn).
  List<ChatMessage> _updateAssistant(
    List<ChatMessage> messages, {
    required String chatId,
    required int epoch,
    required String text,
    List<MessageContent> extra = const [],
  }) {
    if (epoch != _turnEpoch) return messages; // turn aborted (clearChat)
    final last = messages.last;
    final parts = <MessageContent>[];
    if (text.isNotEmpty) {
      parts.add(MessageContent(type: MessageContentType.text, value: text));
    }
    parts.addAll(extra);
    // Keep [last.id] stable so differential persist rewrites only this row.
    final updated = ChatMessage(
      id: last.id,
      role: MessageRole.assistant,
      content: parts.isEmpty
          ? [MessageContent(type: MessageContentType.text, value: '')]
          : parts,
      timestamp: last.timestamp,
    );
    final next = [...messages.sublist(0, messages.length - 1), updated];
    final ok = ref
        .read(chatHistoryProvider.notifier)
        .updateChatInMemory(chatId, next);
    if (!ok) {
      // The chat was deleted mid-turn — drop the write and wind the turn down.
      _stopRequested = true;
      _persistTimer?.cancel();
      _persistTimer = null;
      return messages;
    }
    _schedulePersist(chatId, epoch);
    return next;
  }

  /// Trailing-debounced persistence: at most one full-transcript disk write
  /// per [_kPersistDebounce] while tokens stream. [_flushPersist] at turn end
  /// (done/stop/error) guarantees nothing stays unsaved longer than a turn.
  void _schedulePersist(String chatId, int epoch) {
    if (_persistTimer != null) return; // one pending write covers this token
    _persistTimer = Timer(_kPersistDebounce, () async {
      _persistTimer = null;
      if (epoch != _turnEpoch) return;
      try {
        await ref.read(chatHistoryProvider.notifier).persistChat(chatId);
      } catch (e) {
        debugPrint('Deferred chat persist failed: $e');
      }
    });
  }

  Future<void> _flushPersist(String chatId, int epoch) async {
    _persistTimer?.cancel();
    _persistTimer = null;
    if (epoch != _turnEpoch) return;
    try {
      await ref.read(chatHistoryProvider.notifier).persistChat(chatId);
    } catch (e) {
      debugPrint('Chat persist flush failed: $e');
    }
  }

  /// The composer hands over picked FILE PATHS, but every wire path (plain
  /// chat history, the agent loop's part builder, binary extraction) forwards
  /// only `data:` URLs and silently drops anything else — so an uploaded
  /// photo rendered in the chat UI yet never reached the model ("I don't see
  /// an image to edit"). Inline the file bytes as a data URL at send time.
  ///
  /// HEIC/HEIF (default iOS camera) is re-encoded to PNG — most image/edit
  /// backends reject `image/heic`.
  Future<String> _toImageDataUrl(String pathOrDataUrl) async {
    if (pathOrDataUrl.startsWith('data:')) return pathOrDataUrl;
    try {
      final bytes = await File(pathOrDataUrl).readAsBytes();
      final ext = pathOrDataUrl.split('.').last.toLowerCase();
      if (ext == 'heic' || ext == 'heif') {
        final png = await _reencodeToPng(bytes);
        if (png != null) {
          return 'data:image/png;base64,${base64Encode(png)}';
        }
      }
      final mime = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        'heic' || 'heif' => 'image/heic',
        _ => 'image/jpeg',
      };
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (_) {
      // Unreadable file — keep the path so the UI can still render it.
      return pathOrDataUrl;
    }
  }

  /// Decode via the platform codec and re-encode as PNG (handles HEIC on iOS).
  Future<List<int>?> _reencodeToPng(List<int> bytes) async {
    try {
      final codec =
          await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
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
    // Marked as an error notice: rendered normally in the bubble, but
    // stripped when later turns build the model payload.
    final errMessage = ChatMessage.text(
        role: MessageRole.assistant, text: AppMessages.errorNotice(text));
    final chatId = _turnChatId ??
        ref.read(chatHistoryProvider.notifier).getActiveChat()?.id;
    if (chatId != null) {
      final chat = ref.read(chatHistoryProvider.notifier).getChatById(chatId);
      final base = chat?.messages ?? state;
      await ref
          .read(chatHistoryProvider.notifier)
          .updateChat(chatId, [...base, errMessage]);
    } else {
      await ref
          .read(chatHistoryProvider.notifier)
          .updateActiveChat([...state, errMessage]);
    }
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
    final activeId =
        ref.read(chatHistoryProvider.notifier).getActiveChat()?.id;
    if (activeId != null && activeId == _turnChatId) {
      // Clearing the chat a turn is streaming into: abandon the turn's
      // remaining writes (epoch bump) and stop the stream — otherwise the
      // very next token would silently undo the clear.
      _turnEpoch++;
      stopStreaming();
      _persistTimer?.cancel();
      _persistTimer = null;
    }
    ref.read(chatHistoryProvider.notifier).updateActiveChat([]);
  }
}

// jsonEncode kept around for any future tool-calls payload persistence.
// ignore: unused_element
String _unused() => jsonEncode({'_': null});
