import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/admin_mode_provider.dart';
import '../providers/omni_router_provider.dart';
import '../providers/servers_provider.dart';
import 'admin_console_screen.dart';
import 'omni_router_screen.dart';
import 'servers_screen.dart';
import 'transcription_screen.dart';
import '../widgets/server_selector.dart';
import '../widgets/theme_picker.dart';

/// Top-level Settings screen — pure navigation menu. Each row links to a
/// dedicated screen so individual concerns don't pile up on one page.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final omniEnabled = ref.watch(omniRouterEnabledProvider);
    final adminEnabled = ref.watch(adminModeProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ====== Theme ======
          const ThemePicker(),
          const SizedBox(height: 24),
          const Divider(),

          // ====== Active server picker ======
          // Same widget the chat drawer uses, so switching the active server
          // works from either entry point. The "Servers" row below still
          // links to the full management screen.
          const ServerSelector(),

          // ====== Servers ======
          ListTile(
            leading: Icon(Icons.dns_outlined, color: scheme.primary),
            title: const Text('Manage servers'),
            subtitle: Text(
              servers.isEmpty
                  ? 'No servers configured'
                  : '${servers.length} server${servers.length == 1 ? "" : "s"} configured',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ServersScreen()),
            ),
          ),

          // ====== Lemonade Omni ======
          ListTile(
            leading: Icon(Icons.hub_outlined, color: scheme.primary),
            title: const Text('Lemonade Omni'),
            subtitle: Text(
              omniEnabled
                  ? 'On — multimodal tools enabled'
                  : 'Off — manual fallback mode',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: omniEnabled,
                  onChanged: (v) => ref
                      .read(omniRouterEnabledProvider.notifier)
                      .setEnabled(v),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OmniRouterScreen()),
            ),
          ),

          // ====== Transcription tool ======
          // Standalone audio-file → text utility. The primary in-chat voice
          // experience lives on the mic button in the chat input; this page
          // is the legacy/power-user tool for capturing a one-shot recording.
          ListTile(
            leading: Icon(Icons.transcribe_outlined, color: scheme.primary),
            title: const Text('Transcription tool'),
            subtitle: const Text(
              'Standalone audio recorder + transcriber (not needed for normal voice chat).',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TranscriptionScreen()),
            ),
          ),

          // ====== Admin Mode ======
          SwitchListTile(
            secondary:
                Icon(Icons.admin_panel_settings_outlined, color: scheme.primary),
            title: const Text('Admin Mode'),
            subtitle: const Text(
              'Reveals the Admin Console (server health, model management, '
              'backends, system info, logs).',
            ),
            value: adminEnabled,
            onChanged: (v) =>
                ref.read(adminModeProvider.notifier).setEnabled(v),
          ),
          if (adminEnabled)
            ListTile(
              leading: Icon(Icons.dashboard_customize_outlined,
                  color: scheme.primary),
              title: const Text('Open Admin Console'),
              subtitle: const Text('Manage the connected Lemonade server'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminConsoleScreen()),
              ),
            ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              'Lemonade Mobile',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
