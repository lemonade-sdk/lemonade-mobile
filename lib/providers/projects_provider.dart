import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../themes/nexus_tokens.dart';

/// A kanban column count chip.
class ProjectChip {
  final String label;
  final int n;
  final Color color;
  const ProjectChip(this.label, this.n, this.color);
}

/// A pipeline stage cell.
class ProjectStage {
  final String name;
  final bool active;
  final bool done;
  const ProjectStage(this.name, {this.active = false, this.done = false});
}

/// A project surfaced from the remote coordinator.
///
/// STUB: there is no Projects/coordinator HTTP API in nexus-router yet. This
/// model + [projectsProvider] seed feed the Projects tab so the surface matches
/// the design; swap the provider's body for a real client/stream when the
/// backend ships — the UI binds only to this model.
class NexusProject {
  final String id;
  final String name;
  final String type;
  final bool isRunning;
  final String stateLabel;
  final double progress; // 0..1
  final String progText;
  final List<ProjectChip> chips;
  final String current; // "now running" task
  final List<ProjectStage> stages;
  final List<String> agentInitials;
  final String activity;
  final String time;

  const NexusProject({
    required this.id,
    required this.name,
    required this.type,
    required this.isRunning,
    required this.stateLabel,
    required this.progress,
    required this.progText,
    required this.chips,
    this.current = '',
    this.stages = const [],
    this.agentInitials = const [],
    this.activity = '',
    this.time = '',
  });

  String get pctText => '${(progress * 100).round()}%';
}

/// Remote source-of-truth strip (the Mac streaming projects). STUB.
class ProjectsSource {
  final String deviceName;
  final int projectCount;
  final bool online;
  const ProjectsSource({
    required this.deviceName,
    required this.projectCount,
    required this.online,
  });
}

const projectsSource = ProjectsSource(
  deviceName: "Geramy's MacBook Pro",
  projectCount: 4,
  online: true,
);

/// STUB project list. Colors resolve against the dark token palette so the seed
/// looks intentional even before a backend exists.
final projectsProvider = Provider<List<NexusProject>>((ref) {
  const t = NexusTokens.dark;
  return [
    NexusProject(
      id: 'p1',
      name: 'Voice agent revamp',
      type: 'Flutter · Dart',
      isRunning: true,
      stateLabel: 'Running',
      progress: 0.62,
      progText: '13 of 21 tasks',
      chips: [
        ProjectChip('To do', 8, t.muted),
        ProjectChip('Doing', 3, t.accent2),
        ProjectChip('Review', 2, t.warn),
        ProjectChip('Done', 8, t.good),
      ],
      current: 'Wiring the live-call takeover composer',
      stages: [
        ProjectStage('Plan', done: true),
        ProjectStage('Build', active: true),
        ProjectStage('Review'),
        ProjectStage('Ship'),
      ],
      agentInitials: ['CO', 'BD'],
      activity: 'Edited live_call.dart · ran flutter analyze',
      time: '2m',
    ),
    NexusProject(
      id: 'p2',
      name: 'Knowledge ingest pipeline',
      type: 'Python · FastAPI',
      isRunning: false,
      stateLabel: 'Idle',
      progress: 0.4,
      progText: '6 of 15 tasks',
      chips: [
        ProjectChip('To do', 9, t.muted),
        ProjectChip('Doing', 0, t.accent2),
        ProjectChip('Review', 0, t.warn),
        ProjectChip('Done', 6, t.good),
      ],
      agentInitials: ['KB'],
      activity: 'Paused after embedding backfill',
      time: '1h',
    ),
    NexusProject(
      id: 'p3',
      name: 'PBX flow templates',
      type: 'C# · NexusRouter.Voice',
      isRunning: false,
      stateLabel: 'Idle',
      progress: 0.85,
      progText: '17 of 20 tasks',
      chips: [
        ProjectChip('To do', 3, t.muted),
        ProjectChip('Doing', 0, t.accent2),
        ProjectChip('Review', 1, t.warn),
        ProjectChip('Done', 16, t.good),
      ],
      agentInitials: ['IVR'],
      activity: 'Awaiting review on after-hours flow',
      time: '3h',
    ),
  ];
});
