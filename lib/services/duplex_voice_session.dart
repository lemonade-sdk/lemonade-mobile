import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:vad/vad.dart';

import '../api/lemonade_client.dart';
import '../api/realtime/realtime_audio_socket.dart';
import '../api/types/chat_message.dart';
import '../api/types/chat_request.dart';
import '../models/chat_message.dart' as ui;
import '../omni/agent_loop.dart';
import '../omni/capability_resolver.dart';
import '../omni/message_mapper.dart';
import '../omni/tool_executor.dart';
import 'audio_recorder_service.dart';
import 'audio_transcription_service.dart';
import 'data_url_audio_source.dart';
import 'noise_suppressor.dart';
import 'tts_service.dart';
import 'voice_record_config.dart';

/// Drives a half-duplex voice conversation:
///   1. Listen on the mic; stream PCM16 to ASR via WebSocket.
///   2. Once a final transcript arrives, stop mic.
///   3. Send transcript through `/v1/chat/completions` (non-streaming).
///   4. Synthesize the assistant reply via `/v1/audio/speech` and play it.
///   5. Once playback ends, restart mic for the next turn.
///
/// Full-duplex (interruption) is intentionally out of scope here — the user
/// can tap the hang-up button or the pause toggle to stop the loop.
class DuplexVoiceSession {
  final LemonadeApiClient client;
  final String llmModel;
  final String? ttsModel;
  final String asrModel;
  final List<ui.ChatMessage> history;

  /// Optional. When provided alongside [executor] and the LLM advertises
  /// tool-calling, each turn runs through [AgentLoop] so the model can
  /// invoke generate_image / text_to_speech / etc. by intent.
  final CapabilitySnapshot? capabilities;
  final OmniToolExecutor? executor;

  final RealtimeAudioSocket _ws;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<RealtimeEvent>? _eventsSub;
  StreamSubscription<RealtimeConnectionState>? _wsStateSub;
  StreamSubscription<Uint8List>? _pcmSub;

  final _state = StreamController<DuplexState>.broadcast();
  final _events = StreamController<DuplexEvent>.broadcast();

  bool _running = false;
  bool _disposed = false;
  bool _recorderDisposed = false;

  /// Bumped by [stop]/[dispose] so `start()` (and other awaited work) can
  /// detect it was superseded mid-await and bail out without resurrecting a
  /// stopped session.
  int _epoch = 0;

  /// Re-entrancy guard: servers can emit multiple `completed` events for one
  /// utterance; only the first may run a turn (mirrors voice_mode's
  /// `_committing`). Reset when a new listening window opens.
  bool _turnInProgress = false;

  /// Mirrors the realtime socket's connection state so the mic stream can
  /// pause pushing audio into a dead sink while the socket reconnects.
  RealtimeConnectionState _wsState = RealtimeConnectionState.disconnected;

  /// Last state pushed through [_emitState]; lets the WS-state handler show a
  /// transient "connecting" cue only while we're in a listening window.
  DuplexState _currentState = DuplexState.idle;

  String _liveTranscript = '';

  // ── Non-WebSocket fallback ──────────────────────────────────────────
  // When the server doesn't expose the realtime `/realtime` WS (or it's
  // unreachable), we downgrade to Silero VAD end-of-utterance + HTTP
  // transcription via `/audio/transcriptions`.
  bool _httpFallback = false;
  AudioTranscriptionService? _transcriber;

  /// Silero VAD — client-side end-of-speech (ported from the old voice_mode
  /// stack). One handler per call; reused across listening windows so the
  /// ONNX model isn't reloaded every turn.
  VadHandler? _vadHandler;
  StreamSubscription? _vadSpeechStartSub;
  StreamSubscription? _vadSpeechEndSub;
  StreamSubscription? _vadMisfireSub;

  /// Completer resolved by [RealtimeCompleted] after we [commit] the buffer.
  Completer<String>? _pendingFinal;

  /// Process-level flag: [AudioSession] voiceChat config is once-per-process.
  static bool _audioSessionConfigured = false;

  /// PCM16 chunks captured during the current utterance. Cleared at the start
  /// of every listening turn and consumed on commit so TalkScreen can persist
  /// the user's audio alongside the transcript.
  final List<List<int>> _utterancePcm = <List<int>>[];

  DuplexVoiceSession({
    required this.client,
    required this.llmModel,
    required this.asrModel,
    required this.ttsModel,
    required this.history,
    this.capabilities,
    this.executor,
  }) : _ws = RealtimeAudioSocket.forClient(client);

  bool get _toolCallingEnabled =>
      capabilities != null &&
      capabilities!.isUsable &&
      executor != null;

  Stream<DuplexState> get state => _state.stream;
  Stream<DuplexEvent> get events => _events.stream;

  Future<void> start() async {
    if (_running || _disposed) return;
    _running = true;
    final epoch = _epoch;
    _emitState(DuplexState.connecting);

    // OS voice-processing (iOS AEC/NS via voiceChat mode) before the mic opens.
    await _ensureAudioSession();
    if (epoch != _epoch) return;
    try {
      await NoiseSuppressor.instance.warmUp();
    } catch (_) {}
    if (epoch != _epoch) return;

    final svc = AudioTranscriptionService(client);
    _transcriber = svc;
    try {
      final wsPort = await svc.discoverWebSocketPort();
      if (epoch != _epoch) return; // stop()/dispose() raced the discovery
      _wsStateSub = _ws.state.listen(_handleWsState);
      await _ws.connect(model: asrModel, port: wsPort);
      if (epoch != _epoch) {
        // stop()/dispose() raced the handshake — don't leave a half-open WS
        // driving a stopped session.
        await _ws.close();
        return;
      }
      _eventsSub = _ws.events.listen(_handleAsrEvent);
    } catch (e) {
      if (epoch != _epoch) return;
      // The realtime WS doesn't exist here or couldn't be opened — downgrade
      // to Silero VAD + HTTP transcription.
      AudioTranscriptionService.invalidateWebSocketPortCache(client.server);
      _httpFallback = true;
    }
    if (epoch != _epoch) return;
    await _beginListening();
  }

  Future<void> stop() async {
    _running = false;
    _epoch++;
    if (!(_pendingFinal?.isCompleted ?? true)) {
      _pendingFinal!.complete('');
    }
    _pendingFinal = null;
    await _stopListening();
    try {
      await _player.stop();
    } catch (_) {}
    await _ws.close();
    await _disposeRecorder();
    _emitState(DuplexState.idle);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Full stop: swipe-back off TalkScreen lands here without stop() — the
    // mic must never stay hot after the session object is gone.
    _running = false;
    _epoch++;
    await _stopVad();
    try {
      _vadHandler?.dispose();
    } catch (_) {}
    _vadHandler = null;
    try {
      await NoiseSuppressor.instance.dispose();
    } catch (_) {}
    await _eventsSub?.cancel();
    _eventsSub = null;
    await _wsStateSub?.cancel();
    _wsStateSub = null;
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _disposeRecorder();
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _player.dispose();
    } catch (_) {}
    await _ws.dispose();
    await _state.close();
    await _events.close();
  }

  /// Stop + dispose the recorder exactly once (stop() and dispose() may both
  /// run; the record plugin doesn't like double-dispose).
  Future<void> _disposeRecorder() async {
    if (_recorderDisposed) return;
    _recorderDisposed = true;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
    try {
      await _recorder.dispose();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Listening loop
  // ---------------------------------------------------------------------------

  Future<void> _beginListening() async {
    if (!_running || _recorderDisposed) return;
    _liveTranscript = '';
    _utterancePcm.clear();
    _turnInProgress = false;
    if (!(_pendingFinal?.isCompleted ?? true)) {
      _pendingFinal!.complete('');
    }
    _pendingFinal = null;
    _emitEvent(DuplexEvent.transcriptUpdate(''));
    _emitEvent(const DuplexHearing(false));
    _emitState(DuplexState.listening);

    final stream = await _recorder.startStream(kVoicePcm16Config);
    if (!_running || _recorderDisposed) {
      try {
        await _recorder.stop();
      } catch (_) {}
      return;
    }

    // Fan PCM to WS/buffer AND Silero VAD (single mic owner).
    final broadcast = stream.asBroadcastStream();
    _pcmSub = broadcast.listen(_handlePcmChunk, onError: (Object e) {
      if (_running) _emitEvent(DuplexEvent.error('Mic stream error: $e'));
    });

    await _startVad(broadcast);
  }

  void _handlePcmChunk(Uint8List raw) {
    if (!_running || _turnInProgress) return;
    // Layer 3 denoise (no-op today); WS + buffer see the same cleaned audio.
    final chunk = NoiseSuppressor.instance.process(raw);
    _utterancePcm.add(chunk);
    if (!_httpFallback && _wsState == RealtimeConnectionState.connected) {
      _ws.appendAudio(base64Encode(chunk));
    }
  }

  Future<void> _startVad(Stream<Uint8List> broadcast) async {
    await _stopVad();
    try {
      _vadHandler ??= VadHandler.create(isDebug: false);
      _vadSpeechStartSub = _vadHandler!.onSpeechStart.listen((_) {
        if (_running && !_turnInProgress) {
          _emitEvent(const DuplexHearing(true));
        }
      });
      _vadSpeechEndSub = _vadHandler!.onSpeechEnd.listen((_) {
        unawaited(_commitUtterance());
      });
      _vadMisfireSub = _vadHandler!.onVADMisfire.listen((_) {
        if (_running && !_turnInProgress) {
          _emitEvent(const DuplexHearing(false));
        }
      });
      await _vadHandler!.startListening(
        audioStream: broadcast,
        positiveSpeechThreshold: 0.45,
        negativeSpeechThreshold: 0.30,
        minSpeechFrames: 3,
        // ~2.3s trailing silence at 96ms/frame — natural breathing room.
        redemptionFrames: 24,
        model: 'v5',
      );
    } catch (e) {
      // VAD failed to load — still stream to WS (server VAD) or error in HTTP mode.
      if (_httpFallback && _running) {
        _emitEvent(DuplexEvent.error(
            'Voice activity detection failed to start: $e'));
      }
    }
  }

  Future<void> _stopVad() async {
    try {
      await _vadSpeechStartSub?.cancel();
      await _vadSpeechEndSub?.cancel();
      await _vadMisfireSub?.cancel();
    } catch (_) {}
    _vadSpeechStartSub = null;
    _vadSpeechEndSub = null;
    _vadMisfireSub = null;
    try {
      await _vadHandler?.stopListening();
    } catch (_) {}
  }

  /// Configure OS audio session once per process (iOS voiceChat AEC/NS).
  Future<void> _ensureAudioSession() async {
    if (_audioSessionConfigured) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
                AVAudioSessionCategoryOptions.allowBluetooth |
                AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      await session.setActive(true);
      _audioSessionConfigured = true;
    } catch (_) {
      // Non-fatal — mic still works without OS voice processing.
    }
  }

  /// Track the realtime socket's health. Reconnects show a transient
  /// "connecting" cue while a listening window is open; a terminal `failed`
  /// silently downgrades the rest of the call to HTTP transcription so the
  /// session heals instead of looping deaf.
  void _handleWsState(RealtimeConnectionState s) {
    final prev = _wsState;
    _wsState = s;
    if (!_running || _httpFallback) return;
    switch (s) {
      case RealtimeConnectionState.reconnecting:
        if (_currentState == DuplexState.listening) {
          _emitState(DuplexState.connecting);
        }
      case RealtimeConnectionState.connected:
        if (prev == RealtimeConnectionState.reconnecting &&
            _currentState == DuplexState.connecting) {
          _emitState(DuplexState.listening);
        }
      case RealtimeConnectionState.failed:
        _httpFallback = true;
        if (_currentState == DuplexState.connecting) {
          _emitState(DuplexState.listening);
        }
      case RealtimeConnectionState.disconnected:
      case RealtimeConnectionState.connecting:
      case RealtimeConnectionState.error:
        break;
    }
  }

  Future<void> _stopListening() async {
    await _stopVad();
    await _pcmSub?.cancel();
    _pcmSub = null;
    if (_recorderDisposed) return;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // End-of-utterance commit (Silero VAD → ASR → turn)
  // ---------------------------------------------------------------------------

  /// Client VAD decided the user stopped speaking. Stop the mic, get a final
  /// transcript (WS commit or HTTP), then run the LLM turn.
  Future<void> _commitUtterance() async {
    if (_turnInProgress || !_running) return;
    _turnInProgress = true;
    await _stopListening();

    final pcm = List<List<int>>.from(_utterancePcm);
    _utterancePcm.clear();
    if (pcm.isEmpty) {
      if (_running) await _beginListening();
      return;
    }

    Uint8List? wav;
    try {
      wav = AudioRecorderService.buildWavBytes(pcm);
    } catch (_) {}

    String text = '';
    if (_httpFallback) {
      _emitState(DuplexState.thinking);
      if (wav != null && _transcriber != null) {
        try {
          text = await _transcriber!.transcribeWavBytes(wav, model: asrModel);
        } catch (e) {
          if (_running) {
            _emitEvent(DuplexEvent.error('Transcription error: $e'));
          }
        }
      }
    } else {
      _pendingFinal = Completer<String>();
      try {
        _ws.commit();
      } catch (_) {}
      try {
        text = await _pendingFinal!.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => _liveTranscript,
        );
      } catch (_) {
        text = _liveTranscript;
      }
    }

    if (!_running) return;
    text = text.trim();
    if (text.isEmpty) {
      if (_running) await _beginListening();
      return;
    }

    _emitEvent(DuplexUserSpoke(
      text,
      audioBase64: wav == null ? null : base64Encode(wav),
      audioMime: wav == null ? null : 'audio/wav',
    ));
    await _runTurn(text);
  }

  // ---------------------------------------------------------------------------
  // ASR events (WS mode)
  // ---------------------------------------------------------------------------

  Future<void> _handleAsrEvent(RealtimeEvent ev) async {
    switch (ev) {
      case RealtimeDelta():
        _emitEvent(const DuplexHearing(true));
        _liveTranscript = '$_liveTranscript${ev.text}';
        _emitEvent(DuplexEvent.transcriptUpdate(_liveTranscript));
      case RealtimeCompleted():
        final finalText =
            ev.transcript.isNotEmpty ? ev.transcript : _liveTranscript;
        // Prefer completing a pending commit (client VAD path). If the server
        // also auto-finalizes without our commit, only start a turn when we
        // aren't already committing (avoids double-turns).
        if (!(_pendingFinal?.isCompleted ?? true)) {
          _pendingFinal!.complete(finalText);
          return;
        }
        if (_turnInProgress || finalText.trim().isEmpty) return;
        _turnInProgress = true;
        await _stopListening();
        final pcm = List<List<int>>.from(_utterancePcm);
        _utterancePcm.clear();
        String? audioBase64;
        if (pcm.isNotEmpty) {
          try {
            audioBase64 =
                base64Encode(AudioRecorderService.buildWavBytes(pcm));
          } catch (_) {}
        }
        _emitEvent(DuplexUserSpoke(
          finalText,
          audioBase64: audioBase64,
          audioMime: audioBase64 == null ? null : 'audio/wav',
        ));
        await _runTurn(finalText);
      case RealtimeError():
        if (!_httpFallback) _emitEvent(DuplexEvent.error(ev.message));
      case RealtimeInfo():
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // LLM + TTS
  // ---------------------------------------------------------------------------

  Future<void> _runTurn(String userText) async {
    if (!_running) return;
    _emitState(DuplexState.thinking);
    _emitEvent(DuplexEvent.transcriptUpdate(''));
    _liveTranscript = '';

    history.add(ui.ChatMessage.text(role: ui.MessageRole.user, text: userText));

    String reply;
    var ttsArtifacts = const <Artifact>[];
    var imageArtifacts = const <Artifact>[];

    try {
      final result = _toolCallingEnabled
          ? await _runAgentTurn()
          : await _runPlainTurn();
      reply = result.text;
      ttsArtifacts = result.artifacts
          .where((a) => a.kind == ArtifactKind.audio)
          .toList(growable: false);
      imageArtifacts = result.artifacts
          .where((a) => a.kind == ArtifactKind.image)
          .toList(growable: false);
    } catch (e) {
      if (!_running) return;
      _emitEvent(DuplexEvent.error('LLM error: $e'));
      await _beginListening();
      return;
    }
    // Hung up while the LLM was thinking — drop the reply.
    if (!_running) return;

    // Persist the assistant turn into the in-memory transcript. Image and
    // audio artifacts ride along so the talk_screen can fold them into the
    // chat thread when the user hangs up.
    final assistantParts = <ui.MessageContent>[];
    if (reply.isNotEmpty) {
      assistantParts.add(ui.MessageContent(
        type: ui.MessageContentType.text,
        value: reply,
      ));
    }
    for (final art in imageArtifacts) {
      final url = 'data:${art.mime};base64,${art.base64Data}';
      assistantParts.add(ui.MessageContent(
        type: ui.MessageContentType.image,
        value: url,
      ));
      _emitEvent(DuplexEvent.artifact(art));
    }
    // Resolve the audio we'll speak: prefer audio the agent already synthesized
    // (text_to_speech); otherwise synthesize a fresh TTS pass NOW so the spoken
    // reply can be both played AND recorded into the chat thread. (Previously
    // the fresh TTS was produced after emitting the event and thrown away, so
    // the AI's voice never made it into chat history.)
    var spokenAudio = List<Artifact>.from(ttsArtifacts);
    if (spokenAudio.isEmpty && ttsModel != null && reply.isNotEmpty) {
      try {
        // Cached synthesis — repeated phrases don't hit the server again.
        final tts = await TtsService.synthesize(
          client: client,
          model: ttsModel!,
          text: reply,
        );
        spokenAudio = [
          Artifact(
            kind: ArtifactKind.audio,
            mime: tts.mime,
            base64Data: base64Encode(tts.bytes),
          ),
        ];
      } catch (e) {
        if (_running) _emitEvent(DuplexEvent.error('TTS error: $e'));
      }
    }
    if (!_running) return;

    for (final art in spokenAudio) {
      final url = 'data:${art.mime};base64,${art.base64Data}';
      assistantParts.add(ui.MessageContent(
        type: ui.MessageContentType.audio,
        value: url,
      ));
      _emitEvent(DuplexEvent.artifact(art));
    }
    if (assistantParts.isEmpty) {
      await _beginListening();
      return;
    }
    history.add(ui.ChatMessage(
      role: ui.MessageRole.assistant,
      content: assistantParts,
    ));
    _emitEvent(DuplexAssistantSpoke(
      reply,
      audioArtifacts: spokenAudio,
      imageArtifacts: imageArtifacts,
    ));

    // Speak the resolved audio.
    _emitState(DuplexState.speaking);
    if (spokenAudio.isNotEmpty) {
      try {
        final art = spokenAudio.last;
        await _playDataUrl('data:${art.mime};base64,${art.base64Data}');
      } catch (e) {
        _emitEvent(DuplexEvent.error('TTS error: $e'));
      }
    }

    if (_running) await _beginListening();
  }

  Future<_TurnResult> _runAgentTurn() async {
    final loop = AgentLoop(
      client: client,
      llmModelId: llmModel,
      capabilities: capabilities!,
      executor: executor!,
    );
    final agentHistory = history.map(_toAgentMessage).toList(growable: false);
    final artifacts = <Artifact>[];
    var text = '';
    await for (final ev in loop.run(
      history: agentHistory,
      extraSystemPrompt:
          'Keep spoken replies short and natural — one or two sentences. '
          'If the user asks for an image, call generate_image. If they ask '
          'you to read or recite something, call text_to_speech. Otherwise '
          'just reply with text.',
    )) {
      switch (ev) {
        case AgentDelta():
          // Voice speaks the FINAL text; live tokens aren't voiced.
          break;
        case AgentStatus():
          // Surface intermediate status (e.g., "Generating image…") so the
          // UI doesn't sit on the listening pulse during long tool runs.
          _emitEvent(DuplexEvent.transcriptUpdate(ev.message));
        case AgentArtifact():
          artifacts.add(ev.artifact);
        case AgentEndCall():
          // TalkScreen owns its own hang-up affordance; ignore.
          break;
        case AgentDone():
          text = ev.text.trim();
          artifacts
            ..clear()
            ..addAll(ev.artifacts);
      }
    }
    return _TurnResult(text: text, artifacts: artifacts);
  }

  Future<_TurnResult> _runPlainTurn() async {
    final messages = <ApiChatMessage>[
      const ApiChatMessage(
        role: WireRole.system,
        content:
            'You are a helpful conversational assistant. Keep responses brief and natural for spoken delivery.',
      ),
      ...history.map((m) => m.isUser
          ? ApiChatMessage.user(m.textContent)
          : ApiChatMessage.assistant(m.textContent)),
    ];
    final resp = await client.chat.create(ChatCompletionRequest(
      model: llmModel,
      messages: messages,
      stream: false,
    ));
    return _TurnResult(
      text: resp.message.content?.trim() ?? '',
      artifacts: const [],
    );
  }

  AgentMessage _toAgentMessage(ui.ChatMessage m) => agentMessageFromUi(m);

  Future<void> _playDataUrl(String dataUrl) async {
    await _player.setAudioSource(DataUrlAudioSource(dataUrl));
    await _player.play();
    // Tolerate stop(): `_player.stop()` flips the state away from a pending
    // `completed`, and the `!_running` predicate releases the wait. The hard
    // timeout keeps a wedged decoder from hanging the turn forever.
    await _player.processingStateStream
        .firstWhere((s) => s == ProcessingState.completed || !_running)
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () => ProcessingState.completed,
        );
  }

  void _emitState(DuplexState s) {
    _currentState = s;
    if (_state.isClosed) return;
    _state.add(s);
  }

  void _emitEvent(DuplexEvent ev) {
    if (_events.isClosed) return;
    _events.add(ev);
  }
}

enum DuplexState { idle, connecting, listening, thinking, speaking }

sealed class DuplexEvent {
  const DuplexEvent();

  factory DuplexEvent.transcriptUpdate(String text) = DuplexTranscriptUpdate;
  factory DuplexEvent.artifact(Artifact artifact) = DuplexArtifactEvent;
  factory DuplexEvent.error(String message) = DuplexErrorEvent;
}

class DuplexArtifactEvent extends DuplexEvent {
  final Artifact artifact;
  const DuplexArtifactEvent(this.artifact);
}

class _TurnResult {
  final String text;
  final List<Artifact> artifacts;
  const _TurnResult({required this.text, required this.artifacts});
}

class DuplexTranscriptUpdate extends DuplexEvent {
  final String text;
  const DuplexTranscriptUpdate(this.text);
}

class DuplexUserSpoke extends DuplexEvent {
  final String text;
  /// Base64-encoded WAV of the spoken utterance, if the mic stream produced
  /// any PCM. May be null when the recognizer fires without captured audio
  /// (e.g. a server-side replay of a prior utterance).
  final String? audioBase64;
  final String? audioMime;
  const DuplexUserSpoke(
    this.text, {
    this.audioBase64,
    this.audioMime,
  });
}

class DuplexAssistantSpoke extends DuplexEvent {
  final String text;
  final List<Artifact> audioArtifacts;
  final List<Artifact> imageArtifacts;
  const DuplexAssistantSpoke(
    this.text, {
    this.audioArtifacts = const [],
    this.imageArtifacts = const [],
  });
}

class DuplexErrorEvent extends DuplexEvent {
  final String message;
  const DuplexErrorEvent(this.message);
}

/// Speech-activity cue: true when the mic is picking up the user's voice, false
/// when a fresh listening window opens. Drives the "Hearing you…" indicator.
class DuplexHearing extends DuplexEvent {
  final bool active;
  const DuplexHearing(this.active);
}


