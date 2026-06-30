import 'package:flutter/material.dart';

import '../../themes/nexus_tokens.dart';

/// Scrim + bottom sheet with the design's grab handle and slide-up animation.
/// Tapping the scrim calls [onClose].
class SheetScaffold extends StatelessWidget {
  final VoidCallback onClose;
  final Widget child;
  final double maxHeightFactor;

  const SheetScaffold({
    super.key,
    required this.onClose,
    required this.child,
    this.maxHeightFactor = 0.86,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: Container(color: Colors.black.withValues(alpha: 0.6)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _Slide(
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * maxHeightFactor,
              ),
              decoration: BoxDecoration(
                color: t.bg2,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(26)),
                border: Border(top: BorderSide(color: t.line2)),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: t.line2,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      child,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Slide extends StatefulWidget {
  final Widget child;
  const _Slide({required this.child});

  @override
  State<_Slide> createState() => _SlideState();
}

class _SlideState extends State<_Slide> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
      child: widget.child,
    );
  }
}
