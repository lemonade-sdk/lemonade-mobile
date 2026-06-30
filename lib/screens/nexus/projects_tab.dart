import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/chat_provider.dart';
import '../../providers/nav_provider.dart';
import '../../providers/projects_provider.dart';
import '../../themes/nexus_tokens.dart';
import '../../widgets/nexus/nexus_ui.dart';

/// Projects tab — read-only view of agent projects streamed from the user's Mac.
///
/// STUB: backed by [projectsProvider]'s in-memory seed; no backend exists yet.
class ProjectsTab extends ConsumerWidget {
  const ProjectsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final projects = ref.watch(projectsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sourceStrip(context),
        const SizedBox(height: 16),
        for (final p in projects) ...[
          _projectCard(context, p),
          const SizedBox(height: 16),
        ],
        NexusCard(
          onTap: () {
            ref.read(navTabProvider.notifier).state = NexusTab.chat;
            ref.read(chatProvider.notifier).sendMessage(
                'You are the project coordinator. Give me a status summary across my running projects.');
          },
          color: t.surface,
          borderColor: t.line2,
          padding: const EdgeInsets.all(13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.forum_outlined, size: 16, color: t.accent),
              const SizedBox(width: 8),
              Text('Talk to the Coordinator',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.accent2)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sourceStrip(BuildContext context) {
    final t = context.nexus;
    return NexusCard(
      radius: 15,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [t.accentSoft, t.surface],
      ),
      borderColor: t.accent.withValues(alpha: 0.32),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.laptop_mac, color: t.accent2, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(projectsSource.deviceName,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: t.text)),
                Text('${projectsSource.projectCount} projects · streaming live',
                    style: TextStyle(fontSize: 11, color: t.muted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(children: [
                NexusStatusDot(color: t.good, size: 6),
                const SizedBox(width: 5),
                Text('Online',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: t.good)),
              ]),
              const SizedBox(height: 4),
              const NexusPill('VIEW ONLY', color: Color(0xFF93A0C0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _projectCard(BuildContext context, NexusProject p) {
    final t = context.nexus;
    final stateColor = p.isRunning ? t.good : t.faint;
    return NexusCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: t.text)),
                    Text(p.type, style: TextStyle(fontSize: 11.5, color: t.muted)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(children: [
                  if (p.isRunning)
                    NexusStatusDot(color: stateColor, size: 6)
                  else
                    Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            color: stateColor, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(p.stateLabel,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: stateColor)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(p.progText, style: TextStyle(fontSize: 11.5, color: t.muted)),
              Text(p.pctText,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: t.accent2)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p.progress,
              minHeight: 7,
              backgroundColor: t.bg,
              valueColor: AlwaysStoppedAnimation(t.accent),
            ),
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in p.chips)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${c.n}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: c.color)),
                    const SizedBox(width: 5),
                    Text(c.label,
                        style: TextStyle(fontSize: 10.5, color: t.muted)),
                  ]),
                ),
            ],
          ),
          if (p.isRunning && p.stages.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(color: t.line, height: 1),
            const SizedBox(height: 10),
            Text('NOW RUNNING',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: t.faint)),
            const SizedBox(height: 5),
            Text(p.current,
                style: TextStyle(fontSize: 12.5, color: t.text)),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final s in p.stages)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(right: 5),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: s.active
                            ? t.accent
                            : (s.done ? t.accentSoft : t.surface2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(s.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: s.active
                                  ? Colors.white
                                  : (s.done ? t.accent2 : t.muted))),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 13),
          Divider(color: t.line, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final a in p.agentInitials)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: t.line2),
                  ),
                  child: Text(a,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: t.accent2)),
                ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(p.activity,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: t.muted)),
              ),
              Text(p.time, style: nexusMono(fontSize: 10, color: t.faint)),
            ],
          ),
        ],
      ),
    );
  }
}
