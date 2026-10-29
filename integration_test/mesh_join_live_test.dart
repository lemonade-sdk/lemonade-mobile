// Live check of "Join mesh" against the production Lemonade Nexus network.
// It WRITES to the network: one throwaway device creates a mesh and mints an
// invite, a second throwaway device joins with it, then both leave. Runs only
// when asked for:
//
//   flutter test integration_test/mesh_join_live_test.dart -d <device> \
//     --dart-define=MESH_LIVE=true [--dart-define=MESH_PORT=13316]

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lemonade_mobile/services/mesh_service.dart';

const _live = bool.fromEnvironment('MESH_LIVE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('join a mesh with an invite', (tester) async {
    if (!_live) {
      markTestSkipped('Set --dart-define=MESH_LIVE=true to run against the network');
      return;
    }
    final inviter = await MeshService.start();
    final joiner = await MeshService.start();
    try {
      final home = await inviter.connect(MeshAccount.create('join-test inviter'));
      final invite = await inviter.createInvite();
      // The 8-digit code when the network issues one, as a person types it.
      final code = (invite['code'] ?? invite['link_token']) as String;
      // ignore: avoid_print
      print('[live] inviter node=${home.nodeId} invite=$code');
      // One mesh port per device: the inviter's must close before the
      // joiner starts its own on the same loopback port.
      await inviter.stop();
      // A new invite reaches the other servers through consensus; give it
      // the time a person takes to type the code. The SDK also asks another
      // server, at most three times, when the first does not hold it yet;
      // every refusal counts as a wrong code against this address (5 per 10
      // minutes per server), so this test must not lean on that.
      await Future<void>.delayed(const Duration(seconds: 15));

      final joined =
          await joiner.connect(MeshAccount.create('join-test joiner'), inviteCode: code);
      // ignore: avoid_print
      print('[live] joined node=${joined.nodeId} tunnel=${joined.tunnelIp} '
          'name=${joined.deviceName}');
      expect(joined.nodeId, isNotEmpty);
      expect(await joiner.isUp(), isTrue);
    } catch (e) {
      // ignore: avoid_print
      print('[live] FAILED: $e');
      rethrow;
    } finally {
      for (final s in [joiner, inviter]) {
        try {
          await s.leave();
        } catch (_) {}
        await s.close();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
