import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  /// Check and request microphone permission.
  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  /// Start recording to a file.
  /// [compressed] true = AAC/m4a at 96kbps, false = WAV (for segments that need merging).
  Future<String> startFileRecording({bool compressed = true}) async {
    if (_isRecording) {
      throw StateError('Already recording');
    }

    final dir = await getTemporaryDirectory();
    final ext = compressed ? 'm4a' : 'wav';
    final path = '${dir.path}/transcription_${DateTime.now().millisecondsSinceEpoch}.$ext';

    final config = compressed
        ? const RecordConfig(
            encoder: AudioEncoder.aacLc,
            sampleRate: 16000,
            numChannels: 1,
            bitRate: 96000,
          )
        : const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
            bitRate: 256000,
          );

    await _recorder.start(config, path: path);
    _isRecording = true;
    return path;
  }

  /// Stop file recording and return the path.
  Future<String?> stopFileRecording() async {
    if (!_isRecording) return null;

    final path = await _recorder.stop();
    _isRecording = false;
    return path;
  }

  /// Get the current normalized amplitude (0.0 to 1.0).
  /// Works during any active recording (file or stream).
  Future<double> getNormalizedAmplitude() async {
    try {
      final amp = await _recorder.getAmplitude();
      final dB = amp.current;
      final clamped = dB.clamp(-60.0, 0.0);
      return (clamped + 60.0) / 60.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// Stream of normalized amplitude values (0.0 to 1.0) during recording.
  /// Polls recorder amplitude every 100ms, normalizes dBFS (-60..0) to 0.0..1.0.
  Stream<double> amplitudeStream() async* {
    while (_isRecording) {
      try {
        final amp = await _recorder.getAmplitude();
        final dB = amp.current;
        final clamped = dB.clamp(-60.0, 0.0);
        final normalized = (clamped + 60.0) / 60.0;
        yield normalized;
      } catch (_) {
        yield 0.0;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Persist a temporary recording to the app's documents directory.
  /// Returns the new permanent path.
  Future<String> persistRecording(String tempPath) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${docsDir.path}/audio');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }

    final fileName = tempPath.split('/').last;
    final newPath = '${audioDir.path}/$fileName';
    final tempFile = File(tempPath);
    await tempFile.copy(newPath);
    await tempFile.delete();
    return newPath;
  }

  /// Stop any active recording (file or stream).
  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _isRecording = false;
    await _recorder.stop();
  }

  /// Clean up resources.
  void dispose() {
    _recorder.dispose();
  }

  /// Delete a recording file.
  Future<void> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Ignore delete errors
    }
  }

  /// Delete all audio files in the persisted audio directory.
  Future<void> deleteAllAudioFiles() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${docsDir.path}/audio');
      if (await audioDir.exists()) {
        await audioDir.delete(recursive: true);
      }
    } catch (_) {
      // Ignore errors
    }
  }

  /// Merge multiple WAV segment files into a single WAV file.
  /// Reads PCM data from each WAV segment (skipping the 44-byte header),
  /// concatenates, and writes a new WAV file.
  /// Returns the persisted file path.
  Future<String> mergeWavSegments(List<String> segmentPaths) async {
    final allPcmChunks = <List<int>>[];

    for (final path in segmentPaths) {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.length > 44) {
          // Skip 44-byte WAV header, keep raw PCM data
          allPcmChunks.add(bytes.sublist(44));
        }
      }
    }

    if (allPcmChunks.isEmpty) {
      throw StateError('No audio data to merge');
    }

    final wavBytes = buildWavBytes(allPcmChunks);

    final docsDir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${docsDir.path}/audio');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }

    final fileName = 'live_${DateTime.now().millisecondsSinceEpoch}.wav';
    final filePath = '${audioDir.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(wavBytes);
    return filePath;
  }

  /// Delete a list of temporary segment files.
  Future<void> deleteSegmentFiles(List<String> paths) async {
    for (final path in paths) {
      await deleteFile(path);
    }
  }

  /// Build a WAV file in memory from raw PCM16 chunks.
  static Uint8List buildWavBytes(
    List<List<int>> pcmChunks, {
    int sampleRate = 16000,
    int numChannels = 1,
    int bitsPerSample = 16,
  }) {
    int dataSize = 0;
    for (final chunk in pcmChunks) {
      dataSize += chunk.length;
    }

    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;

    final header = ByteData(44);
    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, 36 + dataSize, Endian.little);
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    // fmt sub-chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little); // sub-chunk size
    header.setUint16(20, 1, Endian.little);  // PCM format
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    // data sub-chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final builder = BytesBuilder(copy: false);
    builder.add(header.buffer.asUint8List());
    for (final chunk in pcmChunks) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  /// Save raw PCM16 chunks as a WAV file in the persistent audio directory.
  Future<String> saveStreamAsWav(List<List<int>> pcmChunks) async {
    final wavBytes = buildWavBytes(pcmChunks);

    final docsDir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${docsDir.path}/audio');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }

    final fileName = 'stream_${DateTime.now().millisecondsSinceEpoch}.wav';
    final filePath = '${audioDir.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(wavBytes);
    return filePath;
  }
}
