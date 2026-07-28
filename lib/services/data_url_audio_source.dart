import 'dart:convert';

import 'package:just_audio/just_audio.dart';

/// [StreamAudioSource] backed by a `data:<mime>;base64,…` URL.
///
/// Used by duplex voice, call takeover, and (historically) voice-mode — one
/// implementation so playback quirks are fixed in a single place.
class DataUrlAudioSource extends StreamAudioSource {
  final List<int> _bytes;
  final String _contentType;

  DataUrlAudioSource(String dataUrl)
      : _bytes = base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1)),
        _contentType = dataUrl.substring(5, dataUrl.indexOf(';'));

  /// From raw bytes + MIME (when the caller already has decoded PCM/WAV).
  DataUrlAudioSource.fromBytes(List<int> bytes, String contentType)
      : _bytes = bytes,
        _contentType = contentType;

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
