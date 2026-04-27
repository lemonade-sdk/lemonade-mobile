import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/providers/transcription_provider.dart';

class LiveAudioVisualizer extends ConsumerStatefulWidget {
  final Color color;
  final int barCount;
  final double height;

  const LiveAudioVisualizer({
    super.key,
    required this.color,
    this.barCount = 24,
    this.height = 60,
  });

  @override
  ConsumerState<LiveAudioVisualizer> createState() => _LiveAudioVisualizerState();
}

class _LiveAudioVisualizerState extends ConsumerState<LiveAudioVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<double> _bars = [];

  @override
  void initState() {
    super.initState();
    _bars = List.filled(widget.barCount, 0.0);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amplitudes = ref.watch(recordingAmplitudesProvider);

    // Update bars: push new amplitude onto right end, shift left
    if (amplitudes.isNotEmpty) {
      final latest = amplitudes.last;
      _bars = [..._bars.sublist(1), latest];
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _BarPainter(
            bars: _bars,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<double> bars;
  final Color color;

  _BarPainter({required this.bars, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    final barCount = bars.length;
    final totalSpacing = (barCount - 1) * 2.0;
    final barWidth = (size.width - totalSpacing) / barCount;
    final clampedBarWidth = barWidth.clamp(2.0, 8.0);
    final actualTotalWidth = barCount * clampedBarWidth + (barCount - 1) * 2.0;
    final startX = (size.width - actualTotalWidth) / 2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < barCount; i++) {
      final amplitude = bars[i].clamp(0.0, 1.0);
      // Minimum bar height of 4px for visual appeal
      final barHeight = max(4.0, amplitude * size.height);
      final x = startX + i * (clampedBarWidth + 2.0);
      final y = (size.height - barHeight) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, clampedBarWidth, barHeight),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_BarPainter oldDelegate) => true;
}
