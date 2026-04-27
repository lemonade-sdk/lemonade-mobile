import 'package:just_audio/just_audio.dart';

class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();

  /// Load an audio file and return its duration.
  Future<Duration> setFile(String filePath) async {
    final duration = await _player.setFilePath(filePath);
    return duration ?? Duration.zero;
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();
  Future<void> seek(Duration position) => _player.seek(position);

  Stream<Duration> get positionStream => _player.positionStream;
  Duration? get duration => _player.duration;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  bool get isPlaying => _player.playing;

  void dispose() {
    _player.dispose();
  }
}
