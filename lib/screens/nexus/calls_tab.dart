import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/nexus/nexus_call_tasks_models.dart';
import '../../providers/call_tasks_providers.dart';
import '../../providers/nav_provider.dart';
import 'call_transcript_screen.dart';
import 'get_number_screen.dart';
import '../../providers/nexus_gateway_provider.dart';
import '../../themes/nexus_tokens.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/nexus/gateway_gate.dart';
import '../../widgets/nexus/nexus_ui.dart';

class CallsTab extends ConsumerStatefulWidget {
  const CallsTab({super.key});

  @override
  ConsumerState<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends ConsumerState<CallsTab> {
  final _toCtrl = TextEditingController();
  final _toNameCtrl = TextEditingController();
  final _agentCtrl = TextEditingController();
  final _objCtrl = TextEditingController();
  String _systemPrompt = '';
  bool _placing = false;

  @override
  void dispose() {
    _toCtrl.dispose();
    _toNameCtrl.dispose();
    _agentCtrl.dispose();
    _objCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(NexusCallPreset p) {
    setState(() {
      if (p.objective.isNotEmpty) _objCtrl.text = p.objective;
      if (p.agentName.isNotEmpty) _agentCtrl.text = p.agentName;
      _systemPrompt = p.systemPrompt;
    });
  }

  Future<void> _placeCall() async {
    final client = ref.read(nexusCallTasksClientProvider);
    final to = _toCtrl.text.trim();
    final objective = _objCtrl.text.trim();
    if (client == null || to.isEmpty || objective.isEmpty || _placing) {
      if (to.isEmpty || objective.isEmpty) {
        _toast('Enter both a number and what the agent should do.');
      }
      return;
    }
    setState(() => _placing = true);
    try {
      // The task blocks until answered (multi-second); open the live view as
      // soon as we have the task back.
      final task = await client.createTask(
        to: to,
        toName: _toNameCtrl.text.trim(),
        agentName: _agentCtrl.text.trim(),
        systemPrompt: _systemPrompt,
        objective: objective,
      );
      if (!mounted) return;
      _toCtrl.clear();
      _toNameCtrl.clear();
      _agentCtrl.clear();
      _objCtrl.clear();
      _systemPrompt = '';
      ref.invalidate(callTasksProvider);
      ref.invalidate(activeCallTaskProvider);
      ref.read(overlayProvider.notifier).openLiveCall(task.id);
    } catch (e) {
      _toast(friendlyError(e, action: 'place the call'));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeCallTaskProvider).valueOrNull;
    final tasks = ref.watch(callTasksProvider);

    return GatewayGate(
      icon: Icons.call_outlined,
      feature: 'AI calling',
      capability: 'aiCallTasks',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (active != null) ...[
            _liveBanner(context, active),
            const SizedBox(height: 16),
          ],
          _placeCallCard(context),
          const SizedBox(height: 12),
          _getNumberRow(context),
          const SizedBox(height: 16),
          const NexusSectionLabel('Recent activity'),
          const SizedBox(height: 9),
          tasks.when(
            data: (list) => list.isEmpty
                ? _emptyRecents(context)
                : NexusCard(
                    padding: EdgeInsets.zero,
                    radius: 18,
                    child: Column(
                      children: [
                        for (var i = 0; i < list.length; i++)
                          _recentRow(context, list[i],
                              last: i == list.length - 1),
                      ],
                    ),
                  ),
            loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => _error(context, e),
          ),
        ],
      ),
    );
  }

  Widget _liveBanner(BuildContext context, NexusCallTask task) {
    final t = context.nexus;
    return NexusCard(
      radius: 18,
      onTap: () => ref.read(overlayProvider.notifier).openLiveCall(task.id),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [t.live.withValues(alpha: 0.16), t.surface],
      ),
      borderColor: t.live.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            NexusStatusDot(color: t.live, size: 8),
            const SizedBox(width: 8),
            Text('LIVE',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: t.live)),
            const Spacer(),
            Text(task.state.name, style: nexusMono(fontSize: 12, color: t.muted)),
          ]),
          const SizedBox(height: 10),
          Text(task.toNumber.isEmpty ? 'AI call' : task.toNumber,
              style: TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 3),
          Text(task.objective,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: t.muted)),
          const SizedBox(height: 8),
          Text('Tap to watch live & take over →',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: t.accent2)),
        ],
      ),
    );
  }

  Widget _getNumberRow(BuildContext context) {
    final t = context.nexus;
    return NexusCard(
      radius: 14,
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GetNumberScreen())),
      child: Row(children: [
        Icon(Icons.dialpad, size: 17, color: t.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Get a number',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: t.text)),
              Text('Search & buy a phone number',
                  style: TextStyle(fontSize: 11.5, color: t.muted)),
            ],
          ),
        ),
        Icon(Icons.chevron_right, size: 16, color: t.faint),
      ]),
    );
  }

  Widget _placeCallCard(BuildContext context) {
    final t = context.nexus;
    return NexusCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.add_call, size: 17, color: t.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Place a call — tell the agent what to do',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: t.text)),
            ),
          ]),
          _presetChips(context),
          const SizedBox(height: 11),
          TextField(
            controller: _toCtrl,
            keyboardType: TextInputType.phone,
            style: TextStyle(fontSize: 13.5, color: t.text),
            decoration: InputDecoration(
              hintText: 'Number to call — +1 415 555 0148',
              filled: true,
              fillColor: t.bg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(color: t.line2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(color: t.line2),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(children: [
            Expanded(
                child: _miniField(context, _toNameCtrl, "Who you're calling")),
            const SizedBox(width: 9),
            Expanded(child: _miniField(context, _agentCtrl, 'Agent name')),
          ]),
          const SizedBox(height: 9),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _objCtrl,
                minLines: 1,
                maxLines: 3,
                onSubmitted: (_) => _placeCall(),
                style: TextStyle(fontSize: 13.5, color: t.text),
                decoration: InputDecoration(
                  hintText: 'Objective — e.g. move my appt to Tue AM',
                  filled: true,
                  fillColor: t.bg,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: BorderSide(color: t.line2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: BorderSide(color: t.line2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            GestureDetector(
              onTap: _placeCall,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: t.accent, borderRadius: BorderRadius.circular(13)),
                child: _placing
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.call, size: 18, color: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 9),
          Text(
              'The AI dials out, runs the conversation toward your objective, and you can steer or take over anytime.',
              style: TextStyle(fontSize: 11, height: 1.4, color: t.faint)),
        ],
      ),
    );
  }

  Widget _presetChips(BuildContext context) {
    final t = context.nexus;
    final presets = ref.watch(callPresetsProvider).valueOrNull ?? const [];
    if (presets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: 30,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final p in presets)
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: GestureDetector(
                  onTap: () => _applyPreset(p),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                        color: t.accentSoft,
                        borderRadius: BorderRadius.circular(9)),
                    child: Text(p.name,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: t.accent2)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _miniField(
      BuildContext context, TextEditingController c, String hint) {
    final t = context.nexus;
    return TextField(
      controller: c,
      style: TextStyle(fontSize: 13, color: t.text),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: t.bg,
        hintStyle: TextStyle(color: t.faint, fontSize: 12.5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.line2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.line2),
        ),
      ),
    );
  }

  Widget _recentRow(BuildContext context, NexusCallTask task,
      {required bool last}) {
    final t = context.nexus;
    final (icon, color) = switch (task.state) {
      TaskState.completed => (Icons.check_circle_outline, t.good),
      TaskState.failed => (Icons.error_outline, t.danger),
      TaskState.canceled => (Icons.cancel_outlined, t.faint),
      _ => (Icons.call_made, t.accent2),
    };
    final callRef = task.callRef;
    return InkWell(
      onTap: task.isActive
          ? () => ref.read(overlayProvider.notifier).openLiveCall(task.id)
          : (callRef != null && callRef.isNotEmpty
              ? () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CallTranscriptScreen(
                      callRef: callRef,
                      title: task.toNumber.isEmpty ? 'Transcript' : task.toNumber)))
              : () => _toast('No transcript available for this call.')),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: t.line)),
        ),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: t.surface2, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.toNumber.isEmpty ? 'AI call' : task.toNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.text)),
                Text(task.outcome ?? task.objective,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: t.muted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_time(task), style: nexusMono(fontSize: 10.5, color: t.faint)),
              const SizedBox(height: 4),
              NexusPill(task.state.name, color: color),
            ],
          ),
        ]),
      ),
    );
  }

  String _time(NexusCallTask task) {
    final d = task.startedAt ?? task.createdAt;
    if (d == null) return '';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _emptyRecents(BuildContext context) {
    final t = context.nexus;
    return NexusCard(
      radius: 18,
      padding: const EdgeInsets.all(24),
      child: Center(
          child: Text('No calls yet.',
              style: TextStyle(fontSize: 13, color: t.muted))),
    );
  }

  Widget _error(BuildContext context, Object error) {
    final t = context.nexus;
    // A raw "capability_required 401" means the account has no voice plan —
    // testers saw the literal exception text here. Show the upsell instead.
    final raw = '$error';
    final needsPlan =
        raw.contains('capability_required') || raw.contains('status=401');
    if (needsPlan) {
      return NexusCard(
        radius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Calls need a phone plan',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.text)),
            const SizedBox(height: 5),
            Text(
                'Your account doesn\'t include phone automation yet. Add a '
                'plan to place AI calls.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: t.muted)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () =>
                  ref.read(overlayProvider.notifier).openSubSheet(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Text('View plans',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      );
    }
    return NexusCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(friendlyError(error, action: 'load your recent calls'),
              style: TextStyle(fontSize: 12.5, height: 1.4, color: t.danger)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              ref.invalidate(callTasksProvider);
              ref.invalidate(activeCallTaskProvider);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Text('Retry',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
