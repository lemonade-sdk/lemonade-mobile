import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemonade_mobile/api/exceptions.dart';
import 'package:lemonade_mobile/models/server_config.dart';
import 'package:lemonade_mobile/providers/mesh_provider.dart';
import 'package:lemonade_mobile/utils/friendly_error.dart';
import 'package:lemonade_mobile/services/mesh_service.dart';
import 'package:lemonade_mobile/themes/theme_registry.dart';
import 'package:lemonade_mobile/utils/server_identity.dart';
import 'package:lemonade_mobile/widgets/nexus/mesh_device_list.dart';
import 'package:lemonade_mobile/widgets/nexus/mesh_panel.dart';
import 'package:lemonade_nexus_sdk/lemonade_nexus_sdk.dart'
    show Invite, JoinMembership, MeshPeer, NetworkDevice, Tier1Progress;

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

    // Every peer lists its public endpoint, reached or not: without a path
    // from the SDK there is no handshake on it yet, so it is not P2P.
    test('an endpoint without a path is not peer to peer', () {
      expect(meshPathOf(peer({'endpoint': '1.2.3.4:5'})), isNull);
      expect(meshPathOf(peer({'endpoint': '1.2.3.4:5', 'path': ''})), isNull);
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

  group('meshConnectionOf', () {
    MeshPeer peer(Map<String, dynamic> extra) =>
        MeshPeer.fromJson({'node_id': 'n1', 'mesh_pubkey': 'k', ...extra});

    test('a peer with a working path shows the path', () {
      expect(meshConnectionOf(peer({'is_online': true, 'path': 'direct'})), MeshConnection.p2p);
      expect(meshConnectionOf(peer({'is_online': true, 'path': 'lan'})), MeshConnection.p2p);
      expect(meshConnectionOf(peer({'is_online': true, 'path': 'relay'})), MeshConnection.relay);
    });

    test('a working peer without a path is still connecting', () {
      expect(meshConnectionOf(peer({'is_online': true})), MeshConnection.connecting);
    });

    // After a resume the SDK has no working path to any peer until it
    // rebuilds one, while the devices never went away: they are connecting.
    test('a peer the server reports online is connecting until a path works', () {
      expect(meshConnectionOf(peer({'is_online': false, 'server_online': true})),
          MeshConnection.connecting);
    });

    test('a peer the server reports offline is offline', () {
      expect(meshConnectionOf(peer({'is_online': false, 'server_online': false})),
          MeshConnection.offline);
      expect(meshConnectionOf(peer({'is_online': false})), MeshConnection.offline);
    });

    test('the connections keep every listed peer', () {
      expect(
          meshConnectionsOf([
            peer({'node_id': 'a', 'is_online': true, 'path': 'relay'}),
            peer({'node_id': 'b', 'is_online': false}),
            peer({'node_id': '', 'is_online': true}),
          ]),
          {'a': MeshConnection.relay, 'b': MeshConnection.offline});
    });
  });

  group('network devices', () {
    const self = NetworkDevice(nodeId: 'me', deviceName: 'iPhone', isSelf: true);
    const server = NetworkDevice(
        nodeId: 's', deviceName: 'Mac', tunnelIp: '10.0.0.5/32', isInference: true, canConnect: true);
    const friend = NetworkDevice(nodeId: 'f', deviceName: 'Phone', member: true);

    test('a device pill: none for this device, connecting until the mesh lists it', () {
      expect(meshDeviceConnection(self, connections: const {}), isNull);
      expect(meshDeviceConnection(server, connections: const {}), MeshConnection.connecting);
      expect(meshDeviceConnection(server, connections: const {'s': MeshConnection.p2p}),
          MeshConnection.p2p);
      // Not a mesh peer of this device: no pill.
      expect(meshDeviceConnection(friend, connections: const {}), isNull);
      expect(meshDeviceConnection(friend, connections: const {'f': MeshConnection.relay}),
          MeshConnection.relay);
    });

    test('chat runs on every server of the device list, online or not', () {
      const state = MeshState(
        phase: MeshPhase.connected,
        networkDevices: [
          self,
          server,
          friend,
          NetworkDevice(nodeId: 's', deviceName: 'Mac', groupId: 'other', isInference: true, canConnect: true),
          NetworkDevice(nodeId: 'x', deviceName: 'Their GPU', isInference: true),
        ],
      );
      expect(state.chatDevices, [(nodeId: 's', label: 'Mac', tunnelIp: '10.0.0.5')]);
      expect(state.connectionOf('s'), MeshConnection.connecting);
      expect(state.devicesSummary, 'connecting…');
    });

    test('the summary counts the connected servers', () {
      const devices = [
        server,
        NetworkDevice(nodeId: 't', deviceName: 'Tower', isInference: true, canConnect: true),
      ];
      expect(
          const MeshState(
                  phase: MeshPhase.connected,
                  networkDevices: devices,
                  connections: {'s': MeshConnection.relay, 't': MeshConnection.connecting})
              .devicesSummary,
          '1 online');
      expect(
          const MeshState(
                  phase: MeshPhase.connected,
                  networkDevices: devices,
                  connections: {'s': MeshConnection.offline, 't': MeshConnection.offline})
              .devicesSummary,
          'devices offline');
      expect(const MeshState(phase: MeshPhase.connected, networkDevices: []).devicesSummary,
          'no devices');
    });

    test('pills for this device, a server, and a device of a joined network', () {
      expect(
          meshDeviceTags(const NetworkDevice(
              nodeId: 'me', deviceName: 'iPhone', isSelf: true, admin: true, groupRole: 'home')),
          [MeshDeviceTag.thisDevice, MeshDeviceTag.client, MeshDeviceTag.admin]);
      expect(
          meshDeviceTags(const NetworkDevice(
              nodeId: 'f', deviceName: 'Laptop', isInference: true, member: true, groupRole: 'home')),
          [MeshDeviceTag.server, MeshDeviceTag.member]);
      expect(
          meshDeviceTags(
              const NetworkDevice(nodeId: 'x', deviceName: 'Their Mac', groupRole: 'member')),
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
          body: MeshDeviceList(
              devices: devices,
              connection: (d) => d.isSelf ? null : MeshConnection.connecting),
        ),
      ));
      expect(find.text('iPhone'), findsOneWidget);
      expect(find.text('10.0.0.9'), findsOneWidget);
      expect(find.text(MeshDeviceTag.thisDevice.label), findsOneWidget);
      expect(find.text(MeshDeviceTag.member.label), findsOneWidget);
      expect(find.text(MeshConnection.connecting.label), findsOneWidget);
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

  group('meshConnectDetail', () {
    Tier1Progress progress({bool active = true, int done = 0, int total = 0}) => Tier1Progress(
        active: active, epoch: 0, target: 100, pagesDone: done, pagesTotal: total);

    test('counts the pages of a long key history', () {
      expect(meshConnectDetail(progress(done: 0, total: 4)), 'Verifying network keys 1 of 4');
      expect(meshConnectDetail(progress(done: 3, total: 4)), 'Verifying network keys 4 of 4');
      expect(meshConnectDetail(progress(done: 5, total: 4)), 'Verifying network keys 4 of 4');
    });

    test('names the step when the page count is unknown', () {
      expect(meshConnectDetail(progress()), 'Verifying network keys');
      expect(meshConnectDetail(progress(total: 1)), 'Verifying network keys');
    });

    test('says nothing when no check runs', () {
      expect(meshConnectDetail(null), isNull);
      expect(meshConnectDetail(progress(active: false, total: 4)), isNull);
    });
  });
}
