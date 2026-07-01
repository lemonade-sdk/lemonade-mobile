import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/account_provider.dart';
import '../../providers/app_mode_provider.dart';
import '../../providers/nav_provider.dart';
import 'auth_gate.dart';
import 'conversations_drawer.dart';
import 'flow_editor_overlay.dart';
import 'image_lightbox_overlay.dart';
import 'live_call_overlay.dart';
import 'mode_sheet.dart';
import 'number_routing_overlay.dart';
import 'sub_sheet.dart';

/// Mounts the single active full-screen overlay above the shell, plus the auth
/// gate (shown automatically in Subscription mode while signed out).
class NexusOverlayHost extends ConsumerWidget {
  const NexusOverlayHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appModeProvider);
    final auth = ref.watch(authProvider);
    final overlay = ref.watch(overlayProvider);

    // Auth gate: blocks the app in Subscription mode until signed in.
    final showAuth =
        mode == AppMode.subscription && !auth.isSignedIn && !auth.busy;

    return Stack(
      children: [
        if (overlay.isOpen) _dispatch(overlay),
        if (showAuth) const Positioned.fill(child: AuthGate()),
      ],
    );
  }

  Widget _dispatch(NexusOverlayState s) {
    switch (s.kind) {
      case NexusOverlayKind.conversationsDrawer:
        return const Positioned.fill(child: ConversationsDrawer());
      case NexusOverlayKind.modeSheet:
        return const Positioned.fill(child: ModeSheet());
      case NexusOverlayKind.subSheet:
        return Positioned.fill(child: SubSheet(section: s.subSheetSection));
      case NexusOverlayKind.liveCall:
        return Positioned.fill(child: LiveCallOverlay(taskId: s.taskId!));
      case NexusOverlayKind.flowEditor:
        return Positioned.fill(child: FlowEditorOverlay(flowId: s.flowId));
      case NexusOverlayKind.numberRouting:
        return Positioned.fill(
            child: NumberRoutingOverlay(numberId: s.numberId!));
      case NexusOverlayKind.imageLightbox:
        return Positioned.fill(
            child: ImageLightboxOverlay(
          bytes: s.imageBytes,
          label: s.imageLabel,
          caption: s.imageCaption,
        ));
      case NexusOverlayKind.none:
        return const SizedBox.shrink();
    }
  }
}
