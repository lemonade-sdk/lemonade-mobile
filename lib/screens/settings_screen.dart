import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/models/server_config.dart';
import 'package:lemonade_mobile/providers/servers_provider.dart';
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
                  ? '✅ Server "${server.name}" is working!'
                  : '❌ Server "${server.name}" is not responding. Check your configuration.',
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
            content: Text('❌ Error testing server "${server.name}": ${e.toString()}'),
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

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(serversProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 32),
            const Text(
              'Configured Servers',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
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
                            onPressed: () => ref.read(serversProvider.notifier).removeServer(server),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
