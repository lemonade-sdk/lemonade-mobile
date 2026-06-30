import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/nexus/nexus_voice_models.dart';
import '../../providers/nav_provider.dart';
import '../../providers/nexus_gateway_provider.dart';
import '../../providers/voice_providers.dart';
import '../../themes/nexus_tokens.dart';
import 'sheet_scaffold.dart';

/// Bottom sheet to re-route a DID. Wired to `PUT /voice/numbers/{id}/routing`.
class NumberRoutingOverlay extends ConsumerStatefulWidget {
  final int numberId;
  const NumberRoutingOverlay({super.key, required this.numberId});

  @override
  ConsumerState<NumberRoutingOverlay> createState() =>
      _NumberRoutingOverlayState();
}

class _NumberRoutingOverlayState extends ConsumerState<NumberRoutingOverlay> {
  String _routeType = 'IvrFlow';
  int? _flowId;
  int? _extensionId;
  final _forward = TextEditingController();
  bool _saving = false;
  bool _init = false;

  static const _routeTypes = [
    ('IvrFlow', 'IVR flow'),
    ('Extension', 'Extension'),
    ('Voicemail', 'Voicemail'),
    ('ForwardExternal', 'Forward'),
  ];

  @override
  void dispose() {
    _forward.dispose();
    super.dispose();
  }

  void _seed(NexusNumber n) {
    if (_init) return;
    _init = true;
    _routeType = n.routeType.isEmpty ? 'IvrFlow' : n.routeType;
    _flowId = n.ivrFlowId;
    _extensionId = n.extensionId;
    _forward.text = n.forwardE164 ?? '';
  }

  Future<void> _save() async {
    final client = ref.read(nexusVoiceClientProvider);
    if (client == null || _saving) return;
    setState(() => _saving = true);
    try {
      await client.updateRouting(
        widget.numberId,
        routeType: _routeType,
        ivrFlowId: _routeType == 'IvrFlow' ? _flowId : null,
        extensionId: _routeType == 'Extension' ? _extensionId : null,
        forwardE164:
            _routeType == 'ForwardExternal' ? _forward.text.trim() : null,
      );
      ref.invalidate(voiceNumbersProvider);
      if (mounted) ref.read(overlayProvider.notifier).close();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    final close = ref.read(overlayProvider.notifier).close;
    final numbers = ref.watch(voiceNumbersProvider).valueOrNull ?? const [];
    final number = numbers.where((n) => n.id == widget.numberId).firstOrNull;
    if (number != null) _seed(number);

    return SheetScaffold(
      onClose: close,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Route this number',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 2),
          Text(number?.number ?? '',
              style: TextStyle(fontSize: 13, color: t.muted)),
          const SizedBox(height: 16),
          Text('ROUTE TYPE',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: t.faint)),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final (val, label) in _routeTypes)
                GestureDetector(
                  onTap: () => setState(() => _routeType = val),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: _routeType == val ? t.accent : t.surface,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                          color: _routeType == val ? t.accent : t.line2),
                    ),
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color:
                                _routeType == val ? Colors.white : t.muted)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _routeConfig(context),
          const SizedBox(height: 18),
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
                  : const Text('Save routing',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeConfig(BuildContext context) {
    final t = context.nexus;
    switch (_routeType) {
      case 'IvrFlow':
        final flows = ref.watch(voiceFlowsProvider).valueOrNull ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CHOOSE IVR FLOW',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: t.faint)),
            const SizedBox(height: 9),
            for (final f in flows)
              GestureDetector(
                onTap: () => setState(() => _flowId = f.id),
                child: Container(
                  padding: const EdgeInsets.all(13),
                  margin: const EdgeInsets.only(bottom: 9),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _flowId == f.id ? t.accent : t.line2,
                        width: 1.5),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text(f.name,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: t.text)),
                    ),
                    if (_flowId == f.id)
                      Icon(Icons.check_circle, color: t.accent, size: 18),
                  ]),
                ),
              ),
            if (flows.isEmpty)
              Text('No flows yet — create one in PBX → Flows.',
                  style: TextStyle(fontSize: 12.5, color: t.muted)),
          ],
        );
      case 'Extension':
        final exts = ref.watch(voiceExtensionsProvider).valueOrNull ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CHOOSE EXTENSION',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: t.faint)),
            const SizedBox(height: 9),
            for (final e in exts)
              GestureDetector(
                onTap: () => setState(() => _extensionId = e.id),
                child: Container(
                  padding: const EdgeInsets.all(13),
                  margin: const EdgeInsets.only(bottom: 9),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _extensionId == e.id ? t.accent : t.line2,
                        width: 1.5),
                  ),
                  child: Row(children: [
                    Expanded(
                        child: Text('${e.number} · ${e.displayName}',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: t.text))),
                    if (_extensionId == e.id)
                      Icon(Icons.check_circle, color: t.accent, size: 18),
                  ]),
                ),
              ),
          ],
        );
      case 'ForwardExternal':
        return TextField(
          controller: _forward,
          style: TextStyle(fontSize: 15, color: t.text),
          decoration: const InputDecoration(
              hintText: '+1 415 555 0123', labelText: 'Forward to number'),
        );
      default:
        return Text('Calls to this number go straight to voicemail.',
            style: TextStyle(fontSize: 13, color: t.muted));
    }
  }
}
