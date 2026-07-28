import 'package:record/record.dart';

/// Shared PCM16 / 16 kHz / mono mic config for realtime voice paths
/// (Talk/duplex, live transcription, call takeover).
///
/// Uses Android `voiceCommunication` so hardware AEC + noise suppression
/// engage. Call-takeover previously omitted this and sent echo-prone uplink.
const RecordConfig kVoicePcm16Config = RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: 16000,
  numChannels: 1,
  androidConfig: AndroidRecordConfig(
    audioSource: AndroidAudioSource.voiceCommunication,
  ),
);
