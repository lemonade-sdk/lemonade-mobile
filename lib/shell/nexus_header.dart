import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/account_provider.dart';
import '../providers/app_mode_provider.dart';
import '../providers/beacon_provider.dart';
import '../providers/device_stats_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/servers_provider.dart';
import '../providers/theme_provider.dart';
import '../themes/nexus_tokens.dart';
import '../themes/theme_registry.dart';
import '../widgets/nexus/gateway_gate.dart';
import '../widgets/nexus/nexus_ui.dart';

/// Top chrome, collapsed to a single row: brand + a tappable
/// connection/mode chip (opens the Mode sheet) + theme toggle + avatar.
/// The old layout stacked brand / mode switcher / status strip as three
/// separate rows — one row now, mode switching lives in the Mode sheet.
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

    final status = _statusFor(ref, mode);
    final signedIn = auth.isSignedIn;

    return Container(
      padding: EdgeInsets.fromLTRB(14, topPad + 8, 14, 8),
      decoration: BoxDecoration(
        color: t.bg2,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        children: [
          const LemonLogo(size: 24),
          const SizedBox(width: 10),
          // Connection + mode chip — the former status strip. Tap opens the
          // Mode sheet (which also switches Subscription / Local AI / Mesh).
          Expanded(
            child: GestureDetector(
              onTap: () => ref.read(overlayProvider.notifier).openModeSheet(),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: t.line),
                ),
                child: Row(
                  children: [
                    NexusStatusDot(color: status.color),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        status.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.text,
                        ),
                      ),
                    ),
                    if (status.meta.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          status.meta,
                          overflow: TextOverflow.ellipsis,
                          style: nexusMono(fontSize: 10, color: t.muted),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(Icons.expand_more, size: 15, color: t.faint),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          NexusIconButton(
            icon: isLight
                ? Icons.dark_mode_outlined
                : Icons.light_mode_outlined,
            onTap: () => ref
                .read(themeProvider.notifier)
                .setThemeId(
                  isLight
                      ? ThemeRegistry.nexusDarkId
                      : ThemeRegistry.nexusLightId,
                ),
          ),
          const SizedBox(width: 8),
          // Avatar → account. Signed out in Subscription mode it opens
          // sign-in; otherwise it jumps to Settings (account section).
          // Was a plain Container that testers tapped expecting a menu.
          GestureDetector(
            onTap: () {
              if (mode == AppMode.subscription && !signedIn) {
                SignInScreen.push(context);
              } else {
                ref.read(navTabProvider.notifier).state = NexusTab.settings;
              }
            },
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: t.line),
              ),
              child: signedIn
                  ? Text(
                      _initials(auth.user?.displayName),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.muted,
                      ),
                    )
                  : Icon(Icons.person_outline, size: 17, color: t.muted),
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
      return parts.first
          .substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  _Status _statusFor(WidgetRef ref, AppMode mode) {
    final t = NexusTokens.dark; // colors are mode-semantic, not theme-dependent
    switch (mode) {
      case AppMode.subscription:
        final auth = ref.watch(authProvider);
        if (auth.isSignedIn) {
          return _Status(t.good, 'Subscription', 'online');
        }
        return _Status(t.warn, 'Subscription', 'sign in to route');
      case AppMode.local:
        final server = ref.watch(selectedServerProvider);
        // The local server is discovered/selected asynchronously, so right
        // after switching modes the previous (gateway) selection can linger
        // for a beat. Treat "no local server yet" as a search-in-progress
        // state instead of showing the subscription/gateway name.
        final onLocalServer = server != null;
        if (!onLocalServer) {
          final found = ref.watch(discoveredServersProvider).length;
          if (found > 0) {
            return _Status(t.accent2, 'Local AI', '$found found · tap to pick');
          }
          return _Status(t.warn, 'Local AI', 'searching…');
        }
        final stats = ref.watch(systemStatsProvider).valueOrNull;
        final parts = <String>[];
        final gpu = stats?['gpu_percent'];
        final cpu = stats?['cpu_percent'];
        if (gpu is num) parts.add('GPU ${gpu.round()}%');
        if (cpu is num) parts.add('CPU ${cpu.round()}%');
        return _Status(
          stats == null ? t.warn : t.good,
          'Local AI · ${server.name}',
          parts.isEmpty ? 'local' : parts.join(' · '),
        );
      case AppMode.mesh:
        return _Status(t.accent2, 'Mesh', 'coming soon');
    }
  }
}

class _Status {
  final Color color;
  final String label;
  final String meta;
  _Status(this.color, this.label, this.meta);
}
