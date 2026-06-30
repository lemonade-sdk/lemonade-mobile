import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/account_provider.dart';
import '../../providers/app_mode_provider.dart';
import '../../providers/billing_providers.dart';
import '../../shell/overlays/unlock_sheet.dart';
import '../../themes/nexus_tokens.dart';
import 'nexus_ui.dart';

/// Gates a gateway feature behind: Subscription mode → signed in → (optionally)
/// an entitlement [capability]. When the capability is missing it shows an
/// "unlock" state that runs the §5 decision tree via [UnlockSheet]. The server
/// independently enforces capabilities (402/403), so this is UX only.
class GatewayGate extends ConsumerWidget {
  final IconData icon;
  final String feature;

  /// Required entitlement capability (e.g. 'pbx', 'aiCallTasks', 'calling').
  /// Null = no capability check (just needs the signed-in gateway).
  final String? capability;
  final Widget child;

  const GatewayGate({
    super.key,
    required this.icon,
    required this.feature,
    this.capability,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appModeProvider);
    final signedIn = ref.watch(authProvider).isSignedIn;

    if (mode != AppMode.subscription) {
      return NexusEmptyState(
        icon: icon,
        title: '$feature needs Subscription',
        message:
            '$feature runs on the Nexus cloud. Switch to Subscription mode in the header to use it.',
        action: _btn(context, 'Switch to Subscription',
            () => ref.read(appModeProvider.notifier).setMode(AppMode.subscription)),
      );
    }
    if (!signedIn) {
      return NexusEmptyState(
        icon: icon,
        title: 'Sign in to use $feature',
        message: 'Sign in to your Nexus account to manage $feature.',
        action: null,
      );
    }
    if (capability == null) return child;

    final ent = ref.watch(entitlementsProvider);
    return ent.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      // Fail open on error — the server still enforces; better than a blank gate.
      error: (_, __) => child,
      data: (e) {
        if (e.capabilities.has(capability!)) return child;
        return NexusEmptyState(
          icon: icon,
          title: 'Unlock $feature',
          message: e.isPersonal
              ? '$feature unlocks with a wallet-billed membership.'
              : '$feature is part of the Phone System package on your plan.',
          action: _btn(
              context,
              'Unlock $feature',
              () => UnlockSheet.show(context,
                  capability: capability!, feature: feature)),
        );
      },
    );
  }

  Widget _btn(BuildContext context, String label, VoidCallback onTap) {
    final t = context.nexus;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
            color: t.accent, borderRadius: BorderRadius.circular(12)),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}
