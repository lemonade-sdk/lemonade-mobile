import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_mode_provider.dart';
import '../providers/nav_provider.dart';
import '../screens/nexus/calls_tab.dart';
import '../screens/nexus/chat_tab.dart';
import '../screens/nexus/docs_tab.dart';
import '../screens/nexus/mesh_coming_soon.dart';
import '../screens/nexus/pbx_tab.dart';
import '../screens/nexus/projects_tab.dart';
import '../screens/nexus/settings_tab.dart';
import '../themes/nexus_tokens.dart';
import 'nexus_bottom_nav.dart';
import 'nexus_header.dart';
import 'overlays/nexus_overlay_host.dart';

/// The redesigned app shell: header + six-tab [IndexedStack] + bottom nav, with
/// all full-screen overlays/sheets stacked above via [NexusOverlayHost].
class NexusShell extends ConsumerWidget {
  const NexusShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final tab = ref.watch(navTabProvider);
    final mesh = ref.watch(appModeProvider) == AppMode.mesh;
    final overlayOpen = ref.watch(overlayProvider.select((s) => s.isOpen));

    // System back (Android button/gesture): close the open overlay first, then
    // step back to the Chat tab, and only exit the app from Chat with nothing
    // open. Overlays live in a Stack — not Navigator routes — so without this
    // the back button would background the app mid-flow.
    return PopScope(
      canPop: !overlayOpen && tab == NexusTab.chat,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (ref.read(overlayProvider).isOpen) {
          ref.read(overlayProvider.notifier).close();
        } else if (ref.read(navTabProvider) != NexusTab.chat) {
          ref.read(navTabProvider.notifier).state = NexusTab.chat;
        }
      },
      child: Scaffold(
        backgroundColor: t.bg,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            Column(
              children: [
                const NexusHeader(),
                Expanded(
                  // Mesh mode isn't wired yet — show the coming-soon screen
                  // instead of the tabs (header + nav stay so the user can
                  // switch back to Subscription / Local AI).
                  child: mesh
                      ? const MeshComingSoon()
                      : IndexedStack(
                          index: tab.index,
                          children: const [
                            ChatTab(),
                            ProjectsTab(),
                            CallsTab(),
                            PbxTab(),
                            DocsTab(),
                            SettingsTab(),
                          ],
                        ),
                ),
                // Hide the tab bar while the keyboard is open so the composer
                // isn't squeezed above nav + system bar + IME on short phones.
                if (MediaQuery.viewInsetsOf(context).bottom == 0)
                  const NexusBottomNav(),
              ],
            ),
            const NexusOverlayHost(),
          ],
        ),
      ),
    );
  }
}
