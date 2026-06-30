import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/nexus/nexus_voice_models.dart';
import '../../providers/nexus_gateway_provider.dart';
import '../../providers/voice_providers.dart';
import '../../themes/nexus_tokens.dart';
import '../../widgets/nexus/nexus_ui.dart';

/// Add / edit a SIP extension. On create the one-time SIP password is shown in
/// a follow-up dialog. Wired to `POST`/`PUT /voice/extensions`.
class ExtensionEditorSheet extends ConsumerStatefulWidget {
  final NexusExtension? existing;
  const ExtensionEditorSheet({super.key, this.existing});

  static Future<void> show(BuildContext context, {NexusExtension? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ExtensionEditorSheet(existing: existing),
      ),
    );
  }

  @override
  ConsumerState<ExtensionEditorSheet> createState() =>
      _ExtensionEditorSheetState();
}

class _ExtensionEditorSheetState extends ConsumerState<ExtensionEditorSheet> {
  late final TextEditingController _number;
  late final TextEditingController _name;
  late final TextEditingController _ring;
  late bool _voicemail;
  late bool _enabled;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _number = TextEditingController(text: e?.number ?? '');
    _name = TextEditingController(text: e?.displayName ?? '');
    _ring = TextEditingController(text: '${e?.ringTimeoutSeconds ?? 20}');
    _voicemail = e?.voicemailEnabled ?? true;
    _enabled = e?.enabled ?? true;
  }

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    _ring.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final client = ref.read(nexusVoiceClientProvider);
    if (client == null || _saving) return;
    setState(() => _saving = true);
    try {
      final ring = int.tryParse(_ring.text.trim());
      if (_isEdit) {
        await client.updateExtension(
          widget.existing!.id,
          displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
          ringTimeoutSeconds: ring,
          voicemailEnabled: _voicemail,
          enabled: _enabled,
        );
        ref.invalidate(voiceExtensionsProvider);
        if (mounted) Navigator.of(context).pop();
      } else {
        final created = await client.createExtension(
          number: _number.text.trim().isEmpty ? null : _number.text.trim(),
          displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
          ringTimeoutSeconds: ring,
          voicemailEnabled: _voicemail,
        );
        ref.invalidate(voiceExtensionsProvider);
        if (mounted) {
          Navigator.of(context).pop();
          _showSipPassword(created);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
        setState(() => _saving = false);
      }
    }
  }

  void _showSipPassword(NexusExtensionCreated created) {
    final t = context.nexus;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Extension created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ext ${created.extension.number} · ${created.extension.displayName}',
                style: TextStyle(color: t.muted, fontSize: 13)),
            const SizedBox(height: 12),
            Text('SIP password (shown once):',
                style: TextStyle(color: t.faint, fontSize: 12)),
            const SizedBox(height: 4),
            SelectableText(created.sipPassword,
                style: nexusMono(
                    fontSize: 14, fontWeight: FontWeight.w700, color: t.accent2)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Done', style: TextStyle(color: t.accent))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEdit ? 'Edit extension' : 'Add extension',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: t.text)),
            const SizedBox(height: 16),
            if (!_isEdit) ...[
              _label(context, 'Extension number (optional)'),
              TextField(
                controller: _number,
                keyboardType: TextInputType.number,
                style: TextStyle(color: t.text),
                decoration: const InputDecoration(hintText: 'Auto (e.g. 101)'),
              ),
              const SizedBox(height: 12),
            ],
            _label(context, 'Display name'),
            TextField(
              controller: _name,
              style: TextStyle(color: t.text),
              decoration: const InputDecoration(hintText: 'e.g. Front desk'),
            ),
            const SizedBox(height: 12),
            _label(context, 'Ring timeout (seconds)'),
            TextField(
              controller: _ring,
              keyboardType: TextInputType.number,
              style: TextStyle(color: t.text),
              decoration: const InputDecoration(hintText: '20'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _voicemail,
              onChanged: (v) => setState(() => _voicemail = v),
              title: Text('Voicemail enabled',
                  style: TextStyle(fontSize: 14, color: t.text)),
            ),
            if (_isEdit)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: Text('Enabled',
                    style: TextStyle(fontSize: 14, color: t.text)),
              ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _save,
              child: Container(
                width: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                    color: t.accent, borderRadius: BorderRadius.circular(13)),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_isEdit ? 'Save changes' : 'Create extension',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    final t = context.nexus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: t.faint)),
    );
  }
}
