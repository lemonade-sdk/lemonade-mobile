import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemonade_mobile/api/exceptions.dart';
import 'package:lemonade_mobile/models/server_config.dart';
import 'package:lemonade_mobile/utils/friendly_error.dart';
import 'package:lemonade_mobile/services/mesh_service.dart';
import 'package:lemonade_mobile/themes/theme_registry.dart';
import 'package:lemonade_mobile/utils/server_identity.dart';
import 'package:lemonade_mobile/widgets/nexus/mesh_device_list.dart';
import 'package:lemonade_mobile/widgets/nexus/mesh_panel.dart';
import 'package:lemonade_nexus_sdk/lemonade_nexus_sdk.dart'
    show Invite, JoinMembership, MeshPeer, NetworkDevice;

void main() {
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

  group('MeshInviteCode', () {
    const token = 'lnk_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    Widget host(Invite invite) => MaterialApp(
          theme: ThemeRegistry.byId(ThemeRegistry.nexusDarkId).buildTheme(),
          home: Scaffold(body: MeshInviteCode(invite: invite)),
        );

    testWidgets('shows the 8-digit code first, the token on request', (tester) async {
      await tester.pumpWidget(host(Invite.fromJson({
        'link_token': token,
        'code': '12345678',
        'group_node_id': 'g',
        'code_expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600,
      })));
      expect(find.text('1234 5678'), findsOneWidget);
      expect(find.text(token), findsNothing);
      expect(find.text('Copy full token instead'), findsOneWidget);
    });

    testWidgets('shows the token from a server without codes', (tester) async {
      await tester.pumpWidget(
          host(Invite.fromJson({'link_token': token, 'group_node_id': 'g'})));
      expect(find.text(token), findsOneWidget);
      expect(find.text('Copy full token instead'), findsNothing);
    });
  });

  group('MeshRouteException', () {
    test("shows the mesh port's reason, not a generic conflict", () {
      final e = MeshRouteException.tryParse(
          409, '{"error":"That device is offline or not reachable from this device"}', '/api/v1/chat/completions');
      expect(e, isNotNull);
      expect(friendlyError(e!), 'That device is offline or not reachable from this device');
    });

    test('leaves other bodies and statuses alone', () {
      expect(MeshRouteException.tryParse(409, 'not json', '/x'), isNull);
      expect(MeshRouteException.tryParse(500, '{"error":"boom"}', '/x'), isNull);
    });
  });

  group('meshPathOf', () {
    MeshPeer peer(Map<String, dynamic> extra) =>
        MeshPeer.fromJson({'node_id': 'n1', 'mesh_pubkey': 'k', ...extra});

    test('a relay endpoint means relayed', () {
      expect(meshPathOf(peer({'endpoint': '1.2.3.4:5', 'relay_endpoint': '9.9.9.9:4000'})),
          MeshPath.relay);
    });

    test('an endpoint alone means peer to peer', () {
      expect(meshPathOf(peer({'endpoint': '1.2.3.4:5'})), MeshPath.direct);
    });

    test('no endpoint yet means unknown', () {
      expect(meshPathOf(peer({})), isNull);
    });

    test("the SDK's path wins", () {
      expect(meshPathOf(peer({'path': 'lan', 'endpoint': '10.0.0.82:51820'})), MeshPath.direct);
      expect(meshPathOf(peer({'path': 'direct'})), MeshPath.direct);
      expect(meshPathOf(peer({'path': 'relay', 'endpoint': '1.2.3.4:5'})), MeshPath.relay);
    });
  });

  group('network devices', () {
    MeshPeer peer(String id, {required bool online}) =>
        MeshPeer.fromJson({'node_id': id, 'mesh_pubkey': 'k', 'is_online': online});

    test('the peer state keeps every peer, online or not', () {
      final state = meshPeerStateOf([
        peer('a', online: true),
        peer('b', online: false),
        peer('', online: true),
      ]);
      expect(state.online, {'a': true, 'b': false});
    });

    test('online state: self follows the mesh, others their mesh peer', () {
      const self = NetworkDevice(nodeId: 'me', deviceName: 'iPhone', isSelf: true);
      const server = NetworkDevice(nodeId: 's', deviceName: 'Mac', canConnect: true);
      const friend = NetworkDevice(nodeId: 'f', deviceName: 'Phone', member: true);
      expect(meshDeviceOnline(self, peerOnline: const {}, meshUp: true), isTrue);
      expect(meshDeviceOnline(self, peerOnline: const {}, meshUp: false), isFalse);
      expect(meshDeviceOnline(server, peerOnline: const {'s': true}, meshUp: true), isTrue);
      // A device this one may connect to but no peer yet: offline.
      expect(meshDeviceOnline(server, peerOnline: const {}, meshUp: true), isFalse);
      // Not a mesh peer of this device: unknown, not offline.
      expect(meshDeviceOnline(friend, peerOnline: const {}, meshUp: true), isNull);
      expect(meshDeviceOnline(friend, peerOnline: const {'f': true}, meshUp: true), isTrue);
    });

    test('pills for this device, a server, and a device of a joined network', () {
      expect(
          meshDeviceTags(
              const NetworkDevice(
                  nodeId: 'me', deviceName: 'iPhone', isSelf: true, admin: true, groupRole: 'home'),
              online: true),
          [MeshDeviceTag.thisDevice, MeshDeviceTag.client, MeshDeviceTag.admin, MeshDeviceTag.online]);
      expect(
          meshDeviceTags(
              const NetworkDevice(
                  nodeId: 'f', deviceName: 'Laptop', isInference: true, member: true, groupRole: 'home'),
              online: false),
          [MeshDeviceTag.server, MeshDeviceTag.member, MeshDeviceTag.offline]);
      expect(
          meshDeviceTags(
              const NetworkDevice(nodeId: 'x', deviceName: 'Their Mac', groupRole: 'member'),
              online: null),
          [MeshDeviceTag.client, MeshDeviceTag.joinedNetwork]);
    });

    testWidgets('lists every device with its pills', (tester) async {
      const devices = [
        NetworkDevice(nodeId: 'me', deviceName: 'iPhone', tunnelIp: '10.0.0.2/32', isSelf: true),
        NetworkDevice(
            nodeId: 'f', deviceName: 'Laptop', tunnelIp: '10.0.0.9/32', isInference: true, member: true),
      ];
      await tester.pumpWidget(MaterialApp(
        theme: ThemeRegistry.byId(ThemeRegistry.nexusDarkId).buildTheme(),
        home: Scaffold(
          body: MeshDeviceList(devices: devices, online: (d) => d.isSelf ? true : null),
        ),
      ));
      expect(find.text('iPhone'), findsOneWidget);
      expect(find.text('10.0.0.9'), findsOneWidget);
      expect(find.text(MeshDeviceTag.thisDevice.label), findsOneWidget);
      expect(find.text(MeshDeviceTag.member.label), findsOneWidget);
      expect(find.text(MeshDeviceTag.online.label), findsOneWidget);
      expect(find.text(MeshDeviceTag.offline.label), findsNothing);
    });
  });

  group('meshJoinNotice', () {
    test('no membership: the device joined the network itself', () {
      expect(meshJoinNotice(null), isNull);
    });

    test('member or pending: a notice that names the network, not an error', () {
      for (final status in ['member', 'pending']) {
        final notice = meshJoinNotice(JoinMembership(status: status, groupId: 'g'),
            networkName: 'Home lab');
        expect(notice, isNotNull);
        expect(notice!.isError, isFalse);
        expect(notice.message, contains('Home lab'));
      }
    });

    test("refused: an error with the server's reason", () {
      final notice = meshJoinNotice(const JoinMembership(
          status: 'refused', groupId: 'g', error: 'invite already used'));
      expect(notice!.isError, isTrue);
      expect(notice.message, contains('invite already used'));
    });

    test('the session carries the notice from the join', () {
      final session = MeshSession(
        nodeId: 'n',
        tunnelIp: '',
        genesisKey: '',
        tier1Epoch: 1,
        membership: JoinMembership.fromJson(const {'status': 'refused', 'group_id': 'g'}),
      );
      expect(session.joinNotice!.isError, isTrue);
      expect(const MeshSession(nodeId: 'n', tunnelIp: '', genesisKey: '', tier1Epoch: 1).joinNotice,
          isNull);
    });
  });
}
