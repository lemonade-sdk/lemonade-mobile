import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/lemonade_client.dart';
import '../constants/colors.dart';
import '../models/discovered_server.dart';
import '../models/server_config.dart';
import '../providers/beacon_provider.dart';
import '../providers/servers_provider.dart';

/// Server management — adding, beacon discovery, and the configured-servers list.
/// Extracted out of the old monolithic Settings screen.
class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isTestingServer = false;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _apiKeyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addServer() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (name.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(name.isEmpty
            ? 'Enter a server name first.'
            : 'Enter the server\'s base URL first.'),
      ));
      return;
    }

    final server = ServerConfig(
      name: name,
      baseUrl: url,
      apiKey: apiKey.isNotEmpty ? apiKey : null,
    );
    ref.read(serversProvider.notifier).addServer(server);
    // Auto-select the first server so the app is usable right away — testers
    // didn't realize a separate "select" step existed.
    if (ref.read(selectedServerProvider) == null) {
      ref.read(selectedServerProvider.notifier).selectServer(server);
    }
    _nameController.clear();
    _urlController.clear();
    _apiKeyController.clear();
    // Drop the keyboard so the confirmation (and the new row in "Configured
    // Servers") isn't hidden behind it — testers thought the form just
    // cleared itself and nothing happened.
    FocusManager.instance.primaryFocus?.unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Server "$name" added.')),
    );
  }

  void _autofillFromDiscovered(DiscoveredServer discovered) {
    _nameController.text = discovered.hostname;
    _urlController.text = discovered.url;
    _apiKeyController.clear();
  }

  bool _isAlreadyAdded(DiscoveredServer d, List<ServerConfig> servers) =>
      servers.any((s) => s.baseUrl == d.url);

  Future<void> _testServer(ServerConfig server) async {
    if (_isTestingServer) return;
    setState(() => _isTestingServer = true);

    final client = LemonadeApiClient(server);
    const probeTimeout = Duration(seconds: 4);
    try {
      var alive = false;
      try {
        alive = await client.admin.live().timeout(probeTimeout);
      } catch (_) {
        try {
          final models =
              await client.models.installed().timeout(probeTimeout);
          alive = models.isNotEmpty;
        } catch (_) {
          alive = false;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          alive
              ? 'Server "${server.name}" is working!'
              : 'Server "${server.name}" did not respond.',
        ),
        backgroundColor:
            alive ? AppColors.serverAlive : AppColors.serverDead,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error testing "${server.name}": $e'),
        backgroundColor: AppColors.serverDead,
      ));
    } finally {
      client.close();
      if (mounted) setState(() => _isTestingServer = false);
    }
  }

  String _lastSeenText(DateTime lastSeen) {
    final diff = DateTime.now().difference(lastSeen).inSeconds;
    if (diff < 5) return 'Just now';
    if (diff < 60) return '${diff}s ago';
    if (diff < 3600) return '${(diff / 60).floor()}m ago';
    return '${(diff / 3600).floor()}h ago';
  }

  /// Manual IP switcher for a configured server. Lists every currently
  /// discovered URL whose hostname matches this server's name (case-insensitive,
  /// `.local` stripped) and lets the user pick one. We only rewrite the
  /// stored baseUrl when the user explicitly chooses — beacons never inject
  /// new IPs into a configured server on their own.
  Future<void> _switchIp(
    ServerConfig server,
    List<DiscoveredServer> discovered,
  ) async {
    final key = DiscoveredServer.normalizeHostname(server.name);
    final candidates = discovered
        .where((d) => d.hostnameKey == key && d.url != server.baseUrl)
        .toList(growable: false);

    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No other addresses are currently broadcasting for "${server.name}".',
          ),
        ),
      );
      return;
    }

    final picked = await showDialog<DiscoveredServer>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Switch IP for "${server.name}"'),
        children: [
          for (final c in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.lan_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(c.url, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;

    final updated = ServerConfig(
      name: server.name,
      baseUrl: picked.url,
      apiKey: server.apiKey,
    );
    await ref.read(serversProvider.notifier).updateServer(server, updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Switched "${server.name}" to ${picked.url}')),
    );
  }

  /// Collapse multi-NIC beacons into one row per hostname. The canonical
  /// hostname surfaced is whichever variant arrived first for that key, so
  /// `lemonade.local` doesn't suddenly switch to `lemonade` mid-session.
  List<_DiscoveredGroup> _groupByHostname(List<DiscoveredServer> discovered) {
    final byKey = <String, _DiscoveredGroup>{};
    for (final d in discovered) {
      final group = byKey.putIfAbsent(
        d.hostnameKey,
        () => _DiscoveredGroup(canonicalHostname: d.hostname, entries: []),
      );
      group.entries.add(d);
    }
    final groups = byKey.values.toList(growable: false);
    for (final g in groups) {
      g.entries.sort((a, b) => a.url.compareTo(b.url));
    }
    return groups;
  }

  Future<void> _confirmDelete(ServerConfig server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${server.name}"?'),
        content: const Text(
            'The server and its saved API key will be removed from this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove',
                  style: TextStyle(color: AppColors.serverDead))),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(serversProvider.notifier).removeServer(server);
    }
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(serversProvider);
    final selected = ref.watch(selectedServerProvider);
    final discovered = ref.watch(discoveredServersProvider);
    final beaconService = ref.watch(beaconServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Servers')),
      body: Scrollbar(
        controller: _scrollController,
        child: ListView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
          children: [
            // ====== Add server ======
            _SectionHeader(icon: Icons.add_circle_outline, title: 'Add Server'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Server name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        hintText: 'http://localhost:13305',
                        helperText: '/api/v1 is added automatically',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _apiKeyController,
                      decoration: const InputDecoration(
                        labelText: 'API key (optional)',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _addServer,
                      icon: const Icon(Icons.save),
                      label: const Text('Add server'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ====== Discovered ======
            _SectionHeader(
              icon: beaconService.isListening ? Icons.sensors : Icons.wifi_off,
              title: 'Discovered on network',
              iconColor:
                  beaconService.isListening ? AppColors.beaconActive : null,
            ),
            const SizedBox(height: 8),
            if (!beaconService.isListening)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Text(
                  'Beacon listener is not active. If a Lemonade server is running '
                  'on this same machine, the port is already taken — discovery only '
                  'works for servers on other devices.',
                  style: TextStyle(color: AppColors.hintText),
                ),
              )
            else if (discovered.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Text(
                  'Listening for Lemonade beacons…',
                  style: TextStyle(color: AppColors.hintText),
                ),
              )
            else
              Column(
                children: [
                  for (final group in _groupByHostname(discovered))
                    _DiscoveredServerCard(
                      hostname: group.canonicalHostname,
                      entries: group.entries,
                      alreadyAdded: (d) => _isAlreadyAdded(d, servers),
                      lastSeenTextOf: (d) => _lastSeenText(d.lastSeen),
                      onAutofill: _autofillFromDiscovered,
                    ),
                ],
              ),
            const SizedBox(height: 24),

            // ====== Configured ======
            _SectionHeader(
                icon: Icons.cloud_done_outlined, title: 'Configured Servers'),
            const SizedBox(height: 8),
            if (servers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'No servers added yet.',
                  style: TextStyle(color: AppColors.hintText),
                ),
              )
            else
              for (final server in servers)
                Card(
                  child: ListTile(
                    // Tap the row to make this the active server. Testers
                    // couldn't find how to select one — the row itself is now
                    // the affordance, with an explicit Active/"Tap to use"
                    // label.
                    onTap: () {
                      ref
                          .read(selectedServerProvider.notifier)
                          .selectServer(server);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Now using "${server.name}".')));
                    },
                    selected: selected?.baseUrl == server.baseUrl,
                    leading: Icon(
                      selected?.baseUrl == server.baseUrl
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: selected?.baseUrl == server.baseUrl
                          ? AppColors.serverAlive
                          : null,
                    ),
                    title: Text(server.name),
                    subtitle: Text(
                        selected?.baseUrl == server.baseUrl
                            ? '${server.baseUrl} · Active'
                            : '${server.baseUrl} · Tap to use',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.swap_horiz),
                          tooltip: 'Switch IP',
                          onPressed: () => _switchIp(server, discovered),
                        ),
                        IconButton(
                          icon: const Icon(Icons.network_check,
                              color: AppColors.serverAlive),
                          tooltip: 'Test connection',
                          onPressed: _isTestingServer
                              ? null
                              : () => _testServer(server),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: AppColors.serverDead),
                          tooltip: 'Delete',
                          onPressed: () => _confirmDelete(server),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? iconColor;
  const _SectionHeader({required this.icon, required this.title, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: iconColor ?? scheme.primary, size: 22),
        const SizedBox(width: 8),
        Text(title,
            style: Theme.of(context).textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

/// One row per hostname. A multi-NIC server announces from every interface,
/// so the same hostname can arrive with several IPs — they're consolidated
/// here and the user picks which path to use.
class _DiscoveredServerCard extends StatelessWidget {
  final String hostname;
  final List<DiscoveredServer> entries;
  final bool Function(DiscoveredServer) alreadyAdded;
  final String Function(DiscoveredServer) lastSeenTextOf;
  final void Function(DiscoveredServer) onAutofill;

  const _DiscoveredServerCard({
    required this.hostname,
    required this.entries,
    required this.alreadyAdded,
    required this.lastSeenTextOf,
    required this.onAutofill,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final mostRecent = entries
        .reduce((a, b) => a.lastSeen.isAfter(b.lastSeen) ? a : b);

    return Card(
      color: isDark
          ? AppColors.beaconCardBackgroundDark
          : AppColors.beaconCardBackgroundLight,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.sensors,
                    color: AppColors.beaconActive, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hostname,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${entries.length} address${entries.length == 1 ? '' : 'es'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Last seen: ${lastSeenTextOf(mostRecent)}',
              style: const TextStyle(
                  color: AppColors.hintText, fontSize: 11),
            ),
            const SizedBox(height: 8),
            for (final entry in entries)
              _DiscoveredEntryRow(
                entry: entry,
                alreadyAdded: alreadyAdded(entry),
                onAutofill: () => onAutofill(entry),
              ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveredEntryRow extends StatelessWidget {
  final DiscoveredServer entry;
  final bool alreadyAdded;
  final VoidCallback onAutofill;

  const _DiscoveredEntryRow({
    required this.entry,
    required this.alreadyAdded,
    required this.onAutofill,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.lan_outlined,
              size: 16, color: scheme.onSurface.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.url,
              style: const TextStyle(fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (alreadyAdded)
            const Chip(
              label: Text('Added', style: TextStyle(fontSize: 11)),
              backgroundColor: AppColors.serverAlive,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            )
          else
            TextButton.icon(
              onPressed: onAutofill,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Use'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.beaconActive,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _DiscoveredGroup {
  final String canonicalHostname;
  final List<DiscoveredServer> entries;
  _DiscoveredGroup({
    required this.canonicalHostname,
    required this.entries,
  });
}
