import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import '../api/realtime/realtime_audio_socket.dart';
import '../api/types/audio_request.dart';
import '../api/types/chat_message.dart' as api;
import '../api/types/chat_request.dart';
import '../models/chat_message.dart';
import '../omni/agent_loop.dart';
import '../omni/tool_executor.dart';
import '../services/audio_recorder_service.dart';
import '../services/audio_transcription_service.dart';
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

/// Amplitude (0..1) below which we consider the user "silent" for VAD.
/// Tuned for the dBFS-based normalization in [_amplitudeFromPcm16]: typical
/// quiet-room noise reads around 0.15-0.25, normal speech is 0.55-0.85.
const double _silenceThreshold = 0.30;

/// Minimum continuous below-threshold time before we even consider end-of-
/// utterance. Generous floor so a single beat between words ("um… so…")
/// doesn't trigger.
const Duration _minSilenceCutoff = Duration(milliseconds: 2200);

/// Maximum silence we'll allow before committing regardless of how much the
/// user has been speaking. Hard ceiling so the call doesn't hang forever if
/// they trail off mid-sentence.
const Duration _maxSilenceCutoff = Duration(milliseconds: 4500);

/// For longer utterances we grow the silence cutoff: every extra second of
/// speech buys an extra slice of allowed pause, up to [_maxSilenceCutoff].
/// Rationale: a one-word question can commit fast, but "yeah … so what I
/// was thinking about that … is …" gets the breathing room a person needs.
const double _silenceGrowthRatio = 0.4;

/// Minimum cumulative time above threshold before we'll consider committing.
/// Prevents committing on a stray cough during the initial connect.
const Duration _minSpeechDuration = Duration(milliseconds: 400);

Duration _adaptiveSilenceCutoff(Duration spokeFor) {
  // base + 40% of how long you've been speaking, clamped to [min, max].
  final extra = (spokeFor.inMilliseconds * _silenceGrowthRatio).round();
  final total = _minSilenceCutoff.inMilliseconds + extra;
  if (total <= _minSilenceCutoff.inMilliseconds) return _minSilenceCutoff;
  if (total >= _maxSilenceCutoff.inMilliseconds) return _maxSilenceCutoff;
  return Duration(milliseconds: total);
}

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

  /// VAD bookkeeping for the current utterance.
  DateTime? _firstVoiceAt;
  DateTime? _lastVoiceAt;
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
      _ws = RealtimeAudioSocket(client);
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
    _firstVoiceAt = null;
    _lastVoiceAt = null;
    _committing = false;
    state = state.copyWith(
      phase: VoicePhase.listening,
      message: null,
      amplitudes: const [],
    );

    final stream = await _recorder!.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    ));
    _pcmSub = stream.listen(_handlePcmChunk, onError: (e) {
      _log('mic stream error: $e');
      _fail('Mic stream error: $e');
    });
  }

  Future<void> _stopMic() async {
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

  void _handlePcmChunk(Uint8List chunk) {
    if (!_callActive) return;
    if (state.phase != VoicePhase.listening) return;
    _utterancePcm.add(chunk);
    // Only stream live to the WS when we actually have one. In HTTP fallback
    // mode we batch the whole utterance and POST it on commit.
    if (!_httpMode) {
      _ws?.appendAudio(base64Encode(chunk));
    }

    final amp = _amplitudeFromPcm16(chunk);
    final next = [...state.amplitudes, amp];
    if (next.length > _amplitudeWindow) {
      next.removeRange(0, next.length - _amplitudeWindow);
    }
    state = state.copyWith(amplitudes: next);

    final now = DateTime.now();
    if (amp >= _silenceThreshold) {
      _firstVoiceAt ??= now;
      _lastVoiceAt = now;
    } else if (_firstVoiceAt != null && _lastVoiceAt != null) {
      final silentFor = now.difference(_lastVoiceAt!);
      final spokeFor = _lastVoiceAt!.difference(_firstVoiceAt!);
      final cutoff = _adaptiveSilenceCutoff(spokeFor);
      if (silentFor >= cutoff && spokeFor >= _minSpeechDuration) {
        _log('VAD: end-of-utterance '
            '(spoke ${spokeFor.inMilliseconds}ms, '
            'silent ${silentFor.inMilliseconds}ms, '
            'cutoff ${cutoff.inMilliseconds}ms)');
        _commitUtterance();
      }
    }
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
