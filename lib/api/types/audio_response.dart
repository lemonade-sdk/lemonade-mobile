import 'dart:typed_data';

/// Result of `POST /v1/audio/speech` — raw audio bytes plus the MIME of the format
/// the server actually returned.
class TtsResult {
  final Uint8List audioBytes;
  final String mime;

  TtsResult({required this.audioBytes, required this.mime});
}

/// Result of `POST /v1/audio/transcriptions`.
class TranscriptionResult {
  final String text;

  TranscriptionResult({required this.text});

  factory TranscriptionResult.fromJson(Map<String, dynamic> json) =>
      TranscriptionResult(text: json['text'] as String? ?? '');
}
