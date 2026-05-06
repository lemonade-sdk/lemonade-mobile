/// Body for `POST /v1/audio/speech` (TTS).
class TextToSpeechRequest {
  final String model;
  final String input;
  final String voice;
  final String responseFormat; // 'mp3' | 'wav' | 'opus' | 'aac' | 'flac' | 'pcm'
  final double? speed;

  TextToSpeechRequest({
    required this.model,
    required this.input,
    this.voice = 'af_heart',
    this.responseFormat = 'mp3',
    this.speed,
  });

  Map<String, dynamic> toWireJson() {
    final body = <String, dynamic>{
      'model': model,
      'input': input,
      'voice': voice,
      'response_format': responseFormat,
    };
    if (speed != null) body['speed'] = speed;
    return body;
  }
}

/// Body for `POST /v1/audio/transcriptions` (multipart/form-data).
class TranscriptionRequest {
  final String model;
  final List<int> audioBytes;
  final String audioFilename;
  final String audioMime;
  final String? language; // ISO 639-1 like 'en'
  final String responseFormat; // 'json' | 'text' | 'verbose_json' | 'srt' | 'vtt'

  TranscriptionRequest({
    required this.model,
    required this.audioBytes,
    required this.audioFilename,
    this.audioMime = 'audio/wav',
    this.language,
    this.responseFormat = 'json',
  });
}
