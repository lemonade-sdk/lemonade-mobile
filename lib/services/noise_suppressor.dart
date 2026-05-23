import 'dart:typed_data';

/// Process PCM16 audio chunks to suppress background noise before sending
/// them to ASR. This is the *third* layer of the voice-quality stack:
///
///   1. **OS voice processing** (iOS AVAudioSession voiceChat mode, Android
///      `AudioSource.VOICE_COMMUNICATION`) — handles AEC + steady-state
///      noise. Configured in `voice_mode_provider`. Always on.
///   2. **Silero VAD** (via the `vad` package) — decides when the user
///      stopped talking. Robust to background noise that the OS layer
///      can't filter (other voices, music, transient sounds). Also always
///      on once the dep is wired up.
///   3. **ML denoising** (this file) — runs a learned model over the PCM
///      to scrub residual noise. Only worthwhile in genuinely noisy
///      environments (cafes, cars, wind). Off by default.
///
/// Currently a no-op stub. Wire-up sketch when you're ready:
///   - Pick a model: **RNNoise** (~700 KB, classic, C library), **DeepFilterNet
///     v3** (~7 MB, better quality, ONNX), or a small ONNX speech-enhancement
///     model. RNNoise needs FFI bindings; the ONNX options can run via the
///     `onnxruntime` package (already pulled in transitively by `vad`).
///   - Bundle the model file under `assets/` and load it in [warmUp].
///   - Implement [process] to run the model over each chunk. Match the
///     model's expected frame size (RNNoise is 10 ms / 480 samples at
///     48 kHz; DFN is 30 ms frames at 48 kHz — both require resampling
///     from our 16 kHz capture).
///   - Add a user-visible toggle in Settings so they can A/B it.
abstract class NoiseSuppressor {
  /// Singleton-style entry point. Returns [NoOpNoiseSuppressor] today.
  /// When a real implementation lands, swap this factory to return it.
  static NoiseSuppressor get instance => _instance;
  static NoiseSuppressor _instance = const NoOpNoiseSuppressor();

  /// Replace the active implementation (used by tests + future user
  /// toggles between off / RNNoise / DeepFilterNet).
  static void setImplementation(NoiseSuppressor impl) {
    _instance = impl;
  }

  /// Whether suppression is actually doing anything. UI checks this to
  /// decide whether to show the "denoise: on" badge.
  bool get isActive;

  /// One-time async setup — load model weights, allocate buffers. Called
  /// once when voice mode starts. Safe to call repeatedly.
  Future<void> warmUp();

  /// Process one PCM16 chunk and return the denoised chunk. Output length
  /// MUST equal input length so downstream code doesn't care whether
  /// suppression is on. Implementations that need different framing
  /// should buffer internally and use overlap-add.
  Uint8List process(Uint8List pcm16Chunk);

  /// Tear down model state. Called from voice mode teardown.
  Future<void> dispose();
}

/// Default no-op. Lets all call sites use [NoiseSuppressor.instance.process]
/// unconditionally without branching on whether ML denoising is enabled.
class NoOpNoiseSuppressor implements NoiseSuppressor {
  const NoOpNoiseSuppressor();

  @override
  bool get isActive => false;

  @override
  Future<void> warmUp() async {}

  @override
  Uint8List process(Uint8List pcm16Chunk) => pcm16Chunk;

  @override
  Future<void> dispose() async {}
}
