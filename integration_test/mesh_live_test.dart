// Live end-to-end check of Mesh mode against the production Lemonade Nexus
// network. It WRITES to the network: it creates a throwaway device identity
// and mesh, mints an invite, then leaves (deletes the test device). Runs only
// when asked for:
//
//   flutter test integration_test/mesh_live_test.dart -d <device> \
//     --dart-define=MESH_LIVE=true
//
// On a simulator, add --dart-define=MESH_PORT=13316 when lemond runs on the
// Mac: it holds 13306 on the loopback the simulator shares.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lemonade_mobile/services/mesh_service.dart';
import 'package:lemonade_mobile/utils/server_identity.dart';

const _live = bool.fromEnvironment('MESH_LIVE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create a mesh, invite, leave', (tester) async {
    if (!_live) {
      markTestSkipped('Set --dart-define=MESH_LIVE=true to run against the network');
      return;
    }
    final service = await MeshService.start();
    final account = MeshAccount.create('lemonade-mobile live test');
    try {
      final session = await service.connect(account);
      expect(session.nodeId, isNotEmpty);
      expect(session.genesisKey, isNotEmpty);
      // ignore: avoid_print
      print('[live] node=${session.nodeId} tunnel=${session.tunnelIp} '
          'epoch=${session.tier1Epoch} name=${session.deviceName}');

      expect(await service.isUp(), isTrue, reason: 'mesh dataplane is not up');

      await service.select('auto');
      final port = await service.portStatus();
      expect(port.running, isTrue);
      expect(port.port, kMeshPortNumber);
      expect(port.selection, 'auto');
      // ignore: avoid_print
      print('[live] mesh port: scheme=${port.scheme} devices=${port.devices.length}');

      // The app's HTTP path: a request to the loopback mesh port is answered
      // by the SDK (a new mesh has no inference device yet, so not 200).
      final reply = await http
          .get(Uri.parse('http://127.0.0.1:$kMeshPortNumber/api/v1/models'))
          .timeout(const Duration(seconds: 15));
      // ignore: avoid_print
      print('[live] GET /api/v1/models -> ${reply.statusCode} ${reply.body}');
      expect(reply.statusCode, isNot(0));

      final invite = await service.createInvite();
      final code = invite['link_token'] as String?;
      // ignore: avoid_print
      print('[live] invite: $code expires ${invite['expires_at']}');
      expect(code, isNotNull);
      expect(code, isNotEmpty);
    } catch (e) {
      // ignore: avoid_print
      print('[live] FAILED: $e');
      rethrow;
    } finally {
      // Best effort, so a cleanup error cannot hide the failure above.
      try {
        await service.leave();
        // ignore: avoid_print
        print('[live] left the network');
      } catch (e) {
        // ignore: avoid_print
        print('[live] leave: $e');
      }
      await service.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
