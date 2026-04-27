import 'dart:async';
import 'dart:io';
import 'package:mic_stream_recorder/mic_stream_recorder.dart';
import 'package:path_provider/path_provider.dart';

/// Service for live audio recording using mic_stream_recorder.
/// Records M4A/AAC segments via file-based start/stop rotation.
/// Provides a native amplitude stream for real-time visualization.
class LiveStreamService {
  final MicStreamRecorder _recorder = MicStreamRecorder();

  bool _isRecording = false;
  String? _currentFilePath;
  final List<String> _allSegmentPaths = [];

  bool get isRecording => _isRecording;

  /// Real-time amplitude stream (0.0 - 1.0) from the native platform.
  Stream<double> get amplitudeStream => _recorder.amplitudeStream;

  /// Start recording the first segment.
  Future<void> start({double sampleRate = 16000}) async {
    if (_isRecording) return;
    _allSegmentPaths.clear();

    await _recorder.configureRecording(
      sampleRate: sampleRate,
      channels: 1,
      audioQuality: AudioQuality.high,
    );

    final dir = await getTemporaryDirectory();
    _currentFilePath =
        '${dir.path}/live_seg_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.startRecording(_currentFilePath);
    _isRecording = true;
  }

  /// Rotate to a new segment: stop current recording, start a new one.
  /// Returns the completed segment's file path, or null if nothing recorded.
  Future<String?> rotateSegment() async {
    if (!_isRecording) return null;

    // Stop current segment
    final completedPath = await _recorder.stopRecording();
    if (completedPath != null && completedPath.isNotEmpty) {
      _allSegmentPaths.add(completedPath);
    }

    // Start next segment immediately
    final dir = await getTemporaryDirectory();
    _currentFilePath =
        '${dir.path}/live_seg_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.startRecording(_currentFilePath);

    return completedPath;
  }

  /// Stop recording entirely. Returns the final segment's file path.
  Future<String?> stop() async {
    if (!_isRecording) return null;
    _isRecording = false;

    String? finalPath;
    try {
      finalPath = await _recorder.stopRecording();
      if (finalPath != null && finalPath.isNotEmpty) {
        _allSegmentPaths.add(finalPath);
      }
    } catch (_) {}

    _currentFilePath = null;
    return finalPath;
  }

  /// All segment file paths from this session.
  List<String> get allSegmentPaths => List.unmodifiable(_allSegmentPaths);

  /// Persist all session segments to the app's persistent audio directory.
  /// Copies files and returns the list of persisted paths.
  Future<List<String>> persistAllSegments() async {
    if (_allSegmentPaths.isEmpty) return [];

    final docsDir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${docsDir.path}/audio');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }

    final persistedPaths = <String>[];
    for (final segPath in _allSegmentPaths) {
      try {
        final file = File(segPath);
        if (await file.exists()) {
          final fileName = segPath.split('/').last;
          final destPath = '${audioDir.path}/$fileName';
          await file.copy(destPath);
          persistedPaths.add(destPath);
        }
      } catch (_) {}
    }

    return persistedPaths;
  }

  /// Clean up all temporary segment files.
  Future<void> cleanupTempSegments() async {
    for (final path in _allSegmentPaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    _allSegmentPaths.clear();
  }

  /// Clean up resources.
  void dispose() {
    if (_isRecording) {
      _recorder.stopRecording();
      _isRecording = false;
    }
    _currentFilePath = null;
    _allSegmentPaths.clear();
  }
}
