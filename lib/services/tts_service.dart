import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../api/lemonade_client.dart';
import '../api/types/audio_request.dart';

/// Convenience wrapper for TTS playback. Used by the manual "Read aloud" button
/// when OmniRouter mode is off, and for one-shot utterances elsewhere in the
/// app. (Inside the agent loop, TTS goes through the OmniRouter executor and
/// produces an Artifact instead.)
///
/// Synthesized audio is cached on disk keyed by (model, voice, format, text),
/// so identical utterances — common in voice mode ("Sure.", "Done!") — are
/// never re-synthesized. The cache directory is age-pruned on first use.
class TtsService {
  final LemonadeApiClient client;
  final String model;
  final AudioPlayer _player = AudioPlayer();

  TtsService({required this.client, required this.model});

  static const String _cacheDirName = 'tts_cache';
  static const Duration _cacheMaxAge = Duration(days: 7);
  static bool _cleanupStarted = false;

  /// Synthesize and play [text]. Returns the on-disk path of the cached audio
  /// file (caller can persist it or attach it to a message).
  Future<String> speak(String text, {String voice = 'af_heart'}) async {
    final result = await synthesize(
      client: client,
      model: model,
      text: text,
      voice: voice,
    );
    await _player.setFilePath(result.path);
    await _player.play();
    return result.path;
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() async {
    await _player.dispose();
  }

  /// Synthesize [text] with an on-disk cache. Shared by the duplex talk
  /// session and chat voice mode (which don't hold a [TtsService] instance),
  /// hence static. Returns the audio bytes, mime type, and cache-file path.
  static Future<({Uint8List bytes, String mime, String path})> synthesize({
    required LemonadeApiClient client,
    required String model,
    required String text,
    String voice = 'af_heart',
    String responseFormat = 'mp3',
  }) async {
    unawaited(_cleanupOnce());

    final key = sha256
        .convert(utf8.encode('$model\u0000$voice\u0000$responseFormat\u0000$text'))
        .toString();
    final dir = await _cacheDir();
    final path = p.join(dir.path, '$key.$responseFormat');
    final file = File(path);
    if (await file.exists()) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          return (
            bytes: bytes,
            mime: mimeForTtsFormat(responseFormat),
            path: path
          );
        }
      } catch (_) {
        // Unreadable cache entry — fall through and re-synthesize.
      }
    }

    final result = await client.audio.speech(TextToSpeechRequest(
      model: model,
      input: text,
      voice: voice,
      responseFormat: responseFormat,
    ));
    final bytes = Uint8List.fromList(result.audioBytes);
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      // Cache write failure is non-fatal — the synthesized audio still plays.
    }
    return (bytes: bytes, mime: result.mime, path: path);
  }

  static Future<Directory> _cacheDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, _cacheDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// One age-based sweep per process: prune cache entries older than
  /// [_cacheMaxAge], and delete the legacy un-cached `tts_<µs>.mp3` temp
  /// files earlier builds leaked into the temp dir root.
  static Future<void> _cleanupOnce() async {
    if (_cleanupStarted) return;
    _cleanupStarted = true;
    try {
      final cutoff = DateTime.now().subtract(_cacheMaxAge);
      final dir = await _cacheDir();
      await for (final entry in dir.list()) {
        if (entry is! File) continue;
        try {
          final stat = await entry.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entry.delete();
          }
        } catch (_) {}
      }

      final tmp = await getTemporaryDirectory();
      await for (final entry in tmp.list()) {
        if (entry is! File) continue;
        final name = p.basename(entry.path);
        if (name.startsWith('tts_') && name.endsWith('.mp3')) {
          try {
            await entry.delete();
          } catch (_) {}
        }
      }
    } catch (_) {
      // Cleanup is best-effort.
    }
  }

}
