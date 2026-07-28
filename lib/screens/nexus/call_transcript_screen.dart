import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/nexus/nexus_call_tasks_models.dart';
import '../../providers/voice_providers.dart';
import '../../themes/nexus_tokens.dart';
import '../../widgets/nexus/error_retry.dart';
import '../../widgets/nexus/nexus_form.dart';
import '../../widgets/nexus/nexus_ui.dart';

/// Read-only transcript for a finished call (`GET /voice/calls/{ref}/transcript`).
class CallTranscriptScreen extends ConsumerWidget {
  final String callRef;
  final String title;
  const CallTranscriptScreen(
      {super.key, required this.callRef, this.title = 'Transcript'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final async = ref.watch(callTranscriptProvider(callRef));
    return NexusPage(
      title: title,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
            error: e,
            action: 'load the transcript',
            asPage: true,
            onRetry: () => ref.invalidate(callTranscriptProvider(callRef))),
        data: (transcript) {
          if (transcript == null || transcript.turns.isEmpty) {
            return Center(
                child: Text('No transcript for this call.',
                    style: TextStyle(color: t.muted)));
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
            children: [
              if (transcript.summary != null &&
                  transcript.summary!.isNotEmpty) ...[
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
                          style: TextStyle(
                              fontSize: 13.5, height: 1.45, color: t.text)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              for (final turn in transcript.turns) _turn(context, turn),
            ],
          );
        },
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
          NexusPill(turn.tool ?? 'tool', color: t.accent2, outlined: true),
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
            child: Text(turn.content ?? '',
                style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: agent ? Colors.white : t.text)),
          ),
        ],
      ),
    );
  }
}
