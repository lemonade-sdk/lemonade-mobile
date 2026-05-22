import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Wraps a child with the AI Super Hack visual flair: a subtle scanline overlay,
/// a soft vignette, and an ever-so-slight neon-green glow tint at the corners.
///
/// Cheap to render (CustomPaint over a single repaint boundary). Only used when
/// the active theme's [ThemeDecorations.useScanlines] is true.
class AiSuperHackOverlay extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final bool animated;
  /// When false, this widget is a tree-stable passthrough — keeps the same
  /// position in the element tree as themes that *do* enable scanlines, so
  /// MaterialApp.builder doesn't reshape its descendants on theme switch.
  final bool enabled;

  const AiSuperHackOverlay({
    super.key,
    required this.child,
    this.glowColor = const Color(0xFF39FF14),
    this.animated = true,
    this.enabled = true,
  });

  @override
  State<AiSuperHackOverlay> createState() => _AiSuperHackOverlayState();
}

class _AiSuperHackOverlayState extends State<AiSuperHackOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant AiSuperHackOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    final shouldRun = widget.enabled && widget.animated;
    if (shouldRun && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!shouldRun && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always wrap in a Stack so the element tree shape is identical whether
    // or not scanlines are drawn — toggling between Stack and bare child
    // during a theme switch is what triggered the `_elements.contains`
    // assertion in MaterialApp's rebuild.
    return Stack(
      children: [
        widget.child,
        if (widget.enabled)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) => CustomPaint(
                  painter: _ScanlinePainter(
                    phase: _ctrl.value,
                    glow: widget.glowColor,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  final double phase;
  final Color glow;

  _ScanlinePainter({required this.phase, required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x18000000);
    const lineHeight = 2.0;
    const lineGap = 2.0;
    for (double y = 0; y < size.height; y += lineHeight + lineGap) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, lineHeight), paint);
    }

    // Slow horizontal scan beam.
    final beamY = (phase * (size.height + 80)) - 40;
    final beamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          glow.withValues(alpha: 0),
          glow.withValues(alpha: 0.10),
          glow.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, beamY, size.width, 80));
    canvas.drawRect(Rect.fromLTWH(0, beamY, size.width, 80), beamPaint);

    // Soft corner glow.
    final cornerGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          glow.withValues(alpha: 0.08),
          glow.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromCircle(center: Offset.zero, radius: math.max(size.width, size.height) * 0.6),
      );
    canvas.drawRect(Offset.zero & size, cornerGlow);
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.glow != glow;
  }
}
