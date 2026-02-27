import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/models/server_config.dart';
import 'package:lemonade_mobile/models/discovered_server.dart';
import 'package:lemonade_mobile/providers/servers_provider.dart';
import 'package:lemonade_mobile/providers/beacon_provider.dart';
import 'package:lemonade_mobile/services/openai_service.dart';
import 'package:lemonade_mobile/constants/colors.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _isTestingServer = false;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _addServer() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (name.isEmpty || url.isEmpty) return;

    final server = ServerConfig(
      name: name,
      baseUrl: url,
      apiKey: apiKey.isNotEmpty ? apiKey : null,
    );

    ref.read(serversProvider.notifier).addServer(server);
    _clearFields();
  }

  void _clearFields() {
    _nameController.clear();
    _urlController.clear();
    _apiKeyController.clear();
  }

  void _autofillFromDiscovered(DiscoveredServer discovered) {
    _nameController.text = discovered.hostname;
    _urlController.text = discovered.url;
    _apiKeyController.clear();
  }

  bool _isAlreadyAdded(DiscoveredServer discovered, List<ServerConfig> servers) {
    return servers.any((s) => s.baseUrl == discovered.url);
  }

  Future<void> _testServer(ServerConfig server) async {
    if (_isTestingServer) return;

    setState(() => _isTestingServer = true);

    try {
      final openaiService = OpenaiService(server);
      final isAlive = await openaiService.testServer();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAlive
                  ? 'Server "${server.name}" is working!'
                  : 'Server "${server.name}" is not responding. Check your configuration.',
            ),
            backgroundColor: isAlive ? AppColors.serverAlive : AppColors.serverDead,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error testing server "${server.name}": ${e.toString()}'),
            backgroundColor: AppColors.serverDead,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingServer = false);
      }
    }
  }

  String _lastSeenText(DateTime lastSeen) {
    final diff = DateTime.now().difference(lastSeen).inSeconds;
    if (diff < 5) return 'Just now';
    if (diff < 60) return '${diff}s ago';
    return '${(diff / 60).floor()}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(serversProvider);
    final discoveredServers = ref.watch(discoveredServersProvider);
    final beaconService = ref.watch(beaconServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== ADD NEW SERVER FORM =====
            const Text(
              'Add New Server',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Server Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'http://localhost:8000',
                helperText: 'Do not include /v1 - added automatically',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key (Optional)',
                hintText: 'Leave empty to use default authentication',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _addServer,
              child: const Text('Add Server'),
            ),

            // ===== DISCOVERED SERVERS (BEACON) =====
            const SizedBox(height: 32),
            Row(
              children: [
                const Text(
                  'Discovered Servers',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                if (beaconService.isListening)
                  const _PulsingDot()
                else
                  const Icon(Icons.wifi_off, size: 16, color: AppColors.hintText),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              beaconService.isListening
                  ? 'Listening for Lemonade servers on the network...'
                  : 'Beacon listener is not active',
              style: const TextStyle(
                color: AppColors.hintText,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            if (discoveredServers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'No servers detected yet',
                    style: TextStyle(color: AppColors.hintText),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: discoveredServers.length,
                itemBuilder: (context, index) {
                  final discovered = discoveredServers[index];
                  final alreadyAdded = _isAlreadyAdded(discovered, servers);

                  return Card(
                    color: AppColors.beaconCardBackground,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.sensors,
                            color: AppColors.beaconActive,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  discovered.hostname,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  discovered.url,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Last seen: ${_lastSeenText(discovered.lastSeen)}',
                                  style: const TextStyle(
                                    color: AppColors.hintText,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (alreadyAdded)
                            const Chip(
                              label: Text(
                                'Added',
                                style: TextStyle(fontSize: 12),
                              ),
                              backgroundColor: AppColors.serverAlive,
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            )
                          else
                            ElevatedButton.icon(
                              onPressed: () =>
                                  _autofillFromDiscovered(discovered),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add Server'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.beaconActive,
                                foregroundColor: AppColors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),

            // ===== CONFIGURED SERVERS =====
            const SizedBox(height: 32),
            const Text(
              'Configured Servers',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (servers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'No servers configured',
                    style: TextStyle(color: AppColors.hintText),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: servers.length,
                itemBuilder: (context, index) {
                  final server = servers[index];
                  return Card(
                    child: ListTile(
                      title: Text(server.name),
                      subtitle: Text(server.baseUrl),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check_circle_outline),
                            tooltip: 'Test Server',
                            onPressed: () => _testServer(server),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => ref
                                .read(serversProvider.notifier)
                                .removeServer(server),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// A small pulsing green dot to indicate the beacon listener is active.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: AppColors.beaconActive,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
