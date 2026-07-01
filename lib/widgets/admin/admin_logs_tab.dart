import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/realtime/logs_socket.dart';
import '../../providers/lemonade_client_provider.dart';

class AdminLogsTab extends ConsumerStatefulWidget {
  const AdminLogsTab({super.key});

  @override
  ConsumerState<AdminLogsTab> createState() => _AdminLogsTabState();
}

class _AdminLogsTabState extends ConsumerState<AdminLogsTab> {
  LogsSocket? _socket;
  StreamSubscription? _sub;
  final _entries = <LogEntry>[];
  int? _lastSeq;
  bool _connected = false;
  bool _paused = false;
  String _filter = '';
  String _severityFilter = 'All';
  String? _error;

  static const _severities = ['All', 'Info', 'Warning', 'Error', 'Debug', 'Trace'];

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    final client = ref.read(lemonadeClientProvider);
    if (client == null) return;
    try {
      final health = await client.admin.health();
      final port = (health['websocket_port'] as num?)?.toInt();
      if (port == null) {
        setState(() => _error = 'Server did not advertise a websocket port.');
        return;
      }
      final s = LogsSocket(client);
      _socket = s;
      await s.connect(port: port);
      s.subscribe(afterSeq: _lastSeq);
      _sub = s.events.listen(_handleEvent);
      if (mounted) setState(() => _connected = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _handleEvent(LogsEvent event) {
    if (_paused) return;
    setState(() {
      switch (event) {
        case LogsSnapshot():
          _entries.addAll(event.entries);
          if (event.entries.isNotEmpty) _lastSeq = event.entries.last.seq;
        case LogsLive():
          _entries.add(event.entry);
          _lastSeq = event.entry.seq;
        case LogsError():
          _error = event.message;
        case LogsDisconnected():
          _connected = false;
      }
      // Cap buffer to prevent unbounded growth.
      if (_entries.length > 5000) {
        _entries.removeRange(0, _entries.length - 5000);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  Iterable<LogEntry> _visible() {
    return _entries.where((e) {
      if (_severityFilter != 'All' &&
          e.severity.toLowerCase() != _severityFilter.toLowerCase()) {
        return false;
      }
      if (_filter.isNotEmpty &&
          !e.line.toLowerCase().contains(_filter.toLowerCase())) {
        return false;
      }
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Filter once per build — doing it per row made the list O(n²) with up to
    // 5000 buffered entries.
    final visible = _visible().toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Filter…',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _severityFilter,
                items: [
                  for (final s in _severities)
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) =>
                    setState(() => _severityFilter = v ?? 'All'),
              ),
              IconButton(
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                tooltip: _paused ? 'Resume' : 'Pause',
                onPressed: () => setState(() => _paused = !_paused),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Reconnect',
                onPressed: () async {
                  await _sub?.cancel();
                  await _socket?.close();
                  setState(() {
                    _connected = false;
                    _entries.clear();
                  });
                  await _connect();
                },
              ),
            ],
          ),
        ),
        if (_error != null)
          Container(
            color: scheme.errorContainer,
            padding: const EdgeInsets.all(8),
            child: Text('Error: $_error'),
          ),
        if (!_connected && _error == null)
          const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            reverse: true,
            itemCount: visible.length,
            itemBuilder: (context, idx) {
              final entry = visible[visible.length - 1 - idx];
              return _LogRow(entry: entry);
            },
          ),
        ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  final LogEntry entry;
  const _LogRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (entry.severity.toLowerCase()) {
      'error' || 'fatal' => scheme.error,
      'warning' => Colors.amber,
      'info' => scheme.primary,
      'debug' => scheme.outline,
      _ => scheme.onSurface.withValues(alpha: 0.6),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'Courier',
                fontSize: 12,
              ),
          children: [
            TextSpan(
              text: '${entry.timestamp} ',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
            ),
            TextSpan(
              text: '[${entry.severity}] ',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: '(${entry.tag}) ',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            TextSpan(text: entry.line),
          ],
        ),
      ),
    );
  }
}
