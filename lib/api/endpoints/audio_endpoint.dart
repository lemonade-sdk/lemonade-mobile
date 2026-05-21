import '../lemonade_client.dart';
import '../types/audio_request.dart';
import '../types/audio_response.dart';

class AudioEndpoint {
  final LemonadeApiClient _client;
  AudioEndpoint(this._client);

  /// `POST /v1/audio/speech` — TTS. Returns raw audio bytes.
  Future<TtsResult> speech(
    TextToSpeechRequest request, {
    Duration? timeout,
  }) async {
    final bytes = await _client.postJsonForBytes(
      _client.apiUriFor('/audio/speech'),
      request.toWireJson(),
      timeout: timeout ?? const Duration(minutes: 2),
    );
    return TtsResult(audioBytes: bytes, mime: _mimeFor(request.responseFormat));
  }

  /// `POST /v1/audio/transcriptions` — ASR via multipart upload.
  Future<TranscriptionResult> transcribe(
    TranscriptionRequest request, {
    Duration? timeout,
  }) async {
    final fields = <String, String>{
      'model': request.model,
      'response_format': request.responseFormat,
    };
    if (request.language != null) fields['language'] = request.language!;

    final body = await _client.postMultipart(
      _client.apiUriFor('/audio/transcriptions'),
      fields: fields,
      files: [
        MultipartFile(
          field: 'file',
          filename: request.audioFilename,
          bytes: request.audioBytes,
          mimeType: request.audioMime,
        ),
      ],
      timeout: timeout ?? const Duration(minutes: 5),
    );
    return TranscriptionResult.fromJson(body);
  }

  String _mimeFor(String responseFormat) {
    switch (responseFormat) {
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'opus':
        return 'audio/opus';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'pcm':
        return 'audio/pcm';
      default:
        return 'application/octet-stream';
    }
  }
}
