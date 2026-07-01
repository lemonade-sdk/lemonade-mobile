import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/nexus/nexus_call_takeover_socket.dart';
import '../../api/nexus/nexus_call_tasks_models.dart';
import '../../providers/account_provider.dart';
import '../../providers/call_tasks_providers.dart';
import '../../providers/nav_provider.dart';
import '../../providers/nexus_gateway_provider.dart';
import '../../services/call_takeover_audio.dart';
import '../../themes/nexus_tokens.dart';
import '../../widgets/nexus/nexus_ui.dart';

/// Live AI call — real transcript (polled), whisper steering (Override), human
/// voice takeover (audio WS), and hangup. Backed by the AI Call Tasks API.
class LiveCallOverlay extends ConsumerStatefulWidget {
  final int taskId;
  const LiveCallOverlay({super.key, required this.taskId});

  @override
  ConsumerState<LiveCallOverlay> createState() => _LiveCallOverlayState();
}

class _LiveCallOverlayState extends ConsumerState<LiveCallOverlay> {
  final _whisper = TextEditingController();
  final _scroll = ScrollController();
  CallTakeoverAudio? _takeover;
  bool _muted = false;
  bool _switching = false;

  @override
  void dispose() {
    _whisper.dispose();
    _scroll.dispose();
    _takeover?.stop();
    super.dispose();
  }

  int get _id => widget.taskId;

  Future<void> _setMode(String mode) async {
    final client = ref.read(nexusCallTasksClientProvider);
    if (client == null || _switching) return;
    setState(() => _switching = true);
    try {
      if (mode == 'takeover') {
        await client.setMode(_id, 'takeover');
        try {
          await _startTakeover();
        } catch (e) {
          // Mic failed — don't leave the caller with dead air. Revert to the
          // AI agent, same path as ending a takeover.
          await _stopTakeover();
          await client.setMode(_id, 'autonomous');
          _toast('Microphone access failed — takeover canceled. $e');
        }
      } else {
        await _stopTakeover();
        await client.setMode(_id, mode);
      }
      ref.invalidate(callTaskProvider(_id));
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _startTakeover() async {
    if (_takeover != null) return;
    final token = ref.read(authProvider).token;
    if (token == null) return;
    final socket = NexusCallTakeoverSocket(token: token, taskId: _id);
    final audio = CallTakeoverAudio(socket);
    _takeover = audio;
    try {
      await audio.start();
    } catch (_) {
      _takeover = null;
      await audio.stop();
      rethrow;
    }
  }

  Future<void> _stopTakeover() async {
    final t = _takeover;
    _takeover = null;
    await t?.stop();
  }

  Future<void> _sendWhisper() async {
    final client = ref.read(nexusCallTasksClientProvider);
    final text = _whisper.text.trim();
    if (client == null || text.isEmpty) return;
    _whisper.clear();
    try {
      await client.whisper(_id, text);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _hangup() async {
    final client = ref.read(nexusCallTasksClientProvider);
    await _stopTakeover();
    try {
      await client?.hangup(_id);
    } catch (_) {}
    if (mounted) ref.read(overlayProvider.notifier).close();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    final task = ref.watch(callTaskProvider(_id)).valueOrNull;
    final transcript = ref.watch(taskTranscriptProvider(_id)).valueOrNull;
    final mode = task?.controlMode ?? ControlMode.autonomous;

    // Auto-scroll to the newest turn — but only if the user is already pinned
    // near the bottom, so scrolling back through the transcript isn't yanked
    // away by the ~2s poll.
    final pinned = !_scroll.hasClients ||
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 120;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pinned && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });

    return Material(
      color: t.bg,
      child: SafeArea(
        child: Column(
          children: [
            _header(context, task),
            Expanded(child: _transcriptList(context, transcript)),
            _controlDeck(context, mode),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, NexusCallTask? task) {
    final t = context.nexus;
    final peer = task == null
        ? 'Connecting…'
        : (task.toNumber.isNotEmpty ? task.toNumber : 'AI call');
    final state = task?.state.name ?? '';
    final mode = task?.controlMode ?? ControlMode.autonomous;
    final (pillText, pillBg) = switch (mode) {
      ControlMode.humanTakeover => ('YOU', t.live),
      ControlMode.override => ('STEERING', t.warn),
      ControlMode.autonomous => ('AI AGENT', t.accent),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: t.bg2,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Column(
        children: [
          Row(children: [
            NexusIconButton(
                icon: Icons.keyboard_arrow_down,
                onTap: () => ref.read(overlayProvider.notifier).close()),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(peer,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: t.text)),
                  Text(state, style: nexusMono(fontSize: 12, color: t.muted)),
                ],
              ),
            ),
            NexusPill(pillText, color: Colors.white, bg: pillBg),
          ]),
          if (task != null && task.objective.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.accentSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.accent.withValues(alpha: 0.32)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.flag_outlined, size: 15, color: t.accent2),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AGENT OBJECTIVE',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: t.accent2)),
                      const SizedBox(height: 2),
                      Text(task.objective,
                          style: TextStyle(
                              fontSize: 12.5, height: 1.4, color: t.text)),
                    ],
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _transcriptList(BuildContext context, NexusTranscript? transcript) {
    final t = context.nexus;
    final turns = transcript?.turns ?? const [];
    return Scrollbar(
      controller: _scroll,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Text('LIVE TRANSCRIPT · both sides',
                style: nexusMono(fontSize: 10.5, color: t.faint)),
          ),
          const SizedBox(height: 13),
          if (turns.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Center(
                  child: Text('Waiting for the conversation…',
                      style: TextStyle(fontSize: 13, color: t.muted))),
            ),
          for (final turn in turns) _turn(context, turn),
          if (transcript?.summary != null &&
              transcript!.summary!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.line2)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SUMMARY',
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: t.accent2)),
                  const SizedBox(height: 5),
                  Text(transcript.summary!,
                      style:
                          TextStyle(fontSize: 13, height: 1.45, color: t.text)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _turn(BuildContext context, NexusTranscriptTurn turn) {
    final t = context.nexus;
    if (turn.isEvent) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(turn.content ?? '',
              textAlign: TextAlign.center,
              style: nexusMono(fontSize: 10.5, color: t.faint)),
        ),
      );
    }
    if (turn.isTool) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: t.line2)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.build_circle_outlined, size: 13, color: t.accent2),
              const SizedBox(width: 6),
              Text(turn.tool ?? 'tool',
                  style: nexusMono(
                      fontSize: 11, fontWeight: FontWeight.w600, color: t.text)),
            ]),
          ),
        ]),
      );
    }
    final agent = turn.isAgent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment:
            agent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(agent ? 'AGENT' : 'CALLER',
              style: TextStyle(
                  fontSize: 9.5, fontWeight: FontWeight.w600, color: t.faint)),
          const SizedBox(height: 3),
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: agent ? t.accent : t.surface,
              borderRadius: BorderRadius.circular(14),
              border: agent ? null : Border.all(color: t.line),
            ),
            child: Text(
              '${turn.content ?? ''}${turn.interrupted ? ' …' : ''}',
              style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: agent ? Colors.white : t.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlDeck(BuildContext context, ControlMode mode) {
    final t = context.nexus;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: t.bg2,
        border: Border(top: BorderSide(color: t.line)),
      ),
      child: Column(
        children: [
          NexusSegmented<ControlMode>(
            value: mode,
            fontSize: 11.5,
            onChanged: (m) => _setMode(switch (m) {
              ControlMode.autonomous => 'autonomous',
              ControlMode.override => 'override',
              ControlMode.humanTakeover => 'takeover',
            }),
            options: const [
              (ControlMode.autonomous, 'AI'),
              (ControlMode.override, 'Steer'),
              (ControlMode.humanTakeover, 'Take over'),
            ],
          ),
          const SizedBox(height: 12),
          if (mode == ControlMode.override) _whisperComposer(context),
          if (mode == ControlMode.humanTakeover) _takeoverBar(context),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: _hangup,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                      color: t.danger, borderRadius: BorderRadius.circular(14)),
                  child: const Text('End call',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _whisperComposer(BuildContext context) {
    final t = context.nexus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _whisper,
            onSubmitted: (_) => _sendWhisper(),
            style: TextStyle(fontSize: 14, color: t.text),
            decoration: InputDecoration(
              hintText: 'Whisper private steering to the agent…',
              filled: true,
              fillColor: t.surface,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.warn.withValues(alpha: 0.6)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.warn),
              ),
            ),
          ),
        ),
        const SizedBox(width: 9),
        GestureDetector(
          onTap: _sendWhisper,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: t.warn, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.send, color: Colors.white, size: 17),
          ),
        ),
      ]),
    );
  }

  Widget _takeoverBar(BuildContext context) {
    final t = context.nexus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(children: [
        NexusStatusDot(color: t.live, size: 8),
        const SizedBox(width: 8),
        Expanded(
          child: Text("You're live on the call",
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
        ),
        GestureDetector(
          onTap: () {
            setState(() => _muted = !_muted);
            _takeover?.setMuted(_muted);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
                color: _muted ? t.surface2 : t.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.line2)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_muted ? Icons.mic_off : Icons.mic,
                  size: 15, color: _muted ? t.danger : t.muted),
              const SizedBox(width: 5),
              Text(_muted ? 'Muted' : 'Mute',
                  style: TextStyle(fontSize: 12, color: t.muted)),
            ]),
          ),
        ),
        GestureDetector(
          onTap: () => _setMode('autonomous'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
                color: t.accent, borderRadius: BorderRadius.circular(10)),
            child: const Text('Release',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}
