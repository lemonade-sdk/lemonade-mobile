import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_nexus_sdk/lemonade_nexus_sdk.dart'
    show Invite, inviteFormatError, normalizeInvite;

import '../../providers/app_mode_provider.dart';
import '../../providers/mesh_provider.dart';
import '../../providers/nav_provider.dart';
import '../../services/mesh_service.dart';
import '../../themes/nexus_tokens.dart';
import '../../widgets/nexus/mesh_panel.dart';
import '../../widgets/nexus/nexus_form.dart';
import 'sheet_scaffold.dart';

enum _Step { choose, create, join, invite }

/// Shown when Mesh is picked on a device without a mesh account: create a new
/// mesh (then invite a computer running Lemonade) or join one with an invite
/// code from Lemonade. Switches to Mesh mode once the device is in.
class MeshSetupSheet extends ConsumerStatefulWidget {
  const MeshSetupSheet({super.key});

  @override
  ConsumerState<MeshSetupSheet> createState() => _MeshSetupSheetState();
}

class _MeshSetupSheetState extends ConsumerState<MeshSetupSheet> {
  var _step = _Step.choose;
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  Invite? _invite;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_name.text.isEmpty) _name.text = meshDefaultDeviceName(context);
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  void _close() => ref.read(overlayProvider.notifier).close();

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name for this device.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final mesh = ref.read(meshProvider.notifier);
      await mesh.create(_name.text);
      await ref.read(appModeProvider.notifier).setMode(AppMode.mesh);
      // The mesh is useful once a computer running Lemonade joins it.
      try {
        _invite = await mesh.createInvite();
      } catch (_) {
        _invite = null;
      }
      if (mounted) setState(() => _step = _Step.invite);
    } catch (e) {
      if (mounted) setState(() => _error = MeshException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final code = normalizeInvite(_code.text);
    final malformed = inviteFormatError(code);
    if (malformed != null) {
      setState(() => _error = malformed);
      return;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name for this device.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(meshProvider.notifier).join(code, _name.text);
      await ref.read(appModeProvider.notifier).setMode(AppMode.mesh);
      _close();
    } catch (e) {
      if (mounted) setState(() => _error = MeshException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return SheetScaffold(
      onClose: _busy ? () {} : _close,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (_step == _Step.create || _step == _Step.join)
              GestureDetector(
                onTap: _busy
                    ? null
                    : () => setState(() {
                          _step = _Step.choose;
                          _error = null;
                        }),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.arrow_back, size: 20, color: t.muted),
                ),
              ),
            Text(switch (_step) {
              _Step.choose => 'Set up Mesh',
              _Step.create => 'Create a mesh',
              _Step.join => 'Join a mesh',
              _Step.invite => 'Add your computer',
            },
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.text)),
          ]),
          const SizedBox(height: 6),
          ..._body(context),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(fontSize: 12.5, height: 1.4, color: t.danger)),
          ],
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    final t = context.nexus;
    switch (_step) {
      case _Step.choose:
        return [
          Text(
              'Use the models on your own computers from anywhere, over an '
              'encrypted WireGuard mesh. No port forwarding, no cloud.',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: t.muted)),
          const SizedBox(height: 16),
          _option(
            context,
            icon: Icons.add_circle_outline,
            title: 'Create mesh',
            desc: 'Start a new mesh with this device, then add your computers '
                'with an invite code.',
            onTap: () => setState(() => _step = _Step.create),
          ),
          _option(
            context,
            icon: Icons.login,
            title: 'Join mesh',
            desc: 'Your computer already has a mesh: enter an invite code from '
                'Lemonade (Settings → Devices & mesh → Invite).',
            onTap: () => setState(() => _step = _Step.join),
          ),
        ];
      case _Step.create:
        return [
          Text('This device creates the mesh and is its owner.',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: t.muted)),
          const SizedBox(height: 16),
          NexusField(label: 'Device name', controller: _name, hint: 'iPhone'),
          NexusButton(label: 'Create mesh', busy: _busy, onTap: _create),
        ];
      case _Step.join:
        return [
          Text(
              'On the computer running Lemonade, open Settings → Devices & mesh '
              '→ Invite, and enter the code it shows.',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: t.muted)),
          const SizedBox(height: 16),
          NexusField(
              label: 'Invite code',
              controller: _code,
              hint: '1234 5678',
              keyboard: TextInputType.visiblePassword),
          NexusField(label: 'Device name', controller: _name, hint: 'iPhone'),
          NexusButton(label: 'Join mesh', busy: _busy, onTap: _join),
        ];
      case _Step.invite:
        final invite = _invite;
        return [
          if (invite != null)
            MeshInviteCode(invite: invite)
          else
            Text(
                'Your mesh is ready. Invite a computer from Settings → Mesh '
                'network → Invite a device.',
                style: TextStyle(fontSize: 13, height: 1.45, color: t.muted)),
          const SizedBox(height: 14),
          NexusButton(label: 'Done', onTap: _close),
        ];
    }
  }

  Widget _option(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    final t = context.nexus;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        margin: const EdgeInsets.only(bottom: 11),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.line2, width: 1.5),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration:
                BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: t.accent2, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
              const SizedBox(height: 5),
              Text(desc, style: TextStyle(fontSize: 12, height: 1.45, color: t.muted)),
            ]),
          ),
          Icon(Icons.chevron_right, color: t.faint),
        ]),
      ),
    );
  }
}
