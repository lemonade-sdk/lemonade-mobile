import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_mode_provider.dart';
import '../providers/call_tasks_providers.dart';
import '../providers/nav_provider.dart';
import '../themes/nexus_tokens.dart';

/// Persistent bottom navigation: Chat / Projects / Calls / PBX / Docs / Settings.
class NexusBottomNav extends ConsumerWidget {
  const NexusBottomNav({super.key});

  static const _items = <(NexusTab, IconData, String)>[
    (NexusTab.chat, Icons.forum_outlined, 'Chat'),
    (NexusTab.projects, Icons.layers_outlined, 'Projects'),
    (NexusTab.calls, Icons.call_outlined, 'Calls'),
    (NexusTab.pbx, Icons.grid_view_rounded, 'PBX'),
    (NexusTab.docs, Icons.description_outlined, 'Docs'),
    (NexusTab.settings, Icons.settings_outlined, 'Settings'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final current = ref.watch(navTabProvider);
    final mode = ref.watch(appModeProvider);
    final callLive = ref.watch(activeCallTaskProvider).valueOrNull != null;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    // Projects / Calls / PBX / Docs are cloud features — greyed out unless in
    // Subscription mode. Chat + Settings are always available.
    bool enabled(NexusTab tab) =>
        tab == NexusTab.chat ||
        tab == NexusTab.settings ||
        mode == AppMode.subscription;

    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, bottomPad > 0 ? bottomPad : 14),
      decoration: BoxDecoration(
        color: t.bg2,
        border: Border(top: BorderSide(color: t.line)),
      ),
      child: Row(
        children: [
          for (final (tab, icon, label) in _items)
            Builder(builder: (_) {
              final on = enabled(tab);
              final tint = !on
                  ? t.faint.withValues(alpha: 0.35)
                  : (tab == current ? t.accent : t.faint);
              return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: on
                    ? () => ref.read(navTabProvider.notifier).state = tab
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(icon, size: 23, color: tint),
                          if (tab == NexusTab.calls && callLive && on)
                            Positioned(
                              right: -3,
                              top: -2,
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: t.live,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(color: t.live, blurRadius: 6)
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: tint,
                          )),
                    ],
                  ),
                ),
              ),
            );
            }),
        ],
      ),
    );
  }
}
