import 'package:flutter/widgets.dart';
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

/// Consecutive failed polls tolerated before the stats flip to null
/// ("Offline"). A single dropped 2s poll used to blank the card immediately.
const _kMaxStatsFailures = 3;

/// Live device utilization for the active server (`/system-stats`), polled every
/// 2s: cpu_percent / gpu_percent / npu_percent / memory_gb / vram_gb. Re-subscribes
/// when the selected server changes. Keeps the last-good sample through
/// transient blips and skips polls while the app is backgrounded.
final systemStatsProvider =
    StreamProvider.autoDispose<Map<String, dynamic>?>((ref) async* {
  final client = ref.watch(lemonadeClientProvider);
  if (client == null) {
    yield null;
    return;
  }
  Map<String, dynamic>? lastGood;
  var failures = 0;
  while (true) {
    // Don't poll (and burn radio/battery) while the app is backgrounded;
    // polling resumes on the first tick after it returns to the foreground.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final backgrounded = lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.detached;
    if (!backgrounded) {
      try {
        lastGood = await client.admin.systemStats();
        failures = 0;
        yield lastGood;
      } catch (_) {
        failures++;
        if (failures >= _kMaxStatsFailures) {
          // Genuinely unreachable — stop showing stale gauges.
          lastGood = null;
          yield null;
        } else if (lastGood != null) {
          // Transient blip: keep the last-good sample on screen instead of
          // blanking the card for one dropped poll.
          yield lastGood;
        }
      }
    }
    await Future.delayed(const Duration(seconds: 2));
  }
});
