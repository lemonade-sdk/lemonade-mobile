import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:lemonade_nexus_sdk/dns_discovery.dart';
import 'package:lemonade_nexus_sdk/lemonade_nexus_sdk.dart';

import '../storage/secure_storage.dart';
import '../utils/server_identity.dart';

/// The Lemonade Nexus network that Mesh mode joins.
const String kMeshDomain = 'lemonade-nexus.io';
const int kMeshServerPort = 9100;

/// lemond accepts invites of at most 600 seconds; use the same lifetime.
const int kMeshInviteTtlSec = 600;

/// This device's mesh account, kept in the Keychain / Keystore.
///
/// [seed] is the Ed25519 identity of this device: whoever holds it is this
/// device on the mesh. [genesisKey] is the network key pinned on first connect
/// (trust on first use, see [MeshService.connect]); [tier1Epoch] is the
/// highest verified Tier 1 epoch, so a later run refuses an older one.
class MeshAccount {
  final String seed;
  final String deviceName;
  final String? genesisKey;
  final int tier1Epoch;
  final String? nodeId;

  /// "auto", or the node ID of the device that serves every request.
  final String selection;

  /// API key per device (node ID) for a lemond that requires one.
  final Map<String, String> peerKeys;

  const MeshAccount({
    required this.seed,
    required this.deviceName,
    this.genesisKey,
    this.tier1Epoch = 0,
    this.nodeId,
    this.selection = 'auto',
    this.peerKeys = const {},
  });

  /// A new device identity from 32 random bytes.
  factory MeshAccount.create(String deviceName) {
    final random = Random.secure();
    final seed = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
    return MeshAccount(seed: base64Encode(seed), deviceName: deviceName);
  }

  MeshAccount copyWith({
    String? deviceName,
    String? genesisKey,
    int? tier1Epoch,
    String? nodeId,
    String? selection,
    Map<String, String>? peerKeys,
  }) =>
      MeshAccount(
        seed: seed,
        deviceName: deviceName ?? this.deviceName,
        genesisKey: genesisKey ?? this.genesisKey,
        tier1Epoch: tier1Epoch ?? this.tier1Epoch,
        nodeId: nodeId ?? this.nodeId,
        selection: selection ?? this.selection,
        peerKeys: peerKeys ?? this.peerKeys,
      );

  Map<String, dynamic> toJson() => {
        'seed': seed,
        'device_name': deviceName,
        'genesis_key': genesisKey,
        'tier1_epoch': tier1Epoch,
        'node_id': nodeId,
        'selection': selection,
        'peer_keys': peerKeys,
      };

  factory MeshAccount.fromJson(Map<String, dynamic> json) => MeshAccount(
        seed: json['seed'] as String,
        deviceName: json['device_name'] as String? ?? 'Phone',
        genesisKey: json['genesis_key'] as String?,
        tier1Epoch: (json['tier1_epoch'] as num?)?.toInt() ?? 0,
        nodeId: json['node_id'] as String?,
        selection: json['selection'] as String? ?? 'auto',
        peerKeys: Map<String, String>.from(json['peer_keys'] as Map? ?? const {}),
      );

  static Future<MeshAccount?> load() async {
    final raw = await SecureKeyStore.readMeshAccount();
    if (raw == null || raw.isEmpty) return null;
    try {
      return MeshAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save() => SecureKeyStore.writeMeshAccount(jsonEncode(toJson()));

  static Future<void> delete() => SecureKeyStore.deleteMeshAccount();
}

/// What [MeshService.connect] learned from the network.
class MeshSession {
  final String nodeId;
  final String tunnelIp;
  final String genesisKey;
  final int tier1Epoch;

  /// The name the network shows for this device: the account's name, or a
  /// free variant ("iphone-2") when another device of the group has it.
  final String? deviceName;
  const MeshSession({
    required this.nodeId,
    required this.tunnelIp,
    required this.genesisKey,
    required this.tier1Epoch,
    this.deviceName,
  });
}

/// Runs the Lemonade Nexus SDK for Mesh mode on a [NexusWorker].
///
/// The phone joins as a Tier 4 client device. The SDK serves the group's
/// inference devices on the loopback mesh port (127.0.0.1:[kMeshPortNumber]),
/// which the app then uses like any local Lemonade server: "auto" routes each
/// request by its model to the device that has it, a node ID sends everything
/// to that device. Mirrors lemond's session in lemonade's nexus_manager.cpp.
class MeshService {
  MeshService._(this._worker);
  final NexusWorker _worker;

  static Future<MeshService> start() async =>
      MeshService._(await NexusWorker.spawn());

  /// Connects this device: finds the network's servers through DNS, pins the
  /// network key on first connect, signs in with the device identity, joins
  /// (or rejoins) the network, and starts the mesh and the mesh port.
  ///
  /// With [inviteCode] a new device joins the inviter's group. Without it the
  /// identity's own group is used, which the first connect creates — that is
  /// "Create mesh", and every later reconnect.
  Future<MeshSession> connect(MeshAccount account, {String? inviteCode}) async {
    final servers = await _discoverServers();
    if (servers.isEmpty) {
      throw const MeshException(
          'No Lemonade Nexus servers answered. Check your internet connection.');
    }
    Object? lastError;
    // The best-scored server first; any server can redeem an invite.
    for (final host in servers.take(3)) {
      try {
        final result = await _worker.run(_bootstrapTask(
          host: host,
          discoveryHosts: servers,
          seed: account.seed,
          deviceName: account.deviceName,
          genesisKey: account.genesisKey,
          minEpoch: account.tier1Epoch,
          inviteCode: inviteCode,
        ));
        return MeshSession(
          nodeId: result['node_id'] as String,
          tunnelIp: result['tunnel_ip'] as String? ?? '',
          genesisKey: result['genesis_key'] as String,
          tier1Epoch: result['epoch'] as int,
          deviceName: result['device_name'] as String?,
        );
      } catch (e) {
        // The next server even on LnError.auth: joining reports an
        // unreachable server as an auth refusal too.
        debugPrint('Mesh connect via $host failed: $e');
        lastError = e;
      }
    }
    throw MeshException.from(lastError);
  }

  /// A single-use invite code for this device's group, valid for
  /// [kMeshInviteTtlSec] seconds. Returns {link_token, expires_at, ...}.
  Future<Map<String, dynamic>> createInvite() =>
      _guard(() => _worker.run(_inviteTask(kMeshInviteTtlSec)));

  /// Mesh port state: the selection and the Tier 3 devices it can reach.
  Future<MeshPortStatus> portStatus() => _guard(() => _worker.run(_portStatusTask));

  /// Whether the mesh is still usable: the dataplane is up (it drops when
  /// iOS suspends the app or the network changes) and the network has not
  /// dropped the session (which needs a join again).
  Future<bool> isUp() async {
    try {
      return await _worker.run(_isUpTask);
    } catch (_) {
      return false;
    }
  }

  /// Session moves the SDK made because the network server that issued the
  /// session left. A move that is not silent needs [connect] again.
  Stream<SessionMoveEvent> get sessionMoves => _worker.sessionMoves;

  /// Serve [target] ("auto" or a node ID) on the mesh port. The device's API
  /// key is not given to the SDK; the app sends it on its own requests.
  Future<void> select(String target) =>
      _guard(() => _worker.run(_selectTask(target)));

  /// Stops the mesh port and the mesh; [connect] brings them back.
  Future<void> stop() => _worker.run(_stopTask);

  /// Removes this device from the network, then stops.
  Future<void> leave() async {
    try {
      await _worker.run(_leaveTask);
    } finally {
      await stop();
    }
  }

  Future<void> close() => _worker.close();

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (e) {
      throw MeshException.from(e);
    }
  }

  /// Certificate host names of the network's servers, best first.
  static Future<List<String>> _discoverServers() async {
    // No geo-IP lookup: the region comes from the locale, so discovery sends
    // the IP address to no third party besides the DNS-over-HTTPS resolver.
    final discovery = DnsDiscoveryService(domain: kMeshDomain, geoIpLookup: false);
    try {
      final servers = await discovery.discoverServers();
      return [
        for (final s in servers)
          if ((s.connectHost ?? s.hostname) != null) (s.connectHost ?? s.hostname)!,
      ];
    } finally {
      discovery.close();
    }
  }
}

/// A mesh failure with a message for the user.
class MeshException implements Exception {
  final String message;
  const MeshException(this.message);

  factory MeshException.from(Object? error) {
    if (error is MeshException) return error;
    if (error is SdkException) {
      final detail = error.message ?? '';
      switch (error.error) {
        case LnError.auth:
          return MeshException(detail.toLowerCase().contains('token') ||
                  detail.toLowerCase().contains('invite') ||
                  detail.toLowerCase().contains('link')
              ? 'That invite code is invalid, expired or already used. Ask for a new one.'
              : 'The network refused this device: $detail');
        case LnError.connect:
          return const MeshException(
              'Could not reach the Lemonade Nexus network. Check your internet connection.');
        case LnError.portInUse:
          return const MeshException(
              'Another app is using the mesh port (127.0.0.1:$kMeshPortNumber).');
        default:
          return MeshException(detail.isEmpty ? 'Mesh error (${error.error.name})' : detail);
      }
    }
    return MeshException('$error');
  }

  @override
  String toString() => message;
}

// ── Worker tasks ───────────────────────────────────────────────────────────
// Top-level, taking only plain data: a closure built inside MeshService would
// carry the service (and its worker) and could not be sent to the isolate.

Future<Map<String, Object?>> Function(LemonadeNexusSdk) _bootstrapTask({
  required String host,
  required List<String> discoveryHosts,
  required String seed,
  required String deviceName,
  required String? genesisKey,
  required int minEpoch,
  required String? inviteCode,
}) =>
    (sdk) async {
      // A reconnect replaces the previous client: stop its mesh first.
      try {
        await sdk.disableMesh();
      } catch (_) {}
      sdk.disconnect(clearIdentity: true);
      await sdk.connectTls(host, kMeshServerPort);
      await sdk.createIdentityFromSeed(base64Decode(seed));
      await sdk.setIdentity();

      // Tree, session and private-API calls go only to Tier 1 servers
      // verified from the network key. First connect: the SDK accepts a key
      // only when at least 3 servers of the network's domain agree on it.
      var key = genesisKey;
      if (key == null) {
        final found = await sdk.discoverGenesisKey(hosts: [
          for (final h in discoveryHosts) (host: h, port: kMeshServerPort),
        ]);
        key = found['genesis_pubkey'] as String;
      } else {
        sdk.setGenesisKey(key, minEpoch: minEpoch);
      }

      if (inviteCode != null) sdk.setLinkToken(inviteCode);
      final NetworkJoinResponse joined;
      try {
        joined = await sdk.joinNetwork(username: deviceName, password: '');
      } finally {
        if (inviteCode != null) sdk.setLinkToken('');
      }
      if (!joined.success || joined.nodeId == null) {
        throw SdkException(LnError.auth,
            message: joined.error ?? 'The network did not accept this device');
      }

      await sdk.enableMesh();
      if ((await sdk.getMeshStatus()).needsRejoin) {
        throw SdkException(LnError.connect,
            message: 'The network dropped the session while connecting');
      }
      // No local service (the phone runs no lemond) and no certificate
      // directory: the port stays on plain HTTP on loopback.
      await sdk.startMeshPort(port: kMeshPortNumber);

      final shownName = await _nameDevice(sdk, joined.nodeId!, deviceName);
      var epoch = minEpoch;
      try {
        epoch = ((await sdk.tier1Membership())['epoch'] as num?)?.toInt() ?? minEpoch;
      } catch (_) {}
      return {
        'node_id': joined.nodeId,
        'tunnel_ip': joined.tunnelIp,
        'genesis_key': key,
        'epoch': epoch,
        'device_name': shownName,
      };
    };

/// Sets this device's name on the network. The network refuses a name whose
/// label another device of the group holds ("iPhone" and "iphone" are one
/// label); then the free name the network suggests is used. Returns the name
/// set, or null when none was (the device still works, unnamed).
Future<String?> _nameDevice(
    LemonadeNexusSdk sdk, String nodeId, String deviceName) async {
  try {
    await sdk.updateNode(nodeId: nodeId, updates: {'hostname': deviceName});
    return deviceName;
  } catch (e) {
    debugPrint('Mesh device name "$deviceName" refused: $e');
  }
  try {
    final group = (await sdk.getNode(nodeId)).parentId;
    final check = await sdk.checkDeviceName(deviceName, groupNodeId: group);
    final suggestion = check['suggestion'] as String?;
    if (check['available'] == true || suggestion == null || suggestion.isEmpty) {
      return null;
    }
    await sdk.updateNode(nodeId: nodeId, updates: {'hostname': suggestion});
    return suggestion;
  } catch (e) {
    debugPrint('Mesh device name fallback failed: $e');
    return null;
  }
}

Future<Map<String, dynamic>> Function(LemonadeNexusSdk) _inviteTask(int ttl) =>
    (sdk) => sdk.createLinkToken(ttlSec: ttl);

Future<MeshPortStatus> _portStatusTask(LemonadeNexusSdk sdk) => sdk.getMeshPortStatus();

Future<bool> _isUpTask(LemonadeNexusSdk sdk) async {
  if (!sdk.isMeshActive()) return false;
  try {
    return !(await sdk.getMeshStatus()).needsRejoin;
  } catch (_) {
    return true;
  }
}

Future<void> Function(LemonadeNexusSdk) _selectTask(String target) =>
    (sdk) => sdk.setMeshPortSelection(target);

Future<void> _stopTask(LemonadeNexusSdk sdk) async {
  await sdk.stopMeshPort();
  // Stop the mesh before destroying the client, as lemond does.
  try {
    await sdk.disableMesh();
  } catch (_) {}
  sdk.disconnect();
}

Future<void> _leaveTask(LemonadeNexusSdk sdk) => sdk.leaveNetwork();
