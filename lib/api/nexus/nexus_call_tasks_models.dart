/// DTOs for the AI Call Tasks API (`/api/v1/voice/tasks/*`). Operator-launched,
/// AI-driven outbound calls with live transcript, whisper steering, and human
/// voice takeover. camelCase in/out.
library;

import 'json_utils.dart';

DateTime? _date(dynamic v) => jsonDate(v);
int? _int(dynamic v) => jsonInt(v);
String _str(dynamic v) => jsonStr(v);

enum TaskState { pending, dialing, inProgress, completed, failed, canceled, unknown }

TaskState _taskState(dynamic v) {
  switch (_str(v).toLowerCase()) {
    case 'pending':
      return TaskState.pending;
    case 'dialing':
      return TaskState.dialing;
    case 'inprogress':
      return TaskState.inProgress;
    case 'completed':
      return TaskState.completed;
    case 'failed':
      return TaskState.failed;
    case 'canceled':
      return TaskState.canceled;
    default:
      return TaskState.unknown;
  }
}

enum ControlMode { autonomous, override, humanTakeover }

ControlMode _controlMode(dynamic v) {
  switch (_str(v).toLowerCase()) {
    case 'override':
      return ControlMode.override;
    case 'humantakeover':
      return ControlMode.humanTakeover;
    default:
      return ControlMode.autonomous;
  }
}

/// `CallTask`.
class NexusCallTask {
  final int id;
  final TaskState state;
  final ControlMode controlMode;
  final String? callRef;
  final String fromNumber;
  final String toNumber;
  final String objective;
  final int? agentProfileId;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? outcome;

  const NexusCallTask({
    required this.id,
    required this.state,
    required this.controlMode,
    this.callRef,
    this.fromNumber = '',
    this.toNumber = '',
    this.objective = '',
    this.agentProfileId,
    this.createdAt,
    this.startedAt,
    this.endedAt,
    this.outcome,
  });

  bool get isActive =>
      state == TaskState.dialing || state == TaskState.inProgress;
  bool get isFinished =>
      state == TaskState.completed ||
      state == TaskState.failed ||
      state == TaskState.canceled;

  factory NexusCallTask.fromJson(Map<String, dynamic> j) => NexusCallTask(
        id: _int(j['id']) ?? 0,
        state: _taskState(j['state']),
        controlMode: _controlMode(j['controlMode']),
        callRef: j['callRef']?.toString(),
        fromNumber: _str(j['fromNumber']),
        toNumber: _str(j['toNumber']),
        objective: _str(j['objective']),
        agentProfileId: _int(j['agentProfileId']),
        createdAt: _date(j['createdAt']),
        startedAt: _date(j['startedAt']),
        endedAt: _date(j['endedAt']),
        outcome: j['outcome']?.toString(),
      );
}

/// A single transcript turn.
class NexusTranscriptTurn {
  final String role; // caller | agent | tool | event
  final String? content;
  final DateTime? at;
  final String? tool;
  final bool interrupted;

  const NexusTranscriptTurn({
    required this.role,
    this.content,
    this.at,
    this.tool,
    this.interrupted = false,
  });

  bool get isAgent => role == 'agent';
  bool get isCaller => role == 'caller';
  bool get isTool => role == 'tool';
  bool get isEvent => role == 'event';

  factory NexusTranscriptTurn.fromJson(Map<String, dynamic> j) =>
      NexusTranscriptTurn(
        role: _str(j['role']),
        content: j['content']?.toString(),
        at: _date(j['at']),
        tool: j['tool']?.toString(),
        interrupted: j['interrupted'] == true,
      );
}

/// A launch-form preset (admin-curated) for AI call tasks.
class NexusCallPreset {
  final int id;
  final String name;
  final String agentName;
  final String systemPrompt;
  final String objective;

  const NexusCallPreset({
    required this.id,
    required this.name,
    this.agentName = '',
    this.systemPrompt = '',
    this.objective = '',
  });

  factory NexusCallPreset.fromJson(Map<String, dynamic> j) => NexusCallPreset(
        id: _int(j['id']) ?? 0,
        name: _str(j['name']),
        agentName: _str(j['agentName']),
        systemPrompt: _str(j['systemPrompt']),
        objective: _str(j['objective']),
      );
}

/// `Transcript`.
class NexusTranscript {
  final int taskId;
  final String? callRef;
  final TaskState state;
  final String? summary;
  final List<NexusTranscriptTurn> turns;

  const NexusTranscript({
    required this.taskId,
    this.callRef,
    this.state = TaskState.unknown,
    this.summary,
    this.turns = const [],
  });

  factory NexusTranscript.fromJson(Map<String, dynamic> j) => NexusTranscript(
        taskId: _int(j['taskId']) ?? 0,
        callRef: j['callRef']?.toString(),
        state: _taskState(j['state']),
        summary: j['summary']?.toString(),
        turns: ((j['turns'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(NexusTranscriptTurn.fromJson)
            .toList(),
      );
}
