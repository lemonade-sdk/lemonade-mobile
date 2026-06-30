import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../themes/nexus_tokens.dart';

// Re-export the IBM Plex Mono helper so any file importing nexus_ui gets it.
export '../../themes/nexus_theme_builder.dart' show nexusMono;

/// Shared visual primitives for the Lemonade Mobile (Nexus design) UI. Keeps the
/// six tabs and the overlays visually consistent and terse.

/// A rounded surface card with the design's hairline border.
class NexusCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final Gradient? gradient;
  final VoidCallback? onTap;

  const NexusCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(15),
    this.radius = 16,
    this.color,
    this.borderColor,
    this.gradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? t.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? t.line),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: card,
    );
  }
}

/// A small filled icon tile (header/sub-header buttons).
class NexusIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? iconColor;
  final double size;
  const NexusIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.iconColor,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: t.line),
        ),
        child: Icon(icon, size: size * 0.5, color: iconColor ?? t.muted),
      ),
    );
  }
}

/// A pulsing status dot (online / live / running).
class NexusStatusDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool pulse;
  const NexusStatusDot({
    super.key,
    required this.color,
    this.size = 7,
    this.pulse = true,
  });

  @override
  State<NexusStatusDot> createState() => _NexusStatusDotState();
}

class _NexusStatusDotState extends State<NexusStatusDot>
    with SingleTickerProviderStateMixin {
  // Created ONLY when pulsing. A lazily-initialized `late final` controller
  // would be constructed inside dispose() for a non-pulsing dot (the field is
  // first touched there), which creates a Ticker on a deactivated element and
  // throws "Looking up a deactivated widget's ancestor is unsafe."
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: widget.color, blurRadius: 8)],
      ),
    );
    final c = _c;
    if (!widget.pulse || c == null) return dot;
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.25).animate(c),
      child: dot,
    );
  }
}

/// A small labeled pill (badges, route types, statuses).
class NexusPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color? bg;
  final bool outlined;
  const NexusPill(
    this.label, {
    super.key,
    required this.color,
    this.bg,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg ?? (outlined ? Colors.transparent : t.accentSoft),
        borderRadius: BorderRadius.circular(6),
        border: outlined ? Border.all(color: color) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Uppercase faint section label.
class NexusSectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const NexusSectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    final label = Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: t.faint,
      ),
    );
    if (trailing == null) return label;
    return Row(children: [label, const Spacer(), trailing!]);
  }
}

/// A segmented control (header mode switch, PBX sub-nav).
class NexusSegmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final double fontSize;
  const NexusSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: t.line),
      ),
      child: Row(
        children: [
          for (final (val, label) in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(val),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: val == value ? t.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                      color: val == value ? Colors.white : t.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// An empty / gated state (e.g. "Sign in to Subscription to use Calls").
class NexusEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const NexusEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.line),
              ),
              child: Icon(icon, color: t.accent2, size: 26),
            ),
            const SizedBox(height: 14),
            Text(title,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: t.text)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.45, color: t.muted)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// The Lemonade brand mark — the design's inline lemon SVG.
class LemonLogo extends StatelessWidget {
  final double size;
  const LemonLogo({super.key, this.size = 26});

  static const _svg = '''
<svg width="26" height="26" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="22.5" cy="8.5" rx="3.6" ry="2.1" transform="rotate(38 22.5 8.5)" fill="#5cb85b"/>
  <path d="M20 11c1.4-2.4 3.8-3.4 5.6-2.6" stroke="#3f9a4e" stroke-width="1" stroke-linecap="round"/>
  <g transform="rotate(-32 16 17)">
    <ellipse cx="16" cy="17" rx="11.4" ry="8.4" fill="#f6ce3b"/>
    <ellipse cx="16" cy="17" rx="11.4" ry="8.4" fill="none" stroke="#dcae27" stroke-width="1"/>
    <path d="M4.6 17H2.4M29.4 17h2.2" stroke="#dcae27" stroke-width="2.2" stroke-linecap="round"/>
    <ellipse cx="11.5" cy="13" rx="4.6" ry="2.4" fill="#fce58a" opacity="0.85"/>
  </g>
</svg>''';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(_svg, width: size, height: size);
  }
}

/// "Lemonade Mobile" wordmark with the accented "Mobile".
class LemonadeWordmark extends StatelessWidget {
  final double fontSize;
  const LemonadeWordmark({super.key, this.fontSize = 18});

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
              text: 'Lemonade',
              style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
          TextSpan(
              text: ' Mobile',
              style: TextStyle(color: t.accent, fontWeight: FontWeight.w700)),
        ],
      ),
      style: TextStyle(fontSize: fontSize, letterSpacing: -0.3),
    );
  }
}
