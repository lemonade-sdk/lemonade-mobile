import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/lemonade_client_provider.dart';
import '../../utils/friendly_error.dart';

class AdminBackendsTab extends ConsumerStatefulWidget {
  const AdminBackendsTab({super.key});

  @override
  ConsumerState<AdminBackendsTab> createState() => _AdminBackendsTabState();
}

class _AdminBackendsTabState extends ConsumerState<AdminBackendsTab> {
  Map<String, dynamic>? _systemInfo;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(lemonadeClientProvider);
      if (client == null) return;
      _systemInfo = await client.admin.systemInfo();
    } catch (e) {
      _error = friendlyError(e, action: 'load system info');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _install(String recipe, String backend, {bool force = false}) async {
    final client = ref.read(lemonadeClientProvider);
    if (client == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Installing $recipe:$backend…')));
    try {
      await client.admin.install(recipe: recipe, backend: backend, force: force);
    } catch (e) {
      _showError(friendlyError(e, action: 'install the backend'));
    } finally {
      await _refresh();
    }
  }

  Future<void> _uninstall(String recipe, String backend) async {
    final client = ref.read(lemonadeClientProvider);
    if (client == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Uninstalling $recipe:$backend…')),
    );
    try {
      await client.admin.uninstall(recipe: recipe, backend: backend);
    } catch (e) {
      _showError(friendlyError(e, action: 'uninstall the backend'));
    } finally {
      await _refresh();
    }
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _systemInfo == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    final recipes = (_systemInfo?['recipes'] as Map?) ?? const {};
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        children: [
          for (final recipeEntry in recipes.entries)
            _RecipeCard(
              recipe: recipeEntry.key.toString(),
              info: (recipeEntry.value as Map).cast<String, dynamic>(),
              onInstall: _install,
              onUninstall: _uninstall,
            ),
        ],
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final String recipe;
  final Map<String, dynamic> info;
  final Future<void> Function(String, String, {bool force}) onInstall;
  final Future<void> Function(String, String) onUninstall;

  const _RecipeCard({
    required this.recipe,
    required this.info,
    required this.onInstall,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final backends = (info['backends'] as Map?) ?? const {};
    final defaultBackend = info['default_backend']?.toString();
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.developer_board),
                const SizedBox(width: 8),
                Text(recipe, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (defaultBackend != null)
                  Chip(label: Text('default: $defaultBackend')),
              ],
            ),
            const SizedBox(height: 8),
            for (final entry in backends.entries)
              _BackendRow(
                recipe: recipe,
                backend: entry.key.toString(),
                info: (entry.value as Map).cast<String, dynamic>(),
                onInstall: onInstall,
                onUninstall: onUninstall,
              ),
          ],
        ),
      ),
    );
  }
}

class _BackendRow extends StatelessWidget {
  final String recipe;
  final String backend;
  final Map<String, dynamic> info;
  final Future<void> Function(String, String, {bool force}) onInstall;
  final Future<void> Function(String, String) onUninstall;

  const _BackendRow({
    required this.recipe,
    required this.backend,
    required this.info,
    required this.onInstall,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final state = info['state']?.toString() ?? 'unknown';
    final message = info['message']?.toString() ?? '';
    final version = info['version']?.toString();
    final scheme = Theme.of(context).colorScheme;

    final color = switch (state) {
      'installed' => Colors.greenAccent,
      'installable' => scheme.primary,
      'update_required' => Colors.amber,
      'unsupported' => scheme.error,
      _ => scheme.outline,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$backend${version == null ? "" : "  ·  v$version"}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (message.isNotEmpty)
                  Text(message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (state == 'installed')
            TextButton(
              onPressed: () => onUninstall(recipe, backend),
              child: const Text('Uninstall'),
            )
          else if (state == 'installable' || state == 'update_required')
            ElevatedButton(
              onPressed: () => onInstall(recipe, backend),
              child: Text(state == 'update_required' ? 'Update' : 'Install'),
            )
          else if (state == 'unsupported')
            TextButton(
              onPressed: () => onInstall(recipe, backend, force: true),
              child: const Text('Force install'),
            ),
        ],
      ),
    );
  }
}
