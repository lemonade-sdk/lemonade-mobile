import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemonade_mobile/api/exceptions.dart';
import 'package:lemonade_mobile/models/server_config.dart';
import 'package:lemonade_mobile/utils/friendly_error.dart';
import 'package:lemonade_mobile/services/mesh_service.dart';
import 'package:lemonade_mobile/themes/theme_registry.dart';
import 'package:lemonade_mobile/utils/server_identity.dart';
import 'package:lemonade_mobile/widgets/nexus/mesh_panel.dart';
import 'package:lemonade_nexus_sdk/lemonade_nexus_sdk.dart' show Invite;

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
}
