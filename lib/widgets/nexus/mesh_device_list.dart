import 'package:flutter/material.dart';
import 'package:lemonade_nexus_sdk/lemonade_nexus_sdk.dart' show NetworkDevice;

import '../../services/mesh_service.dart';
import '../../themes/nexus_tokens.dart';
import 'nexus_ui.dart';

/// The color of a [MeshConnection] pill and status dot.
Color meshConnectionColor(BuildContext context, MeshConnection connection) {
  final t = context.nexus;
  return switch (connection) {
    MeshConnection.p2p => t.good,
    MeshConnection.relay => t.warn,
    MeshConnection.connecting => t.accent2,
    MeshConnection.offline => t.muted,
  };
}

/// A pill on a row of [MeshDeviceList].
enum MeshDeviceTag {
  thisDevice('THIS DEVICE'),

  /// A Lemonade inference server.
  server('SERVER'),
  client('CLIENT'),

  /// The device joined this network from its own network with an invite.
  member('MEMBER'),

  /// The device is in a network this identity joined with an invite.
  joinedNetwork('JOINED NETWORK'),

  /// Its identity administers the network it is listed for.
  admin('ADMIN');

  const MeshDeviceTag(this.label);
  final String label;
}

/// The pills for [device], before its connection pill.
List<MeshDeviceTag> meshDeviceTags(NetworkDevice device) => [
      if (device.isSelf) MeshDeviceTag.thisDevice,
      device.isInference ? MeshDeviceTag.server : MeshDeviceTag.client,
      if (device.member) MeshDeviceTag.member,
      if (device.groupRole == 'member') MeshDeviceTag.joinedNetwork,
      if (device.admin) MeshDeviceTag.admin,
    ];

/// Every device of this identity's networks, in the order the SDK lists
/// them: its own network first, then the networks it joined with an invite.
class MeshDeviceList extends StatelessWidget {
  final List<NetworkDevice> devices;

  /// The connection to a device; null for no connection pill (see
  /// meshDeviceConnection).
  final MeshConnection? Function(NetworkDevice device) connection;

  const MeshDeviceList({super.key, required this.devices, required this.connection});

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NexusSectionLabel('Devices'),
        const SizedBox(height: 8),
        for (final d in devices) _row(context, d, connection(d)),
        if (devices.isEmpty)
          Text('No devices listed yet.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: t.muted)),
      ],
    );
  }

  Widget _row(BuildContext context, NetworkDevice d, MeshConnection? connection) {
    final t = context.nexus;
    final name = d.deviceName.isNotEmpty ? d.deviceName : 'Unnamed device';
    return Container(
      key: ValueKey('mesh-device-${d.groupId}-${d.nodeId}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.line2),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: NexusStatusDot(
              color: d.isSelf
                  ? t.good
                  : connection == null
                      ? t.faint
                      : meshConnectionColor(context, connection),
              pulse: d.isSelf || (connection != null && connection != MeshConnection.offline)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: t.text)),
            if (d.tunnelIp.isNotEmpty)
              Text(d.tunnelIp.split('/').first,
                  style: TextStyle(fontSize: 11.5, color: t.muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final tag in meshDeviceTags(d))
                NexusPill(tag.label, color: _color(context, tag), outlined: true),
              if (connection != null)
                NexusPill(connection.label,
                    color: meshConnectionColor(context, connection), outlined: true),
            ]),
          ]),
        ),
      ]),
    );
  }

  Color _color(BuildContext context, MeshDeviceTag tag) {
    final t = context.nexus;
    return switch (tag) {
      MeshDeviceTag.thisDevice || MeshDeviceTag.admin => t.accent,
      MeshDeviceTag.server || MeshDeviceTag.joinedNetwork => t.accent2,
      MeshDeviceTag.member => t.warn,
      MeshDeviceTag.client => t.muted,
    };
  }
}
