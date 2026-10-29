// On-device check of the Lemonade Nexus SDK used by Mesh mode. Read-only: it
// creates no identity on the network and joins nothing.
//
//   flutter test integration_test/mesh_sdk_test.dart -d <simulator or device>

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lemonade_nexus_sdk/dns_discovery.dart';
import 'package:lemonade_nexus_sdk/lemonade_nexus_sdk.dart';
import 'package:lemonade_mobile/services/mesh_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('loads the SDK and reaches the network', (tester) async {
    final discovery = DnsDiscoveryService(domain: kMeshDomain, geoIpLookup: false);
    final servers = await discovery.discoverServers();
    discovery.close();
    final hosts = [
      for (final s in servers)
        if ((s.connectHost ?? s.hostname) != null) (s.connectHost ?? s.hostname)!,
    ];
    expect(hosts, isNotEmpty, reason: 'DNS discovery found no servers');

    final worker = await NexusWorker.spawn();
    try {
      final result = await worker.run(_probe(hosts));
      expect(result['genesis_pubkey'], isNotEmpty);
      expect(result['health_ok'], isTrue);
    } finally {
      await worker.close();
    }
  });
}

Future<Map<String, Object?>> Function(LemonadeNexusSdk) _probe(List<String> hosts) =>
    (sdk) async {
      await sdk.connectTls(hosts.first, kMeshServerPort);
      final found = await sdk.discoverGenesisKey(
          hosts: [for (final h in hosts) (host: h, port: kMeshServerPort)]);
      final health = await sdk.health();
      return {'genesis_pubkey': found['genesis_pubkey'], 'health_ok': health.ok};
    };
