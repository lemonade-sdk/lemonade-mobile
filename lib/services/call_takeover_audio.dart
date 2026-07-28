import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import '../api/nexus/nexus_call_takeover_socket.dart';
import 'audio_recorder_service.dart';
import 'data_url_audio_source.dart';
import 'voice_record_config.dart';

/// Drives the human-voice takeover: streams the operator's mic (PCM16 16 kHz)
/// up the takeover socket and plays the caller's inbound audio.
///
/// Uplink is real-time; downlink is buffered into short WAV bursts (~400 ms)
/// and played back to back — robust without a fragile live audio source. Tune
/// [_flushEvery] if the caller audio sounds choppy on-device.
class CallTakeoverAudio {
  final NexusCallTakeoverSocket socket;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<Uint8List>? _inSub;
  Timer? _flush;
  final List<int> _inboundBuf = [];
  bool _stopped = false;

  static const _flushEvery = Duration(milliseconds: 400);

  // Keep at most ~2s of caller PCM (16 kHz × 2 bytes/sample). If playback
  // falls behind, drop the oldest audio so a long takeover stays near-realtime
  // instead of accumulating an ever-growing delay.
  static const _maxInboundBytes = 2 * 16000 * 2;

  CallTakeoverAudio(this.socket);

  Future<void> start() async {
    // Fail fast if the takeover socket can't connect — a "live" takeover with
    // no uplink is dead air for the caller, so this must propagate before the
    // UI claims the operator is on the line.
    await socket.connect();

    // Downlink: accumulate caller PCM, flush to playback on a cadence.
    _inSub = socket.inbound.listen((pcm) {
      _inboundBuf.addAll(pcm);
      final overflow = _inboundBuf.length - _maxInboundBytes;
      if (overflow > 0) _inboundBuf.removeRange(0, overflow);
    });
    _flush = Timer.periodic(_flushEvery, (_) => _flushPlayback());

    // Uplink: stream mic PCM16 @16k as it's captured. If the mic can't start,
    // fail loudly — a "live" takeover that sends nothing is dead air for the
    // caller, so the UI must revert instead of pretending it worked.
    try {
      if (!await _recorder.hasPermission()) {
        throw StateError('Microphone permission denied.');
      }
      final stream = await _recorder.startStream(kVoicePcm16Config);
      _micSub = stream.listen((pcm) {
        if (!_muted) socket.sendPcm(pcm);
      });
    } catch (e) {
      debugPrint('[Takeover] mic start failed: $e');
      rethrow;
    }
  }

  bool _muted = false;
  void setMuted(bool muted) {
    _muted = muted;
    // When muted, stop forwarding mic chunks (re-subscribe logic kept simple:
    // the listener checks the flag).
  }

  Future<void> _flushPlayback() async {
    if (_stopped || _inboundBuf.isEmpty) return;
    if (_player.playing) return; // still draining the previous burst
    final pcm = Uint8List.fromList(_inboundBuf);
    _inboundBuf.clear();
    try {
      final wav = AudioRecorderService.buildWavBytes([pcm], sampleRate: 16000);
      final dataUrl = 'data:audio/wav;base64,${base64Encode(wav)}';
      await _player.setAudioSource(DataUrlAudioSource(dataUrl));
      await _player.play();
    } catch (e) {
      debugPrint('[Takeover] playback failed: $e');
    }
  }

  /// Hand the line back to the AI but keep the socket open.
  void release() => socket.release();

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _flush?.cancel();
    await _micSub?.cancel();
    await _inSub?.cancel();
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
    await _recorder.dispose();
    await _player.dispose();
    socket.close();
  }
}
