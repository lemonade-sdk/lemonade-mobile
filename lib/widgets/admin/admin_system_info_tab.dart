import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/lemonade_client_provider.dart';
import '../../utils/friendly_error.dart';

class AdminSystemInfoTab extends ConsumerStatefulWidget {
  const AdminSystemInfoTab({super.key});

  @override
  ConsumerState<AdminSystemInfoTab> createState() => _AdminSystemInfoTabState();
}

class _AdminSystemInfoTabState extends ConsumerState<AdminSystemInfoTab> {
  Map<String, dynamic>? _info;
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
      _info = await client.admin.systemInfo();
    } catch (e) {
      _error = friendlyError(e, action: 'load system info');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _info == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    final info = _info ?? const <String, dynamic>{};
    final devices = (info['devices'] as Map?) ?? const {};

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            title: 'System',
            entries: {
              'OS': info['OS Version']?.toString() ?? '—',
              'Processor': info['Processor']?.toString() ?? '—',
              'RAM': info['Physical Memory']?.toString() ?? '—',
              'OEM': info['OEM System']?.toString() ?? '—',
              'BIOS': info['BIOS Version']?.toString() ?? '—',
              'Power': info['Windows Power Setting']?.toString() ?? '—',
            },
          ),
          const SizedBox(height: 12),
          for (final entry in devices.entries) ..._buildDeviceCard(entry.key.toString(), entry.value),
        ],
      ),
    );
  }

  List<Widget> _buildDeviceCard(String name, dynamic value) {
    if (value is Map) {
      return [
        _Card(
          title: name,
          entries: {
            for (final e in value.entries) e.key.toString(): e.value.toString(),
          },
        ),
        const SizedBox(height: 12),
      ];
    }
    if (value is List) {
      return [
        for (final item in value)
          if (item is Map)
            _Card(
              title: name,
              entries: {
                for (final e in item.entries) e.key.toString(): e.value.toString(),
              },
            ),
        const SizedBox(height: 12),
      ];
    }
    return const [];
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Map<String, String> entries;

  const _Card({required this.title, required this.entries});

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
            for (final e in entries.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        e.key,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        e.value,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
