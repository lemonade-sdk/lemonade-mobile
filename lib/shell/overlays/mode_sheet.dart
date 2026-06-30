import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_mode_provider.dart';
import '../../providers/nav_provider.dart';
import '../../themes/nexus_tokens.dart';
import 'sheet_scaffold.dart';

/// Inference-mode picker (Subscription / Local AI / Mesh).
class ModeSheet extends ConsumerWidget {
  const ModeSheet({super.key});

  static const _modes = <(AppMode, IconData, String, String, String)>[
    (
      AppMode.subscription,
      Icons.cloud_outlined,
      'Subscription',
      'Routed cloud inference + Calls, PBX & Docs.',
      'Unlocks gateway features',
    ),
    (
      AppMode.local,
      Icons.dns_outlined,
      'Local AI',
      'Run a Lemonade server on your LAN or this device.',
      'Unlocks on-device Model Manager',
    ),
    (
      AppMode.mesh,
      Icons.hub_outlined,
      'Mesh',
      'Agentic WireGuard mesh across your devices.',
      'Coming soon',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final current = ref.watch(appModeProvider);
    final close = ref.read(overlayProvider.notifier).close;

    return SheetScaffold(
      onClose: close,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Inference mode',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 4),
          Text(
              'Switch where Lemonade runs. Local modes unlock device & model settings.',
              style: TextStyle(fontSize: 12.5, color: t.muted)),
          const SizedBox(height: 16),
          for (final (mode, icon, title, desc, unlock) in _modes) ...[
            GestureDetector(
              onTap: () {
                ref.read(appModeProvider.notifier).setMode(mode);
                close();
              },
              child: Container(
                padding: const EdgeInsets.all(15),
                margin: const EdgeInsets.only(bottom: 11),
                decoration: BoxDecoration(
                  color: mode == current ? t.accentSoft : t.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: mode == current ? t.accent : t.line2, width: 1.5),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: t.surface2,
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: t.accent2, size: 21),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(title,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: t.text)),
                            const Spacer(),
                            if (mode == current)
                              Icon(Icons.check_circle,
                                  color: t.accent, size: 18),
                          ]),
                          const SizedBox(height: 5),
                          Text(desc,
                              style: TextStyle(
                                  fontSize: 12, height: 1.45, color: t.muted)),
                          const SizedBox(height: 7),
                          Text('→ $unlock',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: t.accent2)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
