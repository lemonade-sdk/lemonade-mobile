import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/device_stats_provider.dart';
import '../../providers/servers_provider.dart';
import '../../themes/nexus_tokens.dart';
import 'nexus_ui.dart';

/// The local inference device card (Local AI / Mesh): which machine we're
/// talking to, its host/IP and GPU, plus live GPU% / RAM% / CPU% / VRAM / NPU
/// from `/system-info` (static) + `/system-stats` (polled). Follows the active
/// (local) server.
class DeviceStatsCard extends ConsumerWidget {
  const DeviceStatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final server = ref.watch(selectedServerProvider);
    final info = ref.watch(systemInfoProvider).valueOrNull;
    final statsAsync = ref.watch(systemStatsProvider);
    final stats = statsAsync.valueOrNull;
    final reachable = stats != null;

    if (server == null) {
      return NexusCard(
        radius: 16,
        child: Row(children: [
          Icon(Icons.dns_outlined, color: t.faint, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
                'No local server selected. Add or pick one in Settings → Manage servers.',
                style: TextStyle(fontSize: 12.5, color: t.muted)),
          ),
        ]),
      );
    }

    final host = Uri.tryParse(server.baseUrl)?.host ?? server.baseUrl;
    final port = Uri.tryParse(server.baseUrl)?.port.toString() ?? '';

    final cpu = _num(stats?['cpu_percent']);
    final gpu = _num(stats?['gpu_percent']);
    final npu = _num(stats?['npu_percent']);
    final memUsed = _num(stats?['memory_gb']);
    final vram = _num(stats?['vram_gb']);
    final totalRam = _totalRamGb(info);
    final ramPct = (memUsed != null && totalRam != null && totalRam > 0)
        ? (memUsed / totalRam * 100)
        : null;

    return NexusCard(
      radius: 16,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [t.accentSoft, t.surface],
      ),
      borderColor: t.accent.withValues(alpha: 0.32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: t.surface2, borderRadius: BorderRadius.circular(11)),
              child: Icon(Icons.memory, color: t.accent2, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: t.text)),
                  Text(port.isEmpty ? host : '$host:$port',
                      style: nexusMono(fontSize: 11, color: t.muted)),
                ],
              ),
            ),
            Row(children: [
              NexusStatusDot(color: reachable ? t.good : t.danger, size: 6),
              const SizedBox(width: 5),
              Text(reachable ? 'Online' : 'Offline',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: reachable ? t.good : t.danger)),
            ]),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.developer_board, size: 14, color: t.faint),
            const SizedBox(width: 7),
            Expanded(
              child: Text(_gpuName(info),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nexusMono(fontSize: 11.5, color: t.muted)),
            ),
          ]),
          const SizedBox(height: 12),
          _bar(context, 'GPU', gpu),
          if (npu != null) _bar(context, 'NPU', npu),
          _bar(context, 'CPU', cpu),
          _bar(context, 'RAM', ramPct,
              detail: (memUsed != null && totalRam != null)
                  ? '${memUsed.toStringAsFixed(1)} / ${totalRam.toStringAsFixed(0)} GB'
                  : (memUsed != null ? '${memUsed.toStringAsFixed(1)} GB' : null)),
          if (vram != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                SizedBox(
                    width: 44,
                    child: Text('VRAM',
                        style: TextStyle(fontSize: 11, color: t.faint))),
                Text('${vram.toStringAsFixed(1)} GB',
                    style: nexusMono(fontSize: 11.5, color: t.muted)),
              ]),
            ),
        ],
      ),
    );
  }

  static double? _num(dynamic v) => v is num ? v.toDouble() : null;

  static double? _totalRamGb(Map<String, dynamic>? info) {
    final raw = info?['Physical Memory']?.toString();
    if (raw == null) return null;
    final m = RegExp(r'([\d.]+)').firstMatch(raw);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  static String _gpuName(Map<String, dynamic>? info) {
    final devices = info?['devices'];
    final names = <String>[];
    void collect(dynamic v) {
      if (v is Map) {
        final n = v['name'] ?? v['Name'];
        if (n != null) names.add('$n');
      } else if (v is List) {
        for (final e in v) collect(e);
      }
    }

    if (devices is Map) {
      devices.forEach((k, v) => collect(v));
    }
    const gpuHints = [
      'gpu', 'metal', 'radeon', 'nvidia', 'geforce', 'rtx', 'apple', 'amd',
      'intel arc', 'adreno'
    ];
    for (final n in names) {
      final l = n.toLowerCase();
      if (gpuHints.any(l.contains)) return n;
    }
    return info?['Processor']?.toString() ??
        (names.isNotEmpty ? names.first : 'Unknown device');
  }

  Widget _bar(BuildContext context, String label, double? pct, {String? detail}) {
    final t = context.nexus;
    final v = (pct ?? 0).clamp(0, 100) / 100.0;
    final color = v > 0.85 ? t.danger : (v > 0.6 ? t.warn : t.accent);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
            width: 44,
            child: Text(label, style: TextStyle(fontSize: 11, color: t.faint))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct == null ? null : v,
              minHeight: 7,
              backgroundColor: t.bg,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 9),
        SizedBox(
          width: detail != null ? 96 : 40,
          child: Text(
            detail ?? (pct == null ? '—' : '${pct.round()}%'),
            textAlign: TextAlign.right,
            style: nexusMono(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: t.text),
          ),
        ),
      ]),
    );
  }
}
