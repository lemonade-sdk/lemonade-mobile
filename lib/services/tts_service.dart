import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../api/lemonade_client.dart';
import '../api/types/audio_request.dart';

/// Convenience wrapper for TTS playback. Used by the manual "Read aloud" button
/// when OmniRouter mode is off, and for one-shot utterances elsewhere in the
/// app. (Inside the agent loop, TTS goes through the OmniRouter executor and
/// produces an Artifact instead.)
class TtsService {
  final LemonadeApiClient client;
  final String model;
  final AudioPlayer _player = AudioPlayer();

  TtsService({required this.client, required this.model});

  /// Synthesize and play [text]. Returns the on-disk path of the cached audio
  /// file (caller can persist it or attach it to a message).
  Future<String> speak(String text, {String voice = 'af_heart'}) async {
    final result = await client.audio.speech(TextToSpeechRequest(
      model: model,
      input: text,
      voice: voice,
      responseFormat: 'mp3',
    ));

    final path = await _writeToCache(result.audioBytes, ext: '.mp3');
    await _player.setFilePath(path);
    await _player.play();
    return path;
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() async {
    await _player.dispose();
  }

  Future<String> _writeToCache(Uint8List bytes, {required String ext}) async {
    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'tts_${DateTime.now().microsecondsSinceEpoch}$ext',
    );
    final f = File(path);
    await f.writeAsBytes(bytes, flush: true);
    return path;
  }
}
