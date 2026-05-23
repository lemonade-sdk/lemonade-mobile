import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:vad/vad.dart';

import '../api/realtime/realtime_audio_socket.dart';
import '../api/types/audio_request.dart';
import '../api/types/chat_message.dart' as api;
import '../api/types/chat_request.dart';
import '../models/chat_message.dart';
import '../omni/agent_loop.dart';
import '../omni/tool_executor.dart';
import '../services/audio_recorder_service.dart';
import '../services/audio_transcription_service.dart';
import '../services/noise_suppressor.dart';
import 'chat_history_provider.dart';
import 'lemonade_client_provider.dart';
import 'model_defaults_provider.dart';
import 'models_provider.dart';
import 'omni_router_provider.dart';

/// Phone-call style voice mode for the chat input.
///
/// Tapping the mic opens a continuous duplex session. While "on the call",
/// the controller continuously streams the mic to the Lemonade ASR socket,
/// runs a client-side VAD to detect when the user has paused, commits the
/// utterance, runs the LLM (through the omni agent loop when available),
/// plays back the assistant's TTS, then resumes listening for the next
/// turn — automatically, like a phone call. Tapping the stop button ends
/// the whole session.
enum VoicePhase { idle, listening, thinking, speaking, error }

class VoiceModeStatus {
  final VoicePhase phase;
  final String? message;

  /// Most recent amplitudes captured from the mic, used by the chat input to
  /// draw a live waveform. Length is capped — see [_amplitudeWindow].
  final List<double> amplitudes;

  const VoiceModeStatus({
    this.phase = VoicePhase.idle,
    this.message,
    this.amplitudes = const [],
  });

  bool get active =>
      phase == VoicePhase.listening ||
      phase == VoicePhase.thinking ||
      phase == VoicePhase.speaking;

  VoiceModeStatus copyWith({
    VoicePhase? phase,
    String? message,
    List<double>? amplitudes,
  }) =>
      VoiceModeStatus(
        phase: phase ?? this.phase,
        message: message,
        amplitudes: amplitudes ?? this.amplitudes,
      );
}

const int _amplitudeWindow = 60;

void _log(String message) {
  developer.log(message, name: 'VoiceMode');
  // ignore: avoid_print
  print('[VoiceMode] $message');
}

class VoiceModeController extends StateNotifier<VoiceModeStatus> {
  final Ref ref;

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _pcmSub;
  RealtimeAudioSocket? _ws;
  StreamSubscription<RealtimeEvent>? _wsSub;
  AudioPlayer? _player;

  /// Silero VAD. We feed it the PCM stream from `_recorder` and listen on
  /// its `onSpeechEnd` to drive end-of-utterance commits. This replaces the
  /// dumb amplitude+timer heuristic — Silero distinguishes speech from
  /// background noise reliably, so pauses-to-think don't get cut off and a
  /// truck driving past doesn't trigger a commit.
  VadHandler? _vadHandler;
  StreamSubscription<List<double>>? _vadSpeechEndSub;
  StreamSubscription<dynamic>? _vadSpeechStartSub;
  StreamSubscription<dynamic>? _vadMisfireSub;

  /// audio_session.configure() is idempotent but only needs to run once per
  /// process; cache the fact we've done it so subsequent calls skip the work.
  bool _audioSessionConfigured = false;

  /// PCM buffered for the *current* utterance (cleared per commit).
  final List<List<int>> _utterancePcm = <List<int>>[];
  String _accumulatedTranscript = '';
  Completer<String>? _pendingFinal;

  /// True once we're connected and accepting audio. Distinct from
  /// state.phase==listening because state may flip into thinking/speaking
  /// while the session is still active in the background.
  bool _callActive = false;

  /// When true, we couldn't open the realtime WS for this call and we'll
  /// transcribe each utterance via HTTP `/audio/transcriptions` instead.
  /// Slightly higher per-turn latency but works on any network that can
  /// reach the HTTP API.
  bool _httpMode = false;

  String? _asrModel;

  /// Re-entrancy guard so a stray onSpeechEnd during commit doesn't fire
  /// a second commit. Reset when listening resumes.
  bool _committing = false;

  VoiceModeController(this.ref) : super(const VoiceModeStatus());

  // ---------------------------------------------------------------------------
  // Public surface — single button drives everything
  // ---------------------------------------------------------------------------

  Future<void> toggle() async {
    if (_callActive) {
      await hangUp();
    } else {
      await startCall();
    }
  }

  Future<void> startCall() async {
    if (_callActive) return;
    _callActive = true;
    _log('startCall()');

    final client = ref.read(lemonadeClientProvider);
    final llm = ref.read(wireLlmModelProvider);
    if (client == null || llm == null) {
      _fail('Select a server and model first.');
      _callActive = false;
      return;
    }
    final defaults = ref.read(globalModelDefaultsProvider);
    final models = ref.read(modelsProvider);
    final asr = defaults.audioToTextModel ??
        _firstModelId(models, (m) => m.supportsAudio);
    if (asr == null) {
      _fail('No audio-to-text model is loaded on the server.');
      _callActive = false;
      return;
    }
    _asrModel = asr;
    _log('using llm=$llm asr=$asr');

    state = const VoiceModeStatus(
      phase: VoicePhase.listening,
      message: 'Connecting…',
      amplitudes: [],
    );

    // 1. Mic first — failure here is unrecoverable.
    try {
      _recorder = AudioRecorder();
      if (!await _recorder!.hasPermission()) {
        _fail(
            'Microphone permission denied. Allow it in System Settings → Privacy → Microphone, then try again.');
        await _teardown();
        _callActive = false;
        return;
      }
    } catch (e) {
      _fail('Mic init failed: $e');
      await _teardown();
      _callActive = false;
      return;
    }

    // 2. Try realtime WS. If it fails for any reason — WS port not
    //    forwarded, server rejected the upgrade, auth failed — drop into
    //    HTTP transcription mode instead of giving up on the call.
    _httpMode = false;
    try {
      final svc = AudioTranscriptionService(client.server);
      final wsPort = await svc.discoverWebSocketPort();
      _log('advertised ws port: $wsPort (will retry on HTTP port if unreachable)');
      _ws = RealtimeAudioSocket.forClient(client);
      await _ws!.connect(model: asr, port: wsPort);
      _log('ws connected (handshake completed)');
      _wsSub = _ws!.events.listen(_handleAsrEvent);
    } catch (e) {
      _log('WS unavailable — falling back to HTTP transcription mode: $e');
      _httpMode = true;
      try {
        await _ws?.dispose();
      } catch (_) {}
      _ws = null;
      state = state.copyWith(
        message: 'Realtime WS unreachable — using HTTP mode',
      );
    }

    try {
      await _startListening();
    } catch (e, st) {
      _log('startCall failed: $e\n$st');
      _fail('Voice mode failed to start: $e');
      await _teardown();
      _callActive = false;
    }
  }

  Future<void> hangUp() async {
    _log('hangUp()');
    _callActive = false;
    try {
      await _player?.stop();
    } catch (_) {}
    await _teardown();
    state = const VoiceModeStatus();
  }

  // ---------------------------------------------------------------------------
  // Listening
  // ---------------------------------------------------------------------------

  Future<void> _startListening() async {
    _log('_startListening');
    _utterancePcm.clear();
    _accumulatedTranscript = '';
    _committing = false;
    state = state.copyWith(
      phase: VoicePhase.listening,
      message: null,
      amplitudes: const [],
    );

    await _ensureAudioSession();

    // RecordConfig picks the native voice-communication audio source on
    // Android, which enables hardware AEC + noise suppression at the
    // platform level (same path FaceTime/Zoom take). On iOS the voice
    // processing IO unit is engaged by audio_session above.
    final stream = await _recorder!.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      androidConfig: AndroidRecordConfig(
        audioSource: AndroidAudioSource.voiceCommunication,
      ),
    ));

    // Fan the PCM stream out to both consumers: the WS / commit pipeline
    // (existing behaviour, still streams live in WS mode) AND the Silero
    // VAD that will tell us when the user has actually stopped talking.
    final broadcast = stream.asBroadcastStream();
    _pcmSub = broadcast.listen(_handlePcmChunk, onError: (e) {
      _log('mic stream error: $e');
      _fail('Mic stream error: $e');
    });

    _vadHandler = VadHandler.create(isDebug: false);
    _vadSpeechStartSub = _vadHandler!.onSpeechStart.listen((_) {
      _log('VAD: speech started');
      // Visual cue only — the live message shows "Listening… speak
      // naturally" by default; this tightens it so the user sees the
      // app reacting to their voice.
      if (state.phase == VoicePhase.listening) {
        state = state.copyWith(message: 'Hearing you…');
      }
    });
    _vadSpeechEndSub = _vadHandler!.onSpeechEnd.listen((_) {
      _log('VAD: speech ended → committing');
      _commitUtterance();
    });
    _vadMisfireSub = _vadHandler!.onVADMisfire.listen((_) {
      // VAD thought it heard speech but the segment was too short to keep.
      // Just clear the indicator so we don't look stuck on "Hearing you…".
      _log('VAD: misfire (too short)');
      if (state.phase == VoicePhase.listening) {
        state = state.copyWith(message: null);
      }
    });

    await _vadHandler!.startListening(
      // We feed our own PCM (so the recorder above is the single mic
      // owner). Without this, the package would try to capture audio
      // itself and we'd have a contention nightmare.
      audioStream: broadcast,
      // Slightly looser thresholds: lets quieter speech in, and "real
      // speech" requires ~3 frames so a stray cough doesn't trigger.
      positiveSpeechThreshold: 0.45,
      negativeSpeechThreshold: 0.30,
      minSpeechFrames: 3,
      // Allow a longer trailing pause before declaring end-of-speech.
      // Each frame is 96 ms at the default 1536-sample frame size, so
      // 24 redemption frames ≈ 2.3 s of silence — natural breathing room.
      redemptionFrames: 24,
      model: 'v5',
    );
  }

  /// Configure the OS audio session once per process. On iOS this engages
  /// AVAudioSession voiceChat mode, which routes input through Apple's
  /// voice-processing IO unit (echo cancellation + noise suppression). On
  /// Android the equivalent kicks in via `voiceCommunication` audio
  /// attributes and the recorder's `voiceCommunication` audio source.
  Future<void> _ensureAudioSession() async {
    if (_audioSessionConfigured) return;
    try {
      final session = await AudioSession.instance;
      // The `|` operator on AVAudioSessionCategoryOptions is non-const,
      // so the whole configuration can't be `const`.
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
      _log('audio session configured for voice call');
    } catch (e) {
      // Non-fatal — the recorder still works, just without OS-level
      // voice processing on iOS.
      _log('audio session configure failed (continuing): $e');
    }
  }

  Future<void> _stopMic() async {
    // Stop Silero first so it doesn't try to process chunks while we're
    // tearing down the mic underneath it.
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
    try {
      _vadHandler?.dispose();
    } catch (_) {}
    _vadHandler = null;

    try {
      await _pcmSub?.cancel();
    } catch (_) {}
    _pcmSub = null;
    try {
      if (_recorder != null && await _recorder!.isRecording()) {
        await _recorder!.stop();
      }
    } catch (_) {}
  }

  void _handlePcmChunk(Uint8List rawChunk) {
    if (!_callActive) return;
    if (state.phase != VoicePhase.listening) return;

    // Pass through the noise suppressor before anything else looks at the
    // audio. The default impl is a no-op (zero overhead); when ML denoise
    // is wired up it kicks in here. Both the WS and the recorded buffer
    // see the cleaned audio so the server's transcript and the user's
    // saved chat clip stay consistent.
    final chunk = NoiseSuppressor.instance.process(rawChunk);

    _utterancePcm.add(chunk);
    // WS mode streams live so the server can emit interim transcript
    // deltas while the user is still speaking. HTTP mode batches and
    // POSTs at commit time.
    if (!_httpMode) {
      _ws?.appendAudio(base64Encode(chunk));
    }

    // Drive the waveform UI. End-of-speech detection is now Silero's
    // job (see `_vadHandler.onSpeechEnd` in `_startListening`), so the
    // amplitude here is purely cosmetic.
    final amp = _amplitudeFromPcm16(chunk);
    final next = [...state.amplitudes, amp];
    if (next.length > _amplitudeWindow) {
      next.removeRange(0, next.length - _amplitudeWindow);
    }
    state = state.copyWith(amplitudes: next);
  }

  // ---------------------------------------------------------------------------
  // ASR events from the realtime socket
  // ---------------------------------------------------------------------------

  void _handleAsrEvent(RealtimeEvent ev) {
    switch (ev) {
      case RealtimeDelta():
        _accumulatedTranscript = '$_accumulatedTranscript${ev.text}';
        _log('asr delta (+${ev.text.length}): $_accumulatedTranscript');
        // Surface interim transcript so the user knows the server's hearing them.
        if (state.phase == VoicePhase.listening) {
          state = state.copyWith(message: _accumulatedTranscript);
        }
      case RealtimeCompleted():
        final t = ev.transcript.isNotEmpty
            ? ev.transcript
            : _accumulatedTranscript;
        _log('asr completed: "$t"');
        if (!(_pendingFinal?.isCompleted ?? true)) {
          _pendingFinal!.complete(t);
        }
      case RealtimeError():
        _log('asr error: ${ev.message}');
        state = state.copyWith(message: 'ASR: ${ev.message}');
      case RealtimeInfo():
        // Ignore session.updated / similar metadata.
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Commit + LLM turn + TTS — runs one full conversational turn
  // ---------------------------------------------------------------------------

  Future<void> _commitUtterance() async {
    if (_committing || !_callActive) return;
    _committing = true;
    _log('_commitUtterance');

    // Stop streaming new audio while we wait for the final transcript and
    // run the LLM. We'll restart the mic after the assistant speaks.
    await _stopMic();
    state = state.copyWith(
      phase: VoicePhase.thinking,
      message: 'Transcribing…',
    );

    final pcm = List<List<int>>.from(_utterancePcm);
    _utterancePcm.clear();
    Uint8List? wavBytes;
    String? userAudioDataUrl;
    if (pcm.isNotEmpty) {
      try {
        wavBytes = AudioRecorderService.buildWavBytes(pcm);
        userAudioDataUrl = 'data:audio/wav;base64,${base64Encode(wavBytes)}';
      } catch (e) {
        _log('wav build failed: $e');
      }
    }

    String transcript = '';
    if (_httpMode) {
      // HTTP path: write the utterance to a temp WAV, POST it to
      // /audio/transcriptions, read back the text. Works on any network
      // that can reach the HTTP API even when the WS port doesn't.
      if (wavBytes != null) {
        try {
          transcript = await _httpTranscribe(wavBytes);
        } catch (e) {
          _log('http transcription failed: $e');
          state = state.copyWith(message: 'Transcription failed: $e');
        }
      }
    } else {
      _pendingFinal = Completer<String>();
      try {
        _ws?.commit();
      } catch (e) {
        _log('ws.commit failed: $e');
      }
      try {
        transcript = await _pendingFinal!.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            _log('timed out waiting for final transcript; using accumulated');
            return _accumulatedTranscript;
          },
        );
      } catch (e) {
        _log('pendingFinal threw: $e');
        transcript = _accumulatedTranscript;
      }
    }
    transcript = transcript.trim();

    if (!_callActive) {
      _log('call ended during commit; abandoning turn');
      return;
    }

    if (transcript.isNotEmpty || userAudioDataUrl != null) {
      await _appendUserMessage(
        transcript: transcript,
        audioDataUrl: userAudioDataUrl,
      );
    }

    if (transcript.isEmpty) {
      _log('empty transcript — skipping LLM turn');
      await _resumeIfStillOnCall();
      return;
    }

    state = state.copyWith(phase: VoicePhase.thinking, message: 'Thinking…');

    var shouldEndCall = false;
    try {
      final reply = await _runLlmTurn(onEndCall: () => shouldEndCall = true);
      if (!_callActive) return;
      await _speakReply(reply);
    } catch (e, st) {
      _log('turn failed: $e\n$st');
      state = state.copyWith(message: 'Reply failed: $e');
    }

    if (shouldEndCall) {
      _log('end_call tool invoked — hanging up after reply');
      await hangUp();
      return;
    }

    await _resumeIfStillOnCall();
  }

  Future<void> _resumeIfStillOnCall() async {
    _committing = false;
    if (!_callActive) return;
    _log('resuming mic for next utterance');
    try {
      await _startListening();
    } catch (e) {
      _log('failed to resume mic: $e');
      _fail('Mic resume failed: $e');
    }
  }

  Future<String> _httpTranscribe(Uint8List wavBytes) async {
    final client = ref.read(lemonadeClientProvider);
    if (client == null) throw StateError('No server selected.');
    final asr = _asrModel ?? '';
    final tmp = await getTemporaryDirectory();
    if (!await tmp.exists()) {
      await tmp.create(recursive: true);
    }
    final path = p.join(
      tmp.path,
      'voice_utterance_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    final f = File(path);
    await f.writeAsBytes(wavBytes, flush: true);
    try {
      _log('http transcribe POST → /audio/transcriptions ($path, model=$asr)');
      final svc = AudioTranscriptionService(client.server);
      final text = await svc.transcribeFile(path, model: asr);
      _log('http transcribe ← "$text"');
      return text;
    } finally {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  Future<_ReplyBundle> _runLlmTurn({void Function()? onEndCall}) async {
    final client = ref.read(lemonadeClientProvider)!;
    final llm = ref.read(wireLlmModelProvider)!;
    final omniEnabled = ref.read(omniRouterEnabledProvider) ||
        ref.read(selectedIsCollectionProvider);
    final caps = ref.read(omniCapabilitiesProvider);
    final executor = ref.read(omniToolExecutorProvider);

    final history =
        ref.read(chatHistoryProvider.notifier).getActiveChat()?.messages ??
            const <ChatMessage>[];

    if (omniEnabled && caps != null && caps.isUsable && executor != null) {
      _log('runLlmTurn via agent loop');
      final agentMessages =
          history.map(_toAgentMessage).toList(growable: false);
      final loop = AgentLoop(
        client: client,
        llmModelId: llm,
        capabilities: caps,
        executor: executor,
      );
      var text = '';
      final artifacts = <Artifact>[];
      await for (final ev in loop.run(
        history: agentMessages,
        extraSystemPrompt:
            'Keep spoken replies short and natural — one or two sentences. '
            'If the user asks for an image, call generate_image. Otherwise '
            'reply with text.',
      )) {
        switch (ev) {
          case AgentStatus():
            state = state.copyWith(
                phase: VoicePhase.thinking, message: ev.message);
          case AgentArtifact():
            artifacts.add(ev.artifact);
          case AgentEndCall():
            _log('agent invoked end_call');
            onEndCall?.call();
          case AgentDone():
            text = ev.text.trim();
            artifacts
              ..clear()
              ..addAll(ev.artifacts);
        }
      }
      _log('agent turn done: text="$text", artifacts=${artifacts.length}');
      return _ReplyBundle(text: text, artifacts: artifacts);
    }

    _log('runLlmTurn via plain chat completion');
    final messages = <api.ApiChatMessage>[
      const api.ApiChatMessage(
        role: api.WireRole.system,
        content:
            'You are a helpful conversational assistant. Keep responses brief and natural for spoken delivery.',
      ),
      ...history.map((m) => m.isUser
          ? api.ApiChatMessage.user(m.textContent)
          : api.ApiChatMessage.assistant(m.textContent)),
    ];
    final resp = await client.chat.create(ChatCompletionRequest(
      model: llm,
      messages: messages,
      stream: false,
    ));
    final text = resp.message.content?.trim() ?? '';
    _log('plain turn done: text="$text"');
    return _ReplyBundle(text: text, artifacts: const []);
  }

  Future<void> _speakReply(_ReplyBundle reply) async {
    final parts = <MessageContent>[];
    if (reply.text.isNotEmpty) {
      parts.add(MessageContent(
        type: MessageContentType.text,
        value: reply.text,
      ));
    }
    final ttsArtifacts =
        reply.artifacts.where((a) => a.kind == ArtifactKind.audio).toList();
    final imageArtifacts =
        reply.artifacts.where((a) => a.kind == ArtifactKind.image).toList();
    for (final art in imageArtifacts) {
      parts.add(MessageContent(
        type: MessageContentType.image,
        value: 'data:${art.mime};base64,${art.base64Data}',
      ));
    }

    String? ttsDataUrl;
    if (ttsArtifacts.isNotEmpty) {
      final art = ttsArtifacts.last;
      ttsDataUrl = 'data:${art.mime};base64,${art.base64Data}';
    } else if (reply.text.isNotEmpty) {
      final ttsModel = ref.read(globalModelDefaultsProvider).textToAudioModel ??
          _firstModelId(ref.read(modelsProvider), (m) => m.supportsTts);
      final client = ref.read(lemonadeClientProvider);
      if (ttsModel != null && client != null) {
        try {
          _log('synthesizing TTS via $ttsModel');
          final tts = await client.audio.speech(TextToSpeechRequest(
            model: ttsModel,
            input: reply.text,
            responseFormat: 'mp3',
          ));
          ttsDataUrl =
              'data:${tts.mime};base64,${base64Encode(tts.audioBytes)}';
        } catch (e) {
          _log('tts failed: $e');
        }
      }
    }
    if (ttsDataUrl != null) {
      parts.add(MessageContent(
        type: MessageContentType.audio,
        value: ttsDataUrl,
      ));
    }
    if (parts.isNotEmpty) {
      final msg = ChatMessage(role: MessageRole.assistant, content: parts);
      final current = ref
              .read(chatHistoryProvider.notifier)
              .getActiveChat()
              ?.messages ??
          const <ChatMessage>[];
      await ref
          .read(chatHistoryProvider.notifier)
          .updateActiveChat([...current, msg]);
    }

    if (ttsDataUrl == null) return;
    state = state.copyWith(phase: VoicePhase.speaking, message: 'Speaking…');
    _player = AudioPlayer();
    try {
      await _player!.setAudioSource(_DataSource(ttsDataUrl));
      await _player!.play();
      await _player!.processingStateStream
          .firstWhere((s) => s == ProcessingState.completed)
          .timeout(const Duration(seconds: 60), onTimeout: () {
        return ProcessingState.completed;
      });
    } catch (e) {
      _log('playback failed: $e');
    } finally {
      try {
        await _player?.dispose();
      } catch (_) {}
      _player = null;
    }
  }

  Future<void> _appendUserMessage({
    required String transcript,
    required String? audioDataUrl,
  }) async {
    final parts = <MessageContent>[];
    if (audioDataUrl != null) {
      parts.add(MessageContent(
        type: MessageContentType.audio,
        value: audioDataUrl,
      ));
    }
    if (transcript.isNotEmpty) {
      parts.add(MessageContent(
        type: MessageContentType.text,
        value: transcript,
      ));
    }
    if (parts.isEmpty) return;
    final msg = ChatMessage(role: MessageRole.user, content: parts);
    final current = ref
            .read(chatHistoryProvider.notifier)
            .getActiveChat()
            ?.messages ??
        const <ChatMessage>[];
    await ref
        .read(chatHistoryProvider.notifier)
        .updateActiveChat([...current, msg]);
  }

  AgentMessage _toAgentMessage(ChatMessage m) {
    final role = m.isUser ? 'user' : 'assistant';
    if (!m.hasImages) {
      return AgentMessage(role: role, text: m.textContent);
    }
    final parts = <api.ApiContentPart>[];
    if (m.textContent.isNotEmpty) {
      parts.add(api.ApiContentPart.text(m.textContent));
    }
    for (final c in m.content) {
      if (c.type == MessageContentType.image && c.value.startsWith('data:')) {
        parts.add(api.ApiContentPart.imageUrl(c.value));
      }
    }
    return AgentMessage(role: role, parts: parts);
  }

  // ---------------------------------------------------------------------------
  // Teardown + helpers
  // ---------------------------------------------------------------------------

  Future<void> _teardown() async {
    _log('_teardown');
    // VAD first — same reasoning as `_stopMic`: stop the consumer before
    // the producer.
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
    try {
      _vadHandler?.dispose();
    } catch (_) {}
    _vadHandler = null;

    try {
      await _pcmSub?.cancel();
    } catch (_) {}
    _pcmSub = null;
    try {
      if (_recorder != null && await _recorder!.isRecording()) {
        await _recorder!.stop();
      }
    } catch (_) {}
    _recorder?.dispose();
    _recorder = null;

    try {
      await _wsSub?.cancel();
    } catch (_) {}
    _wsSub = null;
    try {
      await _ws?.dispose();
    } catch (_) {}
    _ws = null;
  }

  void _fail(String message) {
    _log('FAIL: $message');
    state = VoiceModeStatus(phase: VoicePhase.error, message: message);
  }

  String? _firstModelId(List<ModelInfo> models, bool Function(ModelInfo) test) {
    for (final m in models) {
      if (test(m)) return m.id;
    }
    return null;
  }

  double _amplitudeFromPcm16(Uint8List bytes) {
    if (bytes.length < 2) return 0.0;
    final data = ByteData.sublistView(bytes);
    var maxAmp = 0.0;
    for (var i = 0; i < bytes.length - 1; i += 2) {
      final sample = data.getInt16(i, Endian.little).abs();
      if (sample > maxAmp) maxAmp = sample.toDouble();
    }
    if (maxAmp < 1) return 0.0;
    final dBFS = 20.0 * (log(maxAmp / 32768.0) / ln10);
    final normalized = (dBFS + 60.0) / 60.0;
    return normalized.clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _callActive = false;
    _teardown();
    super.dispose();
  }
}

class _ReplyBundle {
  final String text;
  final List<Artifact> artifacts;
  const _ReplyBundle({required this.text, required this.artifacts});
}

class _DataSource extends StreamAudioSource {
  final List<int> _bytes;
  final String _contentType;

  _DataSource(String dataUrl)
      : _bytes = base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1)),
        _contentType = dataUrl.substring(5, dataUrl.indexOf(';'));

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: _contentType,
    );
  }
}

final voiceModeProvider =
    StateNotifierProvider<VoiceModeController, VoiceModeStatus>(
  (ref) => VoiceModeController(ref),
);
