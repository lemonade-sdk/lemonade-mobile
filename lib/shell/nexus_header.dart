import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/account_provider.dart';
import '../providers/app_mode_provider.dart';
import '../providers/device_stats_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/servers_provider.dart';
import '../providers/theme_provider.dart';
import '../themes/nexus_tokens.dart';
import '../themes/theme_registry.dart';
import '../themes/nexus_theme_builder.dart';
import '../widgets/nexus/nexus_ui.dart';

/// Top chrome: brand, theme toggle, avatar, mode switcher, and the tappable
/// connection-status strip (opens the Mode sheet).
class NexusHeader extends ConsumerWidget {
  const NexusHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final mode = ref.watch(appModeProvider);
    final theme = ref.watch(themeProvider);
    final isLight = theme.id == ThemeRegistry.nexusLightId;
    final auth = ref.watch(authProvider);
    final topPad = MediaQuery.of(context).padding.top;

    final initials = _initials(auth.user?.displayName);
    final status = _statusFor(ref, mode);

    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 0),
      decoration: BoxDecoration(
        color: t.bg2,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Column(
        children: [
          // brand row
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const LemonLogo(size: 26),
                const SizedBox(width: 9),
                const LemonadeWordmark(),
                const Spacer(),
                NexusIconButton(
                  icon: isLight ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  onTap: () => ref.read(themeProvider.notifier).setThemeId(
                        isLight
                            ? ThemeRegistry.nexusDarkId
                            : ThemeRegistry.nexusLightId,
                      ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: t.line),
                  ),
                  child: Text(initials,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.muted)),
                ),
              ],
            ),
          ),

          // mode switcher
          NexusSegmented<AppMode>(
            value: mode,
            onChanged: (m) => ref.read(appModeProvider.notifier).setMode(m),
            options: const [
              (AppMode.subscription, 'Subscription'),
              (AppMode.local, 'Local AI'),
              (AppMode.mesh, 'Mesh'),
            ],
          ),
          const SizedBox(height: 10),

          // connection status strip
          GestureDetector(
            onTap: () => ref.read(overlayProvider.notifier).openModeSheet(),
            behavior: HitTestBehavior.opaque,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: t.line),
              ),
              child: Row(
                children: [
                  NexusStatusDot(color: status.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: t.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(status.meta,
                      style: nexusMono(fontSize: 10.5, color: t.muted)),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right, size: 16, color: t.faint),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '··';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  _Status _statusFor(WidgetRef ref, AppMode mode) {
    final t = NexusTokens.dark; // colors are mode-semantic, not theme-dependent
    switch (mode) {
      case AppMode.subscription:
        final auth = ref.watch(authProvider);
        if (auth.isSignedIn) {
          return _Status(t.good, 'Nexus Subscription · routed cloud', 'online');
        }
        return _Status(t.warn, 'Subscription · sign in to route', 'signed out');
      case AppMode.local:
        final server = ref.watch(selectedServerProvider);
        if (server == null) {
          return _Status(t.warn, 'Local AI · no server selected', 'add server');
        }
        final stats = ref.watch(systemStatsProvider).valueOrNull;
        final parts = <String>[];
        final gpu = stats?['gpu_percent'];
        final cpu = stats?['cpu_percent'];
        if (gpu is num) parts.add('GPU ${gpu.round()}%');
        if (cpu is num) parts.add('CPU ${cpu.round()}%');
        return _Status(
            stats == null ? t.warn : t.good,
            server.name,
            parts.isEmpty ? 'local' : parts.join(' · '));
      case AppMode.mesh:
        return _Status(t.accent2, 'Agentic Mesh', 'coming soon');
    }
  }
}

class _Status {
  final Color color;
  final String title;
  final String meta;
  _Status(this.color, this.title, this.meta);
}
