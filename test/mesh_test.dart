import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lemonade_mobile/models/server_config.dart';
import 'package:lemonade_mobile/providers/mesh_provider.dart';
import 'package:lemonade_mobile/services/mesh_service.dart';
import 'package:lemonade_mobile/utils/server_identity.dart';

void main() {
  group('normalizeInviteCode', () {
    test('joins an 8-digit code typed in groups', () {
      expect(normalizeInviteCode(' 1234 5678 '), '12345678');
      expect(normalizeInviteCode('1234-5678'), '12345678');
    });

    test('keeps a full link token as it is', () {
      expect(normalizeInviteCode('  lnk_AbC-123 '), 'lnk_AbC-123');
    });
  });

  group('MeshAccount', () {
    test('creates a 32-byte identity seed', () {
      final a = MeshAccount.create('iPhone');
      expect(base64Decode(a.seed), hasLength(32));
      expect(MeshAccount.create('iPhone').seed, isNot(a.seed));
      expect(a.selection, 'auto');
    });

    test('survives a storage round trip', () {
      final a = MeshAccount.create('Pixel').copyWith(
        genesisKey: 'W7xnOjHqav3coRGGAxo5X8DWeE9AnOZee2mlzCxt4Ic=',
        tier1Epoch: 7,
        nodeId: 'node-1',
        selection: 'node-2',
        peerKeys: {'node-2': 'secret'},
      );
      final b = MeshAccount.fromJson(
          jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(b.seed, a.seed);
      expect(b.deviceName, 'Pixel');
      expect(b.genesisKey, a.genesisKey);
      expect(b.tier1Epoch, 7);
      expect(b.nodeId, 'node-1');
      expect(b.selection, 'node-2');
      expect(b.peerKeys, {'node-2': 'secret'});
    });
  });

  test('only the loopback mesh port counts as the mesh server', () {
    expect(
        isMeshPortServer(ServerConfig(
            baseUrl: 'http://127.0.0.1:$kMeshPortNumber', name: kMeshServerName)),
        isTrue);
    // A user's own server with the same name is not the mesh port.
    expect(
        isMeshPortServer(
            ServerConfig(baseUrl: 'http://192.168.1.5:13305', name: kMeshServerName)),
        isFalse);
  });
}
