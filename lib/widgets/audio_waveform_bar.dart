import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lemonade_mobile/constants/colors.dart';
import 'package:lemonade_mobile/services/audio_playback_service.dart';
import 'package:just_audio/just_audio.dart';

class AudioWaveformBar extends StatefulWidget {
  final String filePath;
  final List<double> amplitudes;
  final Duration duration;

  const AudioWaveformBar({
    super.key,
    required this.filePath,
    this.amplitudes = const [],
    required this.duration,
  });

  @override
  State<AudioWaveformBar> createState() => _AudioWaveformBarState();
}

class _AudioWaveformBarState extends State<AudioWaveformBar> {
  late AudioPlaybackService _playback;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _initialized = false;
  late List<double> _displayAmplitudes;

  @override
  void initState() {
    super.initState();
    _playback = AudioPlaybackService();
    _displayAmplitudes = _buildDisplayAmplitudes();
    _initPlayer();
  }

  List<double> _buildDisplayAmplitudes() {
    const targetBars = 40;
    if (widget.amplitudes.isNotEmpty) {
      // Downsample or upsample to target bar count
      final src = widget.amplitudes;
      if (src.length == targetBars) return List.from(src);
      return List.generate(targetBars, (i) {
        final srcIndex = (i * src.length / targetBars).floor().clamp(0, src.length - 1);
        return src[srcIndex];
      });
    }
    // Generate gentle random variation for historical recordings
    final rng = Random(widget.filePath.hashCode);
    return List.generate(targetBars, (_) => 0.15 + rng.nextDouble() * 0.5);
  }

  Future<void> _initPlayer() async {
    try {
      final dur = await _playback.setFile(widget.filePath);
      if (!mounted) return;
      setState(() {
        _duration = dur;
        _initialized = true;
      });

      _playback.positionStream.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });

      _playback.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() => _isPlaying = state.playing);
        // Reset when playback completes
        if (state.processingState == ProcessingState.completed) {
          _playback.seek(Duration.zero);
          _playback.pause();
        }
      });
    } catch (_) {
      // File may not exist anymore
    }
  }

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const SizedBox(
        height: 56,
        child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final effectiveDuration = _duration > Duration.zero ? _duration : widget.duration;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            // Play/pause button
            IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                color: AppColors.waveformPlayed,
                size: 36,
              ),
              onPressed: () {
                if (_isPlaying) {
                  _playback.pause();
                } else {
                  _playback.play();
                }
              },
            ),

            // Waveform
            Expanded(
              child: GestureDetector(
                onTapDown: (details) {
                  if (effectiveDuration <= Duration.zero) return;
                  final box = context.findRenderObject() as RenderBox;
                  // Account for play button + padding on left
                  final localX = details.localPosition.dx;
                  final waveformWidth = box.size.width - 52 - 60; // minus play btn and duration label
                  if (waveformWidth <= 0) return;
                  final adjustedX = localX;
                  final fraction = (adjustedX / waveformWidth).clamp(0.0, 1.0);
                  final seekTo = Duration(
                    milliseconds: (fraction * effectiveDuration.inMilliseconds).round(),
                  );
                  _playback.seek(seekTo);
                },
                child: CustomPaint(
                  size: const Size(double.infinity, 36),
                  painter: _WaveformPainter(
                    amplitudes: _displayAmplitudes,
                    progress: effectiveDuration > Duration.zero
                        ? _position.inMilliseconds / effectiveDuration.inMilliseconds
                        : 0.0,
                  ),
                ),
              ),
            ),

            // Duration label
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '${_formatDuration(_position)} / ${_formatDuration(effectiveDuration)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final double progress;

  _WaveformPainter({required this.amplitudes, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;

    final barCount = amplitudes.length;
    final gap = 2.0;
    final barWidth = ((size.width - (barCount - 1) * gap) / barCount).clamp(1.0, 6.0);
    final actualTotalWidth = barCount * barWidth + (barCount - 1) * gap;
    final startX = (size.width - actualTotalWidth) / 2;

    final playedPaint = Paint()
      ..color = AppColors.waveformPlayed
      ..style = PaintingStyle.fill;
    final unplayedPaint = Paint()
      ..color = AppColors.waveformUnplayed
      ..style = PaintingStyle.fill;

    final progressX = startX + progress * actualTotalWidth;

    for (int i = 0; i < barCount; i++) {
      final amp = amplitudes[i].clamp(0.0, 1.0);
      final barHeight = max(3.0, amp * size.height);
      final x = startX + i * (barWidth + gap);
      final y = (size.height - barHeight) / 2;
      final barMidX = x + barWidth / 2;

      final paint = barMidX <= progressX ? playedPaint : unplayedPaint;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.amplitudes != amplitudes;
  }
}
