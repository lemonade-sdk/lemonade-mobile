import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/models/server_config.dart';
import 'package:lemonade_mobile/providers/servers_provider.dart';

class ServerSelector extends ConsumerWidget {
  const ServerSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final selectedServer = ref.watch(selectedServerProvider);

    // Auto-select first server if none selected but servers exist
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (selectedServer == null && servers.isNotEmpty) {
        ref.read(selectedServerProvider.notifier).selectServer(servers.first);
      }
    });

    if (servers.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Text(
          'No servers configured. Go to Settings to add one.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButton<ServerConfig>(
        value: selectedServer,
        hint: const Text('Select Server'),
        items: servers.map((server) {
          return DropdownMenuItem(
            value: server,
            child: Text(server.name),
          );
        }).toList(),
        onChanged: (server) {
          if (server != null) {
            ref.read(selectedServerProvider.notifier).selectServer(server);
          }
        },
        underline: Container(),
        icon: const Icon(Icons.arrow_drop_down),
      ),
    );
  }
}
