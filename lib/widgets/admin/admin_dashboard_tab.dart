import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/lemonade_client_provider.dart';

class AdminDashboardTab extends ConsumerStatefulWidget {
  const AdminDashboardTab({super.key});

  @override
  ConsumerState<AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends ConsumerState<AdminDashboardTab> {
  Map<String, dynamic>? _health;
  Map<String, dynamic>? _stats;
  bool _live = false;
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
      if (client == null) {
        setState(() {
          _loading = false;
          _error = 'No server selected.';
        });
        return;
      }
      final results = await Future.wait([
        client.admin.health(),
        client.admin.live(),
        client.admin.stats().catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      setState(() {
        _health = results[0] as Map<String, dynamic>;
        _live = results[1] as bool;
        _stats = results[2] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) _ErrorBanner(message: _error!),
          _LivenessCard(live: _live),
          const SizedBox(height: 12),
          if (_health != null) ..._buildHealthSection(_health!),
          const SizedBox(height: 12),
          if (_stats != null && _stats!.isNotEmpty) _StatsCard(stats: _stats!),
        ],
      ),
    );
  }

  List<Widget> _buildHealthSection(Map<String, dynamic> h) {
    final loaded = (h['all_models_loaded'] as List?) ?? const [];
    final maxModels = (h['max_models'] as Map?) ?? const {};
    return [
      _SectionCard(
        title: 'Server',
        rows: [
          _Row('Status', h['status']?.toString() ?? '—'),
          _Row('Version', h['version']?.toString() ?? '—'),
          _Row('Loaded models', '${loaded.length}'),
          _Row('WebSocket port',
              h['websocket_port']?.toString() ?? '—'),
        ],
      ),
      const SizedBox(height: 12),
      _SectionCard(
        title: 'Currently loaded',
        rows: loaded.isEmpty
            ? [const _Row('—', 'None')]
            : [
                for (final m in loaded)
                  if (m is Map)
                    _Row(
                      (m['model_name'] ?? '').toString(),
                      [
                        m['type'],
                        m['device'],
                        m['recipe'],
                      ].whereType<Object>().join(' · '),
                    ),
              ],
      ),
      const SizedBox(height: 12),
      _SectionCard(
        title: 'Max loaded per type',
        rows: maxModels.isEmpty
            ? [const _Row('—', '—')]
            : [
                for (final entry in maxModels.entries)
                  _Row(entry.key.toString(), entry.value.toString()),
              ],
      ),
    ];
  }
}

class _LivenessCard extends StatelessWidget {
  final bool live;
  const _LivenessCard({required this.live});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: live ? Colors.green.withValues(alpha: 0.15) : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              live ? Icons.check_circle : Icons.error,
              color: live ? Colors.greenAccent : scheme.error,
              size: 32,
            ),
            const SizedBox(width: 12),
            Text(
              live ? 'Server is live' : 'Server is unreachable',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<_Row> rows;
  const _SectionCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final r in rows) _RowView(row: r),
          ],
        ),
      ),
    );
  }
}

class _Row {
  final String label;
  final String value;
  const _Row(this.label, this.value);
}

class _RowView extends StatelessWidget {
  final _Row row;
  const _RowView({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(row.label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            flex: 3,
            child: Text(
              row.value,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Last request stats',
      rows: [
        _Row('Time to first token (s)',
            (stats['time_to_first_token'] as num?)?.toStringAsFixed(2) ?? '—'),
        _Row('Tokens / second',
            (stats['tokens_per_second'] as num?)?.toStringAsFixed(1) ?? '—'),
        _Row('Input tokens', stats['input_tokens']?.toString() ?? '—'),
        _Row('Output tokens', stats['output_tokens']?.toString() ?? '—'),
        _Row('Prompt tokens', stats['prompt_tokens']?.toString() ?? '—'),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.warning_amber),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
