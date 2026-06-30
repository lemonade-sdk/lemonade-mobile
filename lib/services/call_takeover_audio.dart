import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import '../api/nexus/nexus_call_takeover_socket.dart';
import 'audio_recorder_service.dart';

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

  CallTakeoverAudio(this.socket);

  Future<void> start() async {
    socket.connect();

    // Downlink: accumulate caller PCM, flush to playback on a cadence.
    _inSub = socket.inbound.listen((pcm) => _inboundBuf.addAll(pcm));
    _flush = Timer.periodic(_flushEvery, (_) => _flushPlayback());

    // Uplink: stream mic PCM16 @16k as it's captured.
    try {
      if (await _recorder.hasPermission()) {
        final stream = await _recorder.startStream(const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ));
        _micSub = stream.listen((pcm) {
          if (!_muted) socket.sendPcm(pcm);
        });
      }
    } catch (e) {
      debugPrint('[Takeover] mic start failed: $e');
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
      await _player.setAudioSource(_BytesSource(dataUrl));
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

/// Minimal just_audio source from a `data:` URL (one playback burst).
class _BytesSource extends StreamAudioSource {
  final List<int> _bytes;
  final String _contentType;

  _BytesSource(String dataUrl)
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
