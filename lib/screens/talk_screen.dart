import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import '../providers/chat_history_provider.dart';
import '../providers/lemonade_client_provider.dart';
import '../providers/model_defaults_provider.dart';
import '../providers/models_provider.dart';
import '../providers/omni_router_provider.dart';
import '../services/duplex_voice_session.dart';
import '../utils/friendly_error.dart';

/// Phone-call-style voice conversation. Pushes as a full-screen route from the
/// chat screen. Uses the active server + selected LLM, plus the configured ASR
/// and TTS models from `globalModelDefaultsProvider`.
///
/// The full back-and-forth is shown live as a running transcript and each turn
/// (the user's spoken audio + its text, and the AI's reply text + spoken audio)
/// is persisted into the active chat as it happens — so the conversation, with
/// playable audio, is in chat history whether or not the call is "ended".
class TalkScreen extends ConsumerStatefulWidget {
  const TalkScreen({super.key});

  @override
  ConsumerState<TalkScreen> createState() => _TalkScreenState();
}

class _Turn {
  final MessageRole role;
  String text;
  _Turn(this.role, this.text);
}

class _TalkScreenState extends ConsumerState<TalkScreen>
    with SingleTickerProviderStateMixin {
  DuplexVoiceSession? _session;
  StreamSubscription? _stateSub;
  StreamSubscription? _eventSub;
  late final AnimationController _pulse;
  final _scroll = ScrollController();

  DuplexState _state = DuplexState.idle;
  bool _hearing = false;
  String _interim = '';
  String? _error;

  // The running transcript shown on screen.
  final List<_Turn> _turns = [];

  // The live chat-history message list we append to per turn. Seeded from the
  // active chat so voice turns land in the same thread.
  List<ChatMessage> _chatMessages = [];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final client = ref.read(lemonadeClientProvider);
    // Use the wire LLM — collapses Collections to their chat-shaped
    // component so the chat call doesn't 500 on the meta-id.
    final llm = ref.read(wireLlmModelProvider);
    if (client == null || llm == null) {
      setState(() => _error = 'Select a server and model first.');
      return;
    }
    final defaults = ref.read(globalModelDefaultsProvider);
    final asr = defaults.audioToTextModel ?? _firstByCapability((m) => m.supportsAudio);
    final tts = defaults.textToAudioModel ?? _firstByCapability((m) => m.supportsTts);
    if (asr == null) {
      setState(() => _error = 'No audio-to-text model is loaded on the server.');
      return;
    }

    final history = ref.read(chatHistoryProvider.notifier).getActiveChat()?.messages ??
        const <ChatMessage>[];
    _chatMessages = List.of(history);

    final caps = ref.read(omniCapabilitiesProvider);
    final exec = ref.read(omniToolExecutorProvider);

    final session = DuplexVoiceSession(
      client: client,
      llmModel: llm,
      asrModel: asr,
      ttsModel: tts,
      history: List.of(history),
      capabilities: caps,
      executor: exec,
    );
    _session = session;

    _stateSub = session.state.listen((s) {
      if (!mounted) return;
      setState(() {
        _state = s;
        // Leaving the listening window clears the "hearing you" cue.
        if (s != DuplexState.listening) _hearing = false;
      });
    });
    _eventSub = session.events.listen((ev) {
      if (!mounted) return;
      switch (ev) {
        case DuplexTranscriptUpdate():
          setState(() {
            _interim = ev.text;
            if (ev.text.trim().isNotEmpty) _hearing = true;
          });
        case DuplexHearing():
          setState(() => _hearing = ev.active);
        case DuplexUserSpoke():
          setState(() {
            if (ev.text.trim().isNotEmpty) {
              _turns.add(_Turn(MessageRole.user, ev.text));
            }
            _interim = '';
            _hearing = false;
          });
          _persistUser(ev);
          _autoScroll();
        case DuplexAssistantSpoke():
          setState(() {
            if (ev.text.trim().isNotEmpty) {
              _turns.add(_Turn(MessageRole.assistant, ev.text));
            }
          });
          _persistAssistant(ev);
          _autoScroll();
        case DuplexArtifactEvent():
          // Artifacts are persisted as part of the assistant turn
          // (DuplexAssistantSpoke); nothing to do here.
          break;
        case DuplexErrorEvent():
          setState(() => _error = ev.message);
      }
    });

    try {
      await session.start();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e, action: 'start the call'));
    }
  }

  String? _firstByCapability(bool Function(ModelInfo) test) {
    final models = ref.read(modelsProvider);
    for (final m in models) {
      if (test(m)) return m.id;
    }
    return null;
  }

  // ── Per-turn persistence into the active chat ─────────────────────────
  // The chat repository writes any `data:` audio/image part to disk on save and
  // reloads it as an inline player/image, so no manual attachment handling here.

  Future<void> _persist() async {
    try {
      await ref
          .read(chatHistoryProvider.notifier)
          .updateActiveChat(List.of(_chatMessages));
    } catch (_) {}
  }

  void _persistUser(DuplexUserSpoke ev) {
    final parts = <MessageContent>[];
    final b64 = ev.audioBase64;
    if (b64 != null && b64.isNotEmpty) {
      parts.add(MessageContent(
        type: MessageContentType.audio,
        value: 'data:${ev.audioMime ?? 'audio/wav'};base64,$b64',
      ));
    }
    if (ev.text.trim().isNotEmpty) {
      parts.add(MessageContent(type: MessageContentType.text, value: ev.text));
    }
    if (parts.isEmpty) return;
    _chatMessages.add(ChatMessage(role: MessageRole.user, content: parts));
    _persist();
  }

  void _persistAssistant(DuplexAssistantSpoke ev) {
    final parts = <MessageContent>[];
    if (ev.text.trim().isNotEmpty) {
      parts.add(MessageContent(type: MessageContentType.text, value: ev.text));
    }
    for (final art in ev.imageArtifacts) {
      parts.add(MessageContent(
        type: MessageContentType.image,
        value: 'data:${art.mime};base64,${art.base64Data}',
      ));
    }
    for (final art in ev.audioArtifacts) {
      parts.add(MessageContent(
        type: MessageContentType.audio,
        value: 'data:${art.mime};base64,${art.base64Data}',
      ));
    }
    if (parts.isEmpty) return;
    _chatMessages.add(ChatMessage(role: MessageRole.assistant, content: parts));
    _persist();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _hangUp() async {
    await _session?.stop();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _eventSub?.cancel();
    _session?.dispose();
    _pulse.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.close), onPressed: _hangUp),
                  const Spacer(),
                  Text('Talk', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 8),
              _StatusIndicator(
                  state: _state, hearing: _hearing, pulse: _pulse, scheme: scheme),
              const SizedBox(height: 14),
              Text(
                _statusLabel(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _hearing ? scheme.primary : null,
                      fontWeight: _hearing ? FontWeight.w700 : null,
                    ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _turns.isEmpty && _interim.isEmpty
                    ? Center(
                        child: Text(
                          'Say something — I\'m listening.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView(
                        controller: _scroll,
                        children: [
                          for (final turn in _turns) ...[
                            _Bubble(
                              text: turn.text,
                              alignRight: turn.role == MessageRole.user,
                              color: turn.role == MessageRole.user
                                  ? scheme.primary
                                  : scheme.surfaceContainerHigh,
                              textColor: turn.role == MessageRole.user
                                  ? scheme.onPrimary
                                  : scheme.onSurface,
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (_interim.isNotEmpty)
                            _Bubble(
                              text: _interim,
                              alignRight: true,
                              color: scheme.primary.withValues(alpha: 0.4),
                              textColor: scheme.onPrimary,
                            ),
                        ],
                      ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _hangUp,
                icon: const Icon(Icons.call_end),
                label: const Text('End call'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel() {
    if (_hearing) return 'Hearing you…';
    switch (_state) {
      case DuplexState.connecting:
        return 'Connecting…';
      case DuplexState.listening:
        return 'Listening — go ahead';
      case DuplexState.thinking:
        return 'Thinking…';
      case DuplexState.speaking:
        return 'Speaking…';
      case DuplexState.idle:
        return 'Idle';
    }
  }
}

class _StatusIndicator extends StatelessWidget {
  final DuplexState state;
  final bool hearing;
  final AnimationController pulse;
  final ColorScheme scheme;

  const _StatusIndicator({
    required this.state,
    required this.hearing,
    required this.pulse,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final color = hearing
        ? scheme.primary
        : switch (state) {
            DuplexState.listening => scheme.primary,
            DuplexState.thinking => Colors.amber,
            DuplexState.speaking => Colors.greenAccent,
            DuplexState.connecting => scheme.outline,
            DuplexState.idle => scheme.outline,
          };
    final icon = hearing
        ? Icons.graphic_eq
        : switch (state) {
            DuplexState.listening => Icons.mic,
            DuplexState.thinking => Icons.psychology_alt,
            DuplexState.speaking => Icons.volume_up,
            DuplexState.connecting => Icons.cable,
            DuplexState.idle => Icons.call,
          };
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final t = pulse.value;
        return Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.12),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5 * t),
                blurRadius: 28 + (t * 16),
                spreadRadius: 4 + (t * 4),
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 98,
              height: 98,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.25 + (t * 0.2)),
              ),
              child: Icon(icon, color: color, size: 46),
            ),
          ),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool alignRight;
  final Color color;
  final Color textColor;

  const _Bubble({
    required this.text,
    required this.alignRight,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text, style: TextStyle(color: textColor, fontSize: 15)),
      ),
    );
  }
}
