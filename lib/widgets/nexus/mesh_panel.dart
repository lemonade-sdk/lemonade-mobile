import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_nexus_sdk/lemonade_nexus_sdk.dart'
    show Invite, MeshPortDevice, formatInviteCode;
import 'package:share_plus/share_plus.dart';

import '../../providers/app_mode_provider.dart';
import '../../providers/mesh_provider.dart';
import '../../services/mesh_service.dart';
import '../../themes/nexus_tokens.dart';
import 'mesh_device_list.dart';
import 'nexus_form.dart';
import 'nexus_ui.dart';

/// Default name of this device on the mesh, as other devices list it.
String meshDefaultDeviceName(BuildContext context) {
  final tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
  if (Platform.isIOS) return tablet ? 'iPad' : 'iPhone';
  return tablet ? 'Android tablet' : 'Android phone';
}

/// Settings → Mesh: the network, the device that serves chat, every device
/// of this identity's networks, invites, leave.
class MeshPanel extends ConsumerStatefulWidget {
  const MeshPanel({super.key});

  @override
  ConsumerState<MeshPanel> createState() => _MeshPanelState();
}

class _MeshPanelState extends ConsumerState<MeshPanel> {
  final _key = TextEditingController();
  String? _keyFor;
  bool _busy = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _select(String target) async {
    setState(() => _busy = true);
    try {
      await ref.read(meshProvider.notifier).select(target);
    } catch (e) {
      _toast(MeshException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveKey(String target) async {
    try {
      await ref.read(meshProvider.notifier).select(target, peerKey: _key.text);
      _toast(_key.text.trim().isEmpty ? 'API key removed' : 'API key saved');
    } catch (e) {
      _toast(MeshException.from(e).message);
    }
  }

  Future<void> _invite() async {
    setState(() => _busy = true);
    try {
      final invite = await ref.read(meshProvider.notifier).createInvite();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.nexus.bg2,
          title: const Text('Invite a device'),
          content: MeshInviteCode(invite: invite),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      );
    } catch (e) {
      _toast(MeshException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave mesh?'),
        content: const Text(
            'This device is removed from the mesh and its mesh identity is deleted '
            'from this phone. Your computers stay in the mesh. To come back, '
            'join again with a new invite code.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Leave', style: TextStyle(color: ctx.nexus.danger))),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(meshProvider.notifier).leave();
    await ref.read(appModeProvider.notifier).setMode(AppMode.local);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    final mesh = ref.watch(meshProvider);
    final connected = mesh.phase == MeshPhase.connected;
    final (dot, status) = switch (mesh.phase) {
      MeshPhase.connected => (
          t.good,
          mesh.searching && mesh.onlineDevices == 0
              ? 'Finding devices…'
              : '${mesh.onlineDevices} online'
        ),
      MeshPhase.connecting => (t.accent2, 'Connecting…'),
      MeshPhase.error => (t.danger, 'Offline'),
      MeshPhase.idle => (t.faint, 'Stopped'),
      MeshPhase.notSetUp => (t.faint, 'Not set up'),
    };
    final selection = mesh.selection;
    if (selection != 'auto' && _keyFor != selection) {
      _keyFor = selection;
      _key.text = mesh.account?.peerKeys[selection] ?? '';
    }

    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: t.surface2, borderRadius: BorderRadius.circular(11)),
              child: Icon(Icons.hub_outlined, color: t.accent2, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Mesh network',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
                Text(
                  [
                    mesh.account?.deviceName ?? '',
                    if (mesh.session?.tunnelIp.isNotEmpty ?? false)
                      mesh.session!.tunnelIp.split('/').first,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(fontSize: 12, color: t.muted),
                ),
              ]),
            ),
            NexusStatusDot(color: dot),
            const SizedBox(width: 6),
            Text(status, style: TextStyle(fontSize: 12, color: t.muted)),
          ]),
          if (mesh.phase == MeshPhase.error) ...[
            const SizedBox(height: 12),
            Text(mesh.error ?? 'The mesh is offline.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: t.danger)),
            const SizedBox(height: 10),
            NexusButton(
                label: 'Retry', onTap: () => ref.read(meshProvider.notifier).retry()),
          ],
          if (connected) ...[
            const SizedBox(height: 16),
            const NexusSectionLabel('Chat runs on'),
            const SizedBox(height: 8),
            _choice(
              context,
              selected: selection == 'auto',
              title: 'Auto',
              sub: 'Each model on the device that has it',
              online: true,
              onTap: _busy ? null : () => _select('auto'),
            ),
            for (final MeshPortDevice d in mesh.port.devices)
              _choice(
                context,
                selected: selection == d.nodeId,
                title: d.label,
                sub: d.isOnline ? 'Online' : 'Offline',
                online: d.isOnline,
                path: d.isOnline ? mesh.paths[d.nodeId] : null,
                onTap: _busy ? null : () => _select(d.nodeId),
              ),
            if (mesh.port.devices.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(
                    'No computers in this mesh yet. Invite a computer running Lemonade.',
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: t.muted)),
              ),
            if (selection != 'auto') ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _key,
                    obscureText: true,
                    style: TextStyle(fontSize: 13.5, color: t.text),
                    decoration: nexusInput(context, 'API key (only if that computer sets one)'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: () => _saveKey(selection), child: const Text('Save')),
              ]),
            ],
            // Null from a native SDK without the device list: only the mesh
            // port's devices above.
            if (mesh.networkDevices case final devices?) ...[
              const SizedBox(height: 16),
              MeshDeviceList(devices: devices, online: mesh.isDeviceOnline),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: NexusButton(label: 'Invite a device', busy: _busy, onTap: _invite)),
            ]),
          ],
          if (mesh.isSetUp) ...[
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: _leave,
                child: Text('Leave mesh', style: TextStyle(color: t.danger, fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _choice(
    BuildContext context, {
    required bool selected,
    required String title,
    required String sub,
    required bool online,
    MeshPath? path,
    required VoidCallback? onTap,
  }) {
    final t = context.nexus;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? t.accentSoft : t.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? t.accent : t.line2),
        ),
        child: Row(children: [
          NexusStatusDot(color: online ? t.good : t.faint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: t.text)),
              Text(sub, style: TextStyle(fontSize: 11.5, color: t.muted)),
            ]),
          ),
          // Straight to the device (LAN included), or through a relay.
          if (path != null) ...[
            NexusPill(path == MeshPath.direct ? 'P2P' : 'RELAY',
                color: path == MeshPath.direct ? t.good : t.warn, outlined: true),
            const SizedBox(width: 8),
          ],
          if (selected) Icon(Icons.check_circle, color: t.accent, size: 18),
        ]),
      ),
    );
  }
}

/// An invite code with copy / share and where to enter it.
class MeshInviteCode extends StatelessWidget {
  final Invite invite;
  const MeshInviteCode({super.key, required this.invite});

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    // The 8-digit code when the server issued one, else the full token.
    final code = invite.primary;
    final display = formatInviteCode(code);
    final short = invite.hasCode;
    final expires = invite.hasCode ? invite.codeExpiresAt : invite.expiresAt;
    final minutes = expires == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expires * 1000)
            .difference(DateTime.now())
            .inMinutes;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            'On the computer running Lemonade, open Settings → Devices & mesh → '
            'Join, and enter this code.',
            style: TextStyle(fontSize: 13, height: 1.45, color: t.muted)),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.line2),
          ),
          child: SelectableText(
            display,
            textAlign: short ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: short ? 30 : 13,
              fontWeight: FontWeight.w700,
              letterSpacing: short ? 3 : 0,
              color: t.text,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          if (minutes != null)
            Expanded(
              child: Text(
                  minutes <= 0
                      ? 'Expires in less than a minute · works once'
                      : 'Expires in $minutes min · works once',
                  style: TextStyle(fontSize: 11.5, color: t.faint)),
            )
          else
            const Spacer(),
          IconButton(
            tooltip: 'Copy',
            icon: Icon(Icons.copy, size: 18, color: t.accent2),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.maybeOf(context)
                  ?.showSnackBar(const SnackBar(content: Text('Invite code copied')));
            },
          ),
          IconButton(
            tooltip: 'Share',
            icon: Icon(Icons.ios_share, size: 18, color: t.accent2),
            onPressed: () => Share.share('Lemonade mesh invite code: $code'),
          ),
        ]),
        // A Lemonade that predates invite codes takes only the full token.
        if (invite.hasCode)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: invite.linkToken));
                ScaffoldMessenger.maybeOf(context)
                    ?.showSnackBar(const SnackBar(content: Text('Full invite token copied')));
              },
              child: Text('Copy full token instead',
                  style: TextStyle(fontSize: 12, color: t.accent2)),
            ),
          ),
      ],
    );
  }
}
