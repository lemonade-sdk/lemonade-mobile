import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lemonade_client_provider.dart';

/// Static hardware enumeration for the active server (`/system-info`). Null when
/// no server / unreachable.
final systemInfoProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final client = ref.watch(lemonadeClientProvider);
  if (client == null) return null;
  try {
    return await client.admin.systemInfo();
  } catch (_) {
    return null;
  }
});

/// Live device utilization for the active server (`/system-stats`), polled every
/// 2s: cpu_percent / gpu_percent / npu_percent / memory_gb / vram_gb. Re-subscribes
/// when the selected server changes.
final systemStatsProvider =
    StreamProvider.autoDispose<Map<String, dynamic>?>((ref) async* {
  final client = ref.watch(lemonadeClientProvider);
  if (client == null) {
    yield null;
    return;
  }
  while (true) {
    try {
      yield await client.admin.systemStats();
    } catch (_) {
      yield null;
    }
    await Future.delayed(const Duration(seconds: 2));
  }
});
