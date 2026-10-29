// Live check that Mesh mode comes back after a quick trip to the background,
// against the production Lemonade Nexus network. It WRITES to the network: a
// throwaway device creates a mesh, then leaves. Runs only when asked for:
//
//   flutter test integration_test/mesh_lifecycle_live_test.dart -d <device> \
//     --dart-define=MESH_LIVE=true [--dart-define=MESH_PORT=13316]

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lemonade_mobile/providers/mesh_provider.dart';

const _live = bool.fromEnvironment('MESH_LIVE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reconnects after leaving the app briefly', (tester) async {
    if (!_live) {
      markTestSkipped('Set --dart-define=MESH_LIVE=true to run against the network');
      return;
    }
    final container = ProviderContainer();
    final mesh = container.read(meshProvider.notifier);
    MeshPhase phase() => container.read(meshProvider).phase;
    try {
      await tester.runAsync(() => mesh.create('lifecycle test'));
      expect(phase(), MeshPhase.connected);

      // Out and straight back in, before the stop has finished.
      final binding = tester.binding;
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        binding.handleAppLifecycleStateChanged(s);
      }

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 90));
        // Let the stop run first, then wait for the reconnect.
        await Future<void>.delayed(const Duration(seconds: 3));
        while (phase() != MeshPhase.connected && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      });
      // ignore: avoid_print
      print('[live] phase after resume: ${phase()}');
      expect(phase(), MeshPhase.connected);
    } finally {
      await tester.runAsync(() async {
        try {
          await mesh.leave();
        } catch (_) {}
      });
      container.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
