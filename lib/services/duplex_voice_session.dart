import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import '../api/lemonade_client.dart';
import '../api/realtime/realtime_audio_socket.dart';
import '../api/types/audio_request.dart';
import '../api/types/chat_message.dart';
import '../api/types/chat_request.dart';
import '../models/chat_message.dart' as ui;
import '../omni/agent_loop.dart';
import '../omni/capability_resolver.dart';
import '../omni/tool_executor.dart';
import 'audio_transcription_service.dart';

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
  StreamSubscription<Uint8List>? _pcmSub;

  final _state = StreamController<DuplexState>.broadcast();
  final _events = StreamController<DuplexEvent>.broadcast();

  bool _running = false;
  bool _disposed = false;
  String _liveTranscript = '';

  DuplexVoiceSession({
    required this.client,
    required this.llmModel,
    required this.asrModel,
    required this.ttsModel,
    required this.history,
    this.capabilities,
    this.executor,
  }) : _ws = RealtimeAudioSocket(client);

  bool get _toolCallingEnabled =>
      capabilities != null &&
      capabilities!.isUsable &&
      executor != null;

  Stream<DuplexState> get state => _state.stream;
  Stream<DuplexEvent> get events => _events.stream;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _emitState(DuplexState.connecting);
    final svc = AudioTranscriptionService(client.server);
    final wsPort = await svc.discoverWebSocketPort();
    await _ws.connect(model: asrModel, port: wsPort);
    _eventsSub = _ws.events.listen(_handleAsrEvent);
    await _beginListening();
  }

  Future<void> stop() async {
    _running = false;
    await _stopListening();
    await _player.stop();
    await _ws.close();
    _emitState(DuplexState.idle);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventsSub?.cancel();
    await _pcmSub?.cancel();
    await _player.dispose();
    await _ws.dispose();
    await _state.close();
    await _events.close();
  }

  // ---------------------------------------------------------------------------
  // Listening loop
  // ---------------------------------------------------------------------------

  Future<void> _beginListening() async {
    if (!_running) return;
    _liveTranscript = '';
    _emitEvent(DuplexEvent.transcriptUpdate(''));
    _emitState(DuplexState.listening);

    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    ));
    _pcmSub = stream.listen((chunk) {
      _ws.appendAudio(base64Encode(chunk));
    });
  }

  Future<void> _stopListening() async {
    await _pcmSub?.cancel();
    _pcmSub = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  // ---------------------------------------------------------------------------
  // ASR events
  // ---------------------------------------------------------------------------

  Future<void> _handleAsrEvent(RealtimeEvent ev) async {
    switch (ev) {
      case RealtimeDelta():
        _liveTranscript = '$_liveTranscript${ev.text}';
        _emitEvent(DuplexEvent.transcriptUpdate(_liveTranscript));
      case RealtimeCompleted():
        final finalText = ev.transcript.isNotEmpty ? ev.transcript : _liveTranscript;
        if (finalText.trim().isEmpty) return;
        await _stopListening();
        _emitEvent(DuplexEvent.userSpoke(finalText));
        await _runTurn(finalText);
      case RealtimeError():
        _emitEvent(DuplexEvent.error(ev.message));
      case RealtimeInfo():
        // ignore informational events
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
      _emitEvent(DuplexEvent.error('LLM error: $e'));
      await _beginListening();
      return;
    }

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
    for (final art in ttsArtifacts) {
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
    if (reply.isNotEmpty) _emitEvent(DuplexEvent.assistantSpoke(reply));

    // Speak: prefer audio the agent already synthesized via text_to_speech;
    // otherwise fall back to a fresh TTS pass on the assistant text.
    _emitState(DuplexState.speaking);
    try {
      if (ttsArtifacts.isNotEmpty) {
        final art = ttsArtifacts.last;
        await _playDataUrl('data:${art.mime};base64,${art.base64Data}');
      } else if (ttsModel != null && reply.isNotEmpty) {
        final tts = await client.audio.speech(TextToSpeechRequest(
          model: ttsModel!,
          input: reply,
          responseFormat: 'mp3',
        ));
        await _playDataUrl(
          'data:${tts.mime};base64,${base64Encode(tts.audioBytes)}',
        );
      }
    } catch (e) {
      _emitEvent(DuplexEvent.error('TTS error: $e'));
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
        case AgentStatus():
          // Surface intermediate status (e.g., "Generating image…") so the
          // UI doesn't sit on the listening pulse during long tool runs.
          _emitEvent(DuplexEvent.transcriptUpdate(ev.message));
        case AgentArtifact():
          artifacts.add(ev.artifact);
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

  Future<void> _playDataUrl(String dataUrl) async {
    await _player.setAudioSource(_DataSource(dataUrl));
    await _player.play();
    await _player.processingStateStream
        .firstWhere((s) => s == ProcessingState.completed);
  }

  void _emitState(DuplexState s) => _state.add(s);
  void _emitEvent(DuplexEvent ev) => _events.add(ev);
}

enum DuplexState { idle, connecting, listening, thinking, speaking }

sealed class DuplexEvent {
  const DuplexEvent();

  factory DuplexEvent.transcriptUpdate(String text) = DuplexTranscriptUpdate;
  factory DuplexEvent.userSpoke(String text) = DuplexUserSpoke;
  factory DuplexEvent.assistantSpoke(String text) = DuplexAssistantSpoke;
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
  const DuplexUserSpoke(this.text);
}

class DuplexAssistantSpoke extends DuplexEvent {
  final String text;
  const DuplexAssistantSpoke(this.text);
}

class DuplexErrorEvent extends DuplexEvent {
  final String message;
  const DuplexErrorEvent(this.message);
}

/// just_audio source from a data URL.
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
