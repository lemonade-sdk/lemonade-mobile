import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../themes/nexus_tokens.dart';

/// Shown for the (not-yet-implemented) Mesh mode. Points at the open-source
/// mesh project on GitHub.
class MeshComingSoon extends StatelessWidget {
  const MeshComingSoon({super.key});

  static const _repo = 'https://github.com/lemonade-sdk/lemonade-nexus';

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return Container(
      color: t.bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: t.line2),
            ),
            child: Icon(Icons.hub_outlined, color: t.accent2, size: 34),
          ),
          const SizedBox(height: 18),
          Text('Agentic Mesh',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 6),
          Text('Coming soon',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: t.accent2)),
          const SizedBox(height: 12),
          Text(
              'Self-hosted, cryptographically secure WireGuard mesh for routing inference across your own devices. Not wired into the app yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: t.muted)),
          const SizedBox(height: 22),
          GestureDetector(
            onTap: () => launchUrl(Uri.parse(_repo),
                mode: LaunchMode.externalApplication),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: t.line2),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.open_in_new, size: 16, color: t.accent2),
                const SizedBox(width: 9),
                Text('lemonade-sdk/lemonade-nexus',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.accent2)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
