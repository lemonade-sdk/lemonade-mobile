import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/providers/servers_provider.dart';
import 'package:lemonade_mobile/screens/servers_screen.dart';

/// Drawer-friendly picker for the active server. Tapping a row switches
/// `selectedServerProvider`, which cascades through `lemonadeClientProvider`
/// to flip every API call to the new host.
class ServerSelector extends ConsumerWidget {
  const ServerSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final selected = ref.watch(selectedServerProvider);

    // Auto-pick the first server on cold start so the rest of the app has
    // something to talk to without forcing the user through Settings.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (selected == null && servers.isNotEmpty) {
        ref.read(selectedServerProvider.notifier).selectServer(servers.first);
      }
    });

    return ExpansionTile(
      leading: const Icon(Icons.dns_outlined),
      title: const Text('Server'),
      subtitle: Text(
        selected?.name ??
            (servers.isEmpty ? 'No servers configured' : 'Pick a server'),
        overflow: TextOverflow.ellipsis,
      ),
      children: [
        if (servers.isEmpty)
          ListTile(
            dense: true,
            leading: const Icon(Icons.add),
            title: const Text('Add a server'),
            onTap: () => _openServersScreen(context),
          )
        else ...[
          for (final server in servers)
            ListTile(
              dense: true,
              leading: Icon(
                server.name == selected?.name
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: server.name == selected?.name
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(server.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                server.baseUrl,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              selected: server.name == selected?.name,
              onTap: () {
                ref
                    .read(selectedServerProvider.notifier)
                    .selectServer(server);
                Navigator.pop(context);
              },
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.settings),
            title: const Text('Manage servers…'),
            onTap: () => _openServersScreen(context),
          ),
        ],
      ],
    );
  }

  void _openServersScreen(BuildContext context) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ServersScreen()),
    );
  }
}