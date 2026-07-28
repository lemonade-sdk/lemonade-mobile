import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lemonade_mobile/models/transcription.dart';
import 'package:lemonade_mobile/providers/models_provider.dart';
import 'package:lemonade_mobile/providers/model_defaults_provider.dart';
import 'package:lemonade_mobile/providers/servers_provider.dart';
import 'package:lemonade_mobile/api/lemonade_client.dart';
import 'package:lemonade_mobile/services/audio_transcription_service.dart';
import 'package:lemonade_mobile/services/audio_recorder_service.dart';
import 'package:lemonade_mobile/services/realtime_transcription_service.dart';
import 'package:lemonade_mobile/services/voice_record_config.dart';
import 'package:lemonade_mobile/storage/database.dart';
import 'package:lemonade_mobile/storage/entities/transcription_entity.dart';

// Recording state
enum RecordingState { idle, recording, processing }

final recordingStateProvider = StateProvider<RecordingState>((ref) => RecordingState.idle);

// Live transcription text (for realtime mode)
final liveTranscriptionTextProvider = StateProvider<String>((ref) => '');

// Transcription error
final transcriptionErrorProvider = StateProvider<String?>((ref) => null);

// Selected transcription mode
final transcriptionModeProvider = StateProvider<TranscriptionMode>((ref) => TranscriptionMode.http);

// Audio models derived from models list
final audioModelsProvider = Provider<List<ModelInfo>>((ref) {
  final models = ref.watch(modelsProvider);
  return models.where((m) => m.supportsAudio).toList();
});

// TTS models derived from models list
final ttsModelsProvider = Provider<List<ModelInfo>>((ref) {
  final models = ref.watch(modelsProvider);
  return models.where((m) => m.supportsTts).toList();
});

// --- Audio amplitude/recording providers ---

/// Collects amplitude samples during recording for waveform display.
final recordingAmplitudesProvider = StateProvider<List<double>>((ref) => []);

/// Info about the last completed recording (for post-record playback).
class RecordingInfo {
  final String filePath;
  final List<double> amplitudes;
  final Duration duration;

  RecordingInfo({
    required this.filePath,
    required this.amplitudes,
    required this.duration,
  });
}

final lastRecordingInfoProvider = StateProvider<RecordingInfo?>((ref) => null);

// Transcription history
final transcriptionHistoryProvider =
    StateNotifierProvider<TranscriptionHistoryNotifier, List<Transcription>>(
  (ref) => TranscriptionHistoryNotifier(),
);

class TranscriptionHistoryNotifier extends StateNotifier<List<Transcription>> {
  final _uuid = const Uuid();

  TranscriptionHistoryNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    if (!AppDatabase.isOpen) return;
    final rows = await AppDatabase.instance.transcriptions
        .where()
        .sortByCreatedAtDesc()
        .findAll();
    state = rows.map(_entityToModel).toList(growable: false);
  }

  Transcription _entityToModel(TranscriptionEntity e) => Transcription(
        id: e.uuid,
        text: e.text,
        modelId: e.modelId,
        mode: e.mode == 'realtime'
            ? TranscriptionMode.realtime
            : TranscriptionMode.http,
        serverName: e.serverName,
        audioFilePath: e.audioFilePath,
        audioDuration: e.audioDurationMs == null
            ? null
            : Duration(milliseconds: e.audioDurationMs!),
        createdAt: e.createdAt,
      );

  Future<Transcription> addTranscription({
    required String text,
    String? modelId,
    required TranscriptionMode mode,
    String? serverName,
    String? audioFilePath,
    Duration? audioDuration,
  }) async {
    final transcription = Transcription(
      id: _uuid.v4(),
      text: text,
      modelId: modelId,
      mode: mode,
      serverName: serverName,
      audioFilePath: audioFilePath,
      audioDuration: audioDuration,
    );
    if (AppDatabase.isOpen) {
      final db = AppDatabase.instance;
      final entity = TranscriptionEntity()
        ..uuid = transcription.id
        ..text = transcription.text
        ..modelId = transcription.modelId
        ..mode = mode == TranscriptionMode.realtime ? 'realtime' : 'http'
        ..serverName = transcription.serverName
        ..audioFilePath = transcription.audioFilePath
        ..audioDurationMs = transcription.audioDuration?.inMilliseconds
        ..createdAt = transcription.createdAt;
      await db.isar.writeTxn(() async => db.transcriptions.put(entity));
    }
    state = [transcription, ...state];
    return transcription;
  }

  Future<void> updateTranscription(String id, String text) async {
    state = state.map((t) {
      if (t.id == id) return t.copyWith(text: text);
      return t;
    }).toList();
    if (!AppDatabase.isOpen) return;
    final db = AppDatabase.instance;
    final existing =
        await db.transcriptions.filter().uuidEqualTo(id).findFirst();
    if (existing == null) return;
    existing.text = text;
    await db.isar.writeTxn(() async => db.transcriptions.put(existing));
  }

  Future<void> deleteTranscription(String id) async {
    final transcription = state.firstWhere(
      (t) => t.id == id,
      orElse: () => throw StateError('Not found'),
    );
    if (transcription.audioFilePath != null) {
      try {
        // Stored paths are absolute and go stale when iOS relocates the app
        // container on update — resolve (re-root) before deleting so we hit
        // the real file instead of leaking it.
        final resolved = await AudioRecorderService.resolveAudioPath(
            transcription.audioFilePath!);
        if (resolved != null) await File(resolved).delete();
      } catch (_) {}
    }
    state = state.where((t) => t.id != id).toList();
    if (!AppDatabase.isOpen) return;
    final db = AppDatabase.instance;
    await db.isar.writeTxn(() async {
      await db.transcriptions.filter().uuidEqualTo(id).deleteAll();
    });
  }

  Future<void> clearAll() async {
    for (final t in state) {
      if (t.audioFilePath != null) {
        try {
          final resolved =
              await AudioRecorderService.resolveAudioPath(t.audioFilePath!);
          if (resolved != null) await File(resolved).delete();
        } catch (_) {}
      }
    }
    state = [];
    if (!AppDatabase.isOpen) return;
    final db = AppDatabase.instance;
    await db.isar.writeTxn(() async => db.transcriptions.where().deleteAll());
  }
}

// Main transcription controller provider
final transcriptionControllerProvider = Provider<TranscriptionController>((ref) {
  final controller = TranscriptionController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

class TranscriptionController {
  final Ref ref;
  AudioRecorderService? _recorder;
  StreamSubscription? _amplitudeSub;
  String? _currentRecordingPath;
  bool _isTransitioning = false;

  /// Stop/cancel requested while a start/stop transition was still running
  /// (realtime connect can take ~12s). Instead of silently ignoring the tap,
  /// remember it and honor it as soon as the transition completes.
  _PendingAction _pendingAction = _PendingAction.none;
  DateTime? _streamStartTime;

  // Live stream state (PCM16 mic → WebSocket)
  AudioRecorder? _streamRecorder;
  StreamSubscription<Uint8List>? _pcmStreamSub;
  RealtimeTranscriptionService? _realtimeService;
  StreamSubscription<String>? _transcriptSub;
  StreamSubscription<String>? _wsErrorSub;
  List<List<int>> _fullSessionChunks = [];
  bool _liveSessionActive = false;

  TranscriptionController(this.ref);

  AudioRecorderService get recorder {
    _recorder ??= AudioRecorderService();
    return _recorder!;
  }

  Future<bool> checkPermission() async {
    return await recorder.hasPermission();
  }

  /// Start amplitude sampling using amplitudeStream (for HTTP mode).
  void _startAmplitudeSampling() {
    ref.read(recordingAmplitudesProvider.notifier).state = [];
    _amplitudeSub = recorder.amplitudeStream().listen((amplitude) {
      final current = ref.read(recordingAmplitudesProvider);
      ref.read(recordingAmplitudesProvider.notifier).state = [...current, amplitude];
    });
  }

  void _stopAmplitudeSampling() {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
  }

  // ── HTTP Record Mode ──────────────────────────────────────────

  /// Start recording for HTTP transcription mode (WAV for server compatibility).
  Future<void> startHttpRecording() async {
    ref.read(transcriptionErrorProvider.notifier).state = null;
    ref.read(recordingStateProvider.notifier).state = RecordingState.recording;
    ref.read(lastRecordingInfoProvider.notifier).state = null;

    try {
      _currentRecordingPath = await recorder.startFileRecording(compressed: false);
      _startAmplitudeSampling();
    } catch (e) {
      ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
      ref.read(transcriptionErrorProvider.notifier).state = 'Failed to start recording: $e';
    }
  }

  /// Stop HTTP recording and send for transcription.
  Future<void> stopHttpRecordingAndTranscribe() async {
    _stopAmplitudeSampling();
    ref.read(recordingStateProvider.notifier).state = RecordingState.processing;

    try {
      final path = await recorder.stopFileRecording();
      if (path == null) {
        ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
        ref.read(transcriptionErrorProvider.notifier).state = 'No recording found';
        return;
      }

      final server = ref.read(selectedServerProvider);
      if (server == null) {
        ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
        ref.read(transcriptionErrorProvider.notifier).state = 'No server selected';
        return;
      }

      // Persist the recording before transcribing
      final persistedPath = await recorder.persistRecording(path);

      // Detect duration via just_audio
      Duration audioDuration = Duration.zero;
      try {
        final player = AudioPlayer();
        final dur = await player.setFilePath(persistedPath);
        audioDuration = dur ?? Duration.zero;
        await player.dispose();
      } catch (_) {}

      // Capture amplitudes before transcription
      final amplitudes = List<double>.from(ref.read(recordingAmplitudesProvider));
      final model = ref.read(effectiveAudioModelProvider);

      // Attempt transcription - save recording even if API call fails
      String text = '';
      try {
        final client = LemonadeApiClient(server);
        try {
          final service = AudioTranscriptionService(client);
          text = await service.transcribeFile(persistedPath, model: model);
        } finally {
          client.close();
        }
      } catch (e) {
        ref.read(transcriptionErrorProvider.notifier).state = 'Transcription failed: $e';
      }

      await ref.read(transcriptionHistoryProvider.notifier).addTranscription(
        text: text,
        modelId: model,
        mode: TranscriptionMode.http,
        serverName: server.name,
        audioFilePath: persistedPath,
        audioDuration: audioDuration,
      );

      // Set last recording info for immediate playback
      ref.read(lastRecordingInfoProvider.notifier).state = RecordingInfo(
        filePath: persistedPath,
        amplitudes: amplitudes,
        duration: audioDuration,
      );

      _currentRecordingPath = null;
    } catch (e) {
      ref.read(transcriptionErrorProvider.notifier).state = 'Recording failed: $e';
    } finally {
      ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
    }
  }

  // ── Live Stream Mode (PCM16 mic stream → WebSocket transcription) ──

  /// Start live stream: open WebSocket, start PCM16 mic stream, pipe audio.
  /// Transcription text arrives via WebSocket in real-time.
  /// Full session PCM16 is accumulated for saving as WAV on stop.
  Future<void> startRealtimeStream() async {
    if (_isTransitioning) return;
    _isTransitioning = true;
    _pendingAction = _PendingAction.none;

    ref.read(transcriptionErrorProvider.notifier).state = null;
    ref.read(liveTranscriptionTextProvider.notifier).state = '';
    ref.read(lastRecordingInfoProvider.notifier).state = null;
    ref.read(recordingAmplitudesProvider.notifier).state = [];
    _fullSessionChunks = [];

    final server = ref.read(selectedServerProvider);
    if (server == null) {
      ref.read(transcriptionErrorProvider.notifier).state = 'No server selected';
      await _finishTransition();
      return;
    }

    ref.read(recordingStateProvider.notifier).state = RecordingState.processing;

    final model = ref.read(effectiveAudioModelProvider);

    // 1. Discover WebSocket port and connect
    try {
      final client = LemonadeApiClient(server);
      try {
        final transcriptionService = AudioTranscriptionService(client);
        final wsPort = await transcriptionService.discoverWebSocketPort();
        _realtimeService = RealtimeTranscriptionService(server);
        await _realtimeService!.connect(model: model, port: wsPort);
      } finally {
        client.close();
      }
    } catch (e) {
      ref.read(transcriptionErrorProvider.notifier).state =
          'WebSocket connection failed: $e';
      ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
      // The cached port (if any) just failed us — re-probe next time.
      AudioTranscriptionService.invalidateWebSocketPortCache(server);
      _realtimeService?.dispose();
      _realtimeService = null;
      await _finishTransition();
      return;
    }

    // Listen for transcription text from WebSocket
    _transcriptSub = _realtimeService!.transcriptStream.listen((text) {
      ref.read(liveTranscriptionTextProvider.notifier).state = text;
    });

    _wsErrorSub = _realtimeService!.errorStream.listen((error) {
      ref.read(transcriptionErrorProvider.notifier).state = error;
    });

    // 2. Start PCM16 mic stream
    try {
      _streamRecorder = AudioRecorder();
      final stream = await _streamRecorder!.startStream(kVoicePcm16Config);

      _pcmStreamSub = stream.listen((Uint8List chunk) {
        if (!_liveSessionActive) return;

        // Accumulate for full session WAV on stop
        _fullSessionChunks.add(chunk);

        // Send PCM16 to WebSocket as base64
        _realtimeService?.sendAudioChunk(base64Encode(chunk));

        // Compute amplitude for visualization
        final amplitude =
            AudioRecorderService.normalizedAmplitudeFromPcm16(chunk);
        final current = ref.read(recordingAmplitudesProvider);
        ref.read(recordingAmplitudesProvider.notifier).state = [...current, amplitude];
      });
    } catch (e) {
      ref.read(transcriptionErrorProvider.notifier).state =
          'Failed to start mic stream: $e';
      ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
      await _realtimeService?.disconnect();
      _realtimeService?.dispose();
      _realtimeService = null;
      await _finishTransition();
      return;
    }

    _streamStartTime = DateTime.now();
    _liveSessionActive = true;
    ref.read(recordingStateProvider.notifier).state = RecordingState.recording;
    await _finishTransition();
  }

  /// Stop live stream: stop mic, commit & disconnect WebSocket, save audio + history.
  Future<void> stopRealtimeStream() async {
    if (_isTransitioning) {
      // A start/stop transition is still in flight — honor the stop once it
      // completes instead of silently dropping the tap.
      _pendingAction = _PendingAction.stop;
      return;
    }
    _isTransitioning = true;

    try {
      await _stopRealtimeStreamBody();
    } finally {
      // Even on an unexpected failure the transition must end (a stuck
      // `_isTransitioning` bricks start/stop/cancel for good) and any
      // deferred stop/cancel must run.
      await _finishTransition();
    }
  }

  Future<void> _stopRealtimeStreamBody() async {
    // Nothing live: the session already stopped/cancelled or never started
    // (failed start). A deferred or duplicate stop must not re-save the
    // session (duplicate history entry) — every such path has already put
    // recordingState back to idle.
    if (!_liveSessionActive) return;
    _liveSessionActive = false;
    ref.read(recordingStateProvider.notifier).state = RecordingState.processing;

    // Stop mic stream
    await _pcmStreamSub?.cancel();
    _pcmStreamSub = null;
    try {
      await _streamRecorder?.stop();
    } catch (_) {}
    _streamRecorder?.dispose();
    _streamRecorder = null;

    // Commit final audio buffer and wait for server's final transcript
    if (_realtimeService != null) {
      await _realtimeService!.commitAndWaitForFinal(
        timeout: const Duration(seconds: 30),
      );
    }
    _transcriptSub?.cancel();
    _transcriptSub = null;
    _wsErrorSub?.cancel();
    _wsErrorSub = null;
    await _realtimeService?.disconnect();
    _realtimeService?.dispose();
    _realtimeService = null;

    // Calculate total duration
    final totalDuration = _streamStartTime != null
        ? DateTime.now().difference(_streamStartTime!)
        : Duration.zero;

    // Capture amplitudes
    final amplitudes = List<double>.from(ref.read(recordingAmplitudesProvider));

    // Save full session audio as WAV
    String? audioPath;
    if (_fullSessionChunks.isNotEmpty) {
      try {
        audioPath = await recorder.saveStreamAsWav(_fullSessionChunks);
      } catch (_) {}
    }

    // Save transcription to history
    final text = ref.read(liveTranscriptionTextProvider);
    final server = ref.read(selectedServerProvider);
    final model = ref.read(effectiveAudioModelProvider);

    if (text.isNotEmpty || audioPath != null) {
      await ref.read(transcriptionHistoryProvider.notifier).addTranscription(
        text: text,
        modelId: model,
        mode: TranscriptionMode.realtime,
        serverName: server?.name,
        audioFilePath: audioPath,
        audioDuration: totalDuration,
      );
    }

    // Set last recording info for playback
    if (audioPath != null) {
      ref.read(lastRecordingInfoProvider.notifier).state = RecordingInfo(
        filePath: audioPath,
        amplitudes: amplitudes,
        duration: totalDuration,
      );
    }

    // Reset
    _fullSessionChunks = [];
    _streamStartTime = null;
    ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
  }

  // ── Common ────────────────────────────────────────────────────

  /// Cancel any active recording without saving.
  Future<void> cancelRecording() async {
    if (_isTransitioning) {
      // Can't interleave with an in-flight start/stop (null-derefs, phantom
      // "recording" state) — defer until the transition completes.
      _pendingAction = _PendingAction.cancel;
      return;
    }
    _isTransitioning = true;
    try {
      await _cancelRecordingBody();
    } finally {
      await _finishTransition();
    }
  }

  Future<void> _cancelRecordingBody() async {
    _liveSessionActive = false;
    _stopAmplitudeSampling();

    // Stop HTTP recorder if active
    await recorder.stopRecording();
    if (_currentRecordingPath != null) {
      await recorder.deleteFile(_currentRecordingPath!);
      _currentRecordingPath = null;
    }

    // Stop stream recorder if active
    await _pcmStreamSub?.cancel();
    _pcmStreamSub = null;
    try { await _streamRecorder?.stop(); } catch (_) {}
    _streamRecorder?.dispose();
    _streamRecorder = null;

    // Disconnect WebSocket if active
    _transcriptSub?.cancel();
    _transcriptSub = null;
    _wsErrorSub?.cancel();
    _wsErrorSub = null;
    await _realtimeService?.disconnect();
    _realtimeService?.dispose();
    _realtimeService = null;

    _fullSessionChunks = [];
    _streamStartTime = null;

    ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
    ref.read(liveTranscriptionTextProvider.notifier).state = '';
  }

  /// End the current transition and run any stop/cancel that was requested
  /// while it was in flight.
  Future<void> _finishTransition() async {
    _isTransitioning = false;
    final pending = _pendingAction;
    _pendingAction = _PendingAction.none;
    switch (pending) {
      case _PendingAction.stop:
        await stopRealtimeStream();
      case _PendingAction.cancel:
        await cancelRecording();
      case _PendingAction.none:
        break;
    }
  }

  void dispose() {
    _recorder?.dispose();
    _streamRecorder?.dispose();
    _realtimeService?.dispose();
    _pcmStreamSub?.cancel();
    _transcriptSub?.cancel();
    _wsErrorSub?.cancel();
    _amplitudeSub?.cancel();
  }
}

/// Deferred user intent captured while a start/stop transition is running.
enum _PendingAction { none, stop, cancel }
