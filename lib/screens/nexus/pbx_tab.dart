import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/nexus/nexus_voice_models.dart';
import '../../widgets/inline_audio_player.dart';
import '../../providers/nav_provider.dart';
import '../../providers/nexus_gateway_provider.dart';
import '../../providers/voice_providers.dart';
import '../../themes/nexus_tokens.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/nexus/error_retry.dart';
import '../../widgets/nexus/gateway_gate.dart';
import '../../widgets/nexus/nexus_form.dart';
import '../../widgets/nexus/nexus_ui.dart';
import 'call_transcript_screen.dart';
import 'extension_editor_sheet.dart';
import 'get_number_screen.dart';

class PbxTab extends ConsumerWidget {
  const PbxTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(pbxTabProvider);
    final numbers = ref.watch(voiceNumbersProvider).valueOrNull ?? const [];
    final exts = ref.watch(voiceExtensionsProvider).valueOrNull ?? const [];
    final dash = ref.watch(voiceDashboardProvider).valueOrNull;

    return GatewayGate(
      icon: Icons.grid_view_rounded,
      feature: 'PBX',
      capability: 'pbx',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusStrip(context, numbers.length, exts.length, dash),
          const SizedBox(height: 16),
          NexusSegmented<PbxSection>(
            value: sub,
            fontSize: 11.5,
            onChanged: (v) => ref.read(pbxTabProvider.notifier).state = v,
            options: const [
              (PbxSection.numbers, 'Numbers'),
              (PbxSection.extensions, 'Ext'),
              (PbxSection.flows, 'Flows'),
              (PbxSection.voicemail, 'Voicemail'),
              (PbxSection.history, 'History'),
            ],
          ),
          const SizedBox(height: 16),
          switch (sub) {
            PbxSection.numbers => _NumbersView(),
            PbxSection.extensions => _ExtensionsView(),
            PbxSection.flows => _FlowsView(),
            PbxSection.voicemail => _VoicemailView(),
            PbxSection.history => _HistoryView(),
          },
        ],
      ),
    );
  }

  Widget _statusStrip(BuildContext context, int numCount, int extCount,
      NexusVoiceDashboard? dash) {
    final t = context.nexus;
    return NexusCard(
      radius: 15,
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: t.surface2, borderRadius: BorderRadius.circular(11)),
          child: Icon(Icons.call_outlined, color: t.accent2, size: 19),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Phone system',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: t.text)),
              Text('Nexus Voice · $numCount numbers · $extCount extensions',
                  style: TextStyle(fontSize: 11, color: t.muted)),
            ],
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(children: [
            NexusStatusDot(color: t.good, size: 6),
            const SizedBox(width: 5),
            Text('Live',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: t.good)),
          ]),
          if (dash != null && dash.minutesLimit > 0) ...[
            const SizedBox(height: 3),
            Text('${dash.minutesLeft} min left',
                style: nexusMono(fontSize: 10, color: t.faint)),
          ],
        ]),
      ]),
    );
  }
}

// ── Numbers ────────────────────────────────────────────────────────────
class _NumbersView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final async = ref.watch(voiceNumbersProvider);
    return async.when(
      loading: () => const _Loading(),
      error: (e, _) => ErrorRetry(
          error: e,
          action: 'load your numbers',
          onRetry: () => ref.invalidate(voiceNumbersProvider)),
      data: (numbers) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NexusButton(
            label: '+ Get a number',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const GetNumberScreen())),
          ),
          const SizedBox(height: 16),
          const NexusSectionLabel('DIDs · routing'),
          const SizedBox(height: 11),
          if (numbers.isEmpty)
            _EmptyBox('No numbers yet — tap "Get a number" to add one.')
          else
            for (final n in numbers) ...[
              NexusCard(
                radius: 15,
                onTap: () =>
                    ref.read(overlayProvider.notifier).openNumberRouting(n.id),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.number,
                            style: nexusMono(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: t.text)),
                        if (n.label.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(n.label,
                                style:
                                    TextStyle(fontSize: 11.5, color: t.muted)),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      NexusPill(_routeLabel(n.routeType), color: t.accent2),
                      const SizedBox(height: 4),
                      Text('→ ${_routeTarget(n)}',
                          style: TextStyle(fontSize: 11, color: t.muted)),
                    ],
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, size: 18, color: t.faint),
                    color: t.bg2,
                    onSelected: (v) {
                      if (v == 'routing') {
                        ref
                            .read(overlayProvider.notifier)
                            .openNumberRouting(n.id);
                      } else if (v == 'release') {
                        _release(context, ref, n);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'routing',
                          child: Text('Edit routing',
                              style: TextStyle(color: t.text))),
                      PopupMenuItem(
                          value: 'release',
                          child: Text('Release number',
                              style: TextStyle(color: t.danger))),
                    ],
                  ),
                ]),
              ),
              const SizedBox(height: 11),
            ],
        ],
      ),
    );
  }

  Future<void> _release(
      BuildContext context, WidgetRef ref, NexusNumber n) async {
    final t = context.nexus;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bg2,
        title: Text('Release ${n.number}?',
            style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
        content: Text(
            'This permanently releases the number. It will stop receiving calls '
            'and may not be recoverable.',
            style: TextStyle(color: t.muted, fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Keep', style: TextStyle(color: t.muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Release', style: TextStyle(color: t.danger))),
        ],
      ),
    );
    if (ok != true) return;
    final client = ref.read(nexusVoiceClientProvider);
    if (client == null) return;
    try {
      await client.cancelNumber(n.id);
      ref.invalidate(voiceNumbersProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Number released.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(friendlyError(e, action: 'release the number'))));
    }
  }

  String _routeLabel(String rt) => switch (rt) {
        'IvrFlow' => 'IVR',
        'Extension' => 'EXT',
        'RingAll' => 'RING ALL',
        'Voicemail' => 'VOICEMAIL',
        'ForwardExternal' => 'FORWARD',
        _ => rt.toUpperCase(),
      };

  String _routeTarget(NexusNumber n) {
    if (n.routeType == 'ForwardExternal' && n.forwardE164 != null) {
      return n.forwardE164!;
    }
    if (n.routeType == 'Extension' && n.extensionId != null) {
      return 'ext ${n.extensionId}';
    }
    if (n.routeType == 'IvrFlow' && n.ivrFlowId != null) {
      return 'flow ${n.ivrFlowId}';
    }
    return n.routeType;
  }
}

// ── Extensions ─────────────────────────────────────────────────────────
class _ExtensionsView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(voiceExtensionsProvider);
    return async.when(
      loading: () => const _Loading(),
      error: (e, _) => ErrorRetry(
          error: e,
          action: 'load your extensions',
          onRetry: () => ref.invalidate(voiceExtensionsProvider)),
      data: (exts) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NexusSectionLabel(
            'SIP extensions',
            trailing: _AddButton(
              onTap: () => ExtensionEditorSheet.show(context),
            ),
          ),
          const SizedBox(height: 11),
          if (exts.isEmpty)
            _EmptyBox('No extensions yet — add one.')
          else
            NexusCard(
              padding: EdgeInsets.zero,
              radius: 15,
              child: Column(
                children: [
                  for (var i = 0; i < exts.length; i++)
                    _row(context, exts[i], last: i == exts.length - 1),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, NexusExtension e, {required bool last}) {
    final t = context.nexus;
    return InkWell(
      onTap: () => ExtensionEditorSheet.show(context, existing: e),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: t.surface2, borderRadius: BorderRadius.circular(9)),
          child: Text(e.number,
              style: nexusMono(
                  fontSize: 13, fontWeight: FontWeight.w700, color: t.accent2)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: t.text)),
              Row(children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: e.enabled ? t.good : t.faint,
                        shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(e.statusLabel,
                    style: TextStyle(fontSize: 11, color: t.muted)),
              ]),
            ],
          ),
        ),
        Icon(Icons.chevron_right, size: 16, color: t.faint),
      ]),
      ),
    );
  }
}

/// Small "+ Add" pill used in section labels.
class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
            color: t.accentSoft, borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add, size: 13, color: t.accent2),
          const SizedBox(width: 4),
          Text('Add',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: t.accent2)),
        ]),
      ),
    );
  }
}

// ── Flows ──────────────────────────────────────────────────────────────
class _FlowsView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final async = ref.watch(voiceFlowsProvider);
    return async.when(
      loading: () => const _Loading(),
      error: (e, _) => ErrorRetry(
          error: e,
          action: 'load your flows',
          onRetry: () => ref.invalidate(voiceFlowsProvider)),
      data: (flows) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NexusSectionLabel(
            'IVR flows',
            trailing: GestureDetector(
              onTap: () => ref.read(overlayProvider.notifier).openFlowEditor(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                    color: t.accentSoft, borderRadius: BorderRadius.circular(9)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, size: 13, color: t.accent2),
                  const SizedBox(width: 4),
                  Text('New flow',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: t.accent2)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 11),
          if (flows.isEmpty)
            _EmptyBox('No IVR flows yet — create one.')
          else
            for (final f in flows) ...[
              NexusCard(
                radius: 15,
                onTap: () =>
                    ref.read(overlayProvider.notifier).openFlowEditor(flowId: f.id),
                child: Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: t.surface2,
                        borderRadius: BorderRadius.circular(11)),
                    child: Icon(Icons.account_tree_outlined,
                        color: t.accent2, size: 19),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: t.text)),
                        Text('tap to edit',
                            style: nexusMono(fontSize: 11, color: t.muted)),
                      ],
                    ),
                  ),
                  Row(children: [
                    Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            color: f.isPublished ? t.good : t.faint,
                            shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(f.isPublished ? 'Published' : 'Draft',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: f.isPublished ? t.good : t.faint)),
                  ]),
                ]),
              ),
              const SizedBox(height: 11),
            ],
        ],
      ),
    );
  }
}

// ── Call history (CDR) ─────────────────────────────────────────────────
class _HistoryView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final async = ref.watch(cdrProvider);
    return async.when(
      loading: () => const _Loading(),
      error: (e, _) => ErrorRetry(
          error: e,
          action: 'load your call history',
          onRetry: () => ref.invalidate(cdrProvider)),
      data: (calls) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const NexusSectionLabel('Call history'),
            const Spacer(),
            GestureDetector(
              onTap: () => ref.invalidate(cdrProvider),
              child: Icon(Icons.refresh, size: 17, color: t.muted),
            ),
          ]),
          const SizedBox(height: 11),
          if (calls.isEmpty)
            _EmptyBox('No calls yet.')
          else
            NexusCard(
              padding: EdgeInsets.zero,
              radius: 15,
              child: Column(children: [
                for (var i = 0; i < calls.length; i++)
                  _cdrRow(context, ref, calls[i], last: i == calls.length - 1),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _cdrRow(BuildContext context, WidgetRef ref, NexusCall c,
      {required bool last}) {
    final t = context.nexus;
    final failed = c.state.toLowerCase() == 'failed' ||
        (c.answeredAt == null && c.billableSeconds == 0);
    final (icon, tint) = c.direction.toLowerCase() == 'inbound'
        ? (Icons.call_received, failed ? t.danger : t.accent2)
        : c.direction.toLowerCase() == 'outbound'
            ? (Icons.call_made, failed ? t.danger : t.good)
            : (Icons.swap_horiz, t.muted);
    final peer = c.direction.toLowerCase() == 'inbound'
        ? c.fromNumber
        : c.toNumber;
    final meta = [
      if (c.startedAt != null) _when(c.startedAt!),
      if (c.billableSeconds > 0) _dur(c.billableSeconds),
      if (failed) (c.hangupCause?.isNotEmpty ?? false) ? c.hangupCause! : 'missed',
    ].join(' · ');

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CallTranscriptScreen(
              callRef: c.callRef, title: 'Call transcript'))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: t.line)),
        ),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: t.surface2, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 16, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(peer.isEmpty ? 'Unknown' : peer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nexusMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.text)),
                const SizedBox(height: 2),
                Text(meta.isEmpty ? c.state : meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: t.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (c.cost > 0)
              Text('\$${c.cost.toStringAsFixed(2)}',
                  style: nexusMono(fontSize: 11, color: t.muted)),
            const SizedBox(height: 2),
            Icon(Icons.chevron_right, size: 16, color: t.faint),
          ]),
        ]),
      ),
    );
  }

  String _dur(int seconds) {
    final m = seconds ~/ 60, s = seconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  String _when(DateTime d) {
    final l = d.toLocal();
    final now = DateTime.now();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    if (l.year == now.year && l.month == now.month && l.day == now.day) {
      return '$hh:$mm';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' //
    ];
    return '${months[l.month - 1]} ${l.day} · $hh:$mm';
  }
}

// ── Voicemail ──────────────────────────────────────────────────────────
class _VoicemailView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(voicemailProvider);
    return async.when(
      loading: () => const _Loading(),
      error: (e, _) => ErrorRetry(
          error: e,
          action: 'load your voicemail',
          onRetry: () => ref.invalidate(voicemailProvider)),
      data: (msgs) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NexusSectionLabel('Voicemail'),
          const SizedBox(height: 11),
          if (msgs.isEmpty)
            _EmptyBox('No voicemail.')
          else
            for (final m in msgs) ...[
              _VoicemailTile(m),
              const SizedBox(height: 11),
            ],
        ],
      ),
    );
  }
}

/// A voicemail message: tap play to stream + listen, read the transcript, mark
/// read on play, delete. Audio is fetched on demand and played via the shared
/// [InlineAudioPlayer] (fed a base64 data URL).
class _VoicemailTile extends ConsumerStatefulWidget {
  final NexusVoicemail m;
  const _VoicemailTile(this.m);

  @override
  ConsumerState<_VoicemailTile> createState() => _VoicemailTileState();
}

class _VoicemailTileState extends ConsumerState<_VoicemailTile> {
  String? _dataUrl;
  bool _loading = false;

  Future<void> _delete() async {
    final t = context.nexus;
    final messenger = ScaffoldMessenger.of(context);
    final m = widget.m;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bg2,
        title: Text(
            'Delete voicemail from ${m.fromNumber.isEmpty ? 'Unknown' : m.fromNumber}?',
            style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
        content: Text(
            'This permanently deletes the message and its recording.',
            style: TextStyle(color: t.muted, fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Keep', style: TextStyle(color: t.muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete', style: TextStyle(color: t.danger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final client = ref.read(nexusVoiceClientProvider);
    if (client == null) return;
    try {
      await client.deleteVoicemail(m.id);
      if (!mounted) return;
      ref.invalidate(voicemailProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(friendlyError(e, action: 'delete the voicemail'))));
    }
  }

  Future<void> _load() async {
    final client = ref.read(nexusVoiceClientProvider);
    if (client == null || _loading) return;
    setState(() => _loading = true);
    try {
      final bytes = await client.voicemailAudio(widget.m.id);
      if (mounted) {
        setState(
            () => _dataUrl = 'data:audio/wav;base64,${base64Encode(bytes)}');
      }
      // Mark read even if the tile is gone by now — the network side of the
      // action should still complete; only touch ref/state when mounted.
      if (!widget.m.isRead) {
        await client.markVoicemailRead(widget.m.id);
        if (mounted) ref.invalidate(voicemailProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e, action: 'load the audio'))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    final m = widget.m;
    return NexusCard(
      radius: 15,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: t.surface2, borderRadius: BorderRadius.circular(10)),
              child: Icon(m.isRead ? Icons.voicemail_outlined : Icons.voicemail,
                  size: 17, color: m.isRead ? t.muted : t.accent2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.fromNumber.isEmpty ? 'Unknown' : m.fromNumber,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: t.text)),
                  Text('${m.durationSeconds}s${m.isRead ? '' : ' · new'}',
                      style: nexusMono(fontSize: 11, color: t.faint)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 19, color: t.danger),
              onPressed: _delete,
            ),
          ]),
          const SizedBox(height: 10),
          // Player: a "Play" button until the audio is fetched, then the
          // inline scrubber.
          if (_dataUrl != null)
            InlineAudioPlayer(source: _dataUrl!, color: t.accent2)
          else
            GestureDetector(
              onTap: _load,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                    color: t.accentSoft, borderRadius: BorderRadius.circular(11)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.play_arrow, size: 18, color: t.accent2),
                  const SizedBox(width: 7),
                  Text(_loading ? 'Loading…' : 'Listen',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: t.accent2)),
                ]),
              ),
            ),
          if (m.transcriptText != null && m.transcriptText!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                  color: t.bg, borderRadius: BorderRadius.circular(10)),
              child: Text(m.transcriptText!,
                  style: TextStyle(fontSize: 13, height: 1.45, color: t.text)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Shared small bits ──────────────────────────────────────────────────
class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()));
}

class _EmptyBox extends StatelessWidget {
  final String msg;
  const _EmptyBox(this.msg);
  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return NexusCard(
      radius: 15,
      padding: const EdgeInsets.all(22),
      child: Center(
          child: Text(msg, style: TextStyle(fontSize: 13, color: t.muted))),
    );
  }
}
