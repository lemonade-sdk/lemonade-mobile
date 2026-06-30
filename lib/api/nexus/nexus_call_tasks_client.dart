/// Client for the AI Call Tasks API (`/api/v1/voice/tasks/*`) — operator-
/// launched AI outbound calls with live transcript, whisper steering, mode
/// control, and hangup. The human-voice takeover WebSocket lives in
/// `nexus_call_takeover_socket.dart`.
library;

import 'dart:typed_data';

import 'nexus_call_tasks_models.dart';
import 'nexus_gateway_base.dart';

class NexusCallTasksClient extends NexusGatewayClient {
  NexusCallTasksClient({required super.token, super.client});

  /// POST /voice/tasks — launch an AI call toward [objective]. Blocks until the
  /// far end answers (multi-second; client may time out — poll [getTask]).
  Future<NexusCallTask> createTask({
    required String to,
    String? toName,
    String? agentName,
    String? systemPrompt,
    String? objective,
    int? profileId,
    int? fromPhoneNumberId,
  }) async {
    final json = await postJson(uri('/voice/tasks'), {
      'to': to,
      if (toName != null && toName.isNotEmpty) 'toName': toName,
      if (agentName != null && agentName.isNotEmpty) 'agentName': agentName,
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        'systemPrompt': systemPrompt,
      if (objective != null && objective.isNotEmpty) 'objective': objective,
      if (profileId != null) 'profileId': profileId,
      if (fromPhoneNumberId != null) 'fromPhoneNumberId': fromPhoneNumberId,
    });
    return NexusCallTask.fromJson(json);
  }

  /// GET /voice/tasks/presets — admin-curated launch-form suggestions.
  Future<List<NexusCallPreset>> getPresets() async {
    final json = await getJson(uri('/voice/tasks/presets'));
    return ((json['presets'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(NexusCallPreset.fromJson)
        .toList();
  }

  /// GET /voice/tasks — newest first.
  Future<List<NexusCallTask>> listTasks({bool activeOnly = false}) async {
    final json =
        await getJson(uri('/voice/tasks', {if (activeOnly) 'active': 'true'}));
    return ((json['tasks'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(NexusCallTask.fromJson)
        .toList();
  }

  Future<NexusCallTask> getTask(int id) async {
    final json = await getJson(uri('/voice/tasks/$id'));
    return NexusCallTask.fromJson(json);
  }

  /// GET /voice/tasks/{id}/transcript — both sides, live-pollable.
  Future<NexusTranscript> getTranscript(int id) async {
    final json = await getJson(uri('/voice/tasks/$id/transcript'));
    return NexusTranscript.fromJson(json);
  }

  /// POST /voice/tasks/{id}/mode — 'autonomous' | 'override' | 'takeover'.
  Future<ControlMode> setMode(int id, String mode) async {
    final json = await postJson(uri('/voice/tasks/$id/mode'), {'mode': mode});
    final cm = json['controlMode'];
    return cm == null
        ? ControlMode.autonomous
        : NexusCallTask.fromJson({'controlMode': cm, 'id': 0, 'state': ''})
            .controlMode;
  }

  /// POST /voice/tasks/{id}/whisper — private steering (Override).
  Future<void> whisper(int id, String text) =>
      postJson(uri('/voice/tasks/$id/whisper'), {'text': text}).then((_) {});

  /// POST /voice/tasks/{id}/hangup — end the call, close the task.
  Future<void> hangup(int id) =>
      postJson(uri('/voice/tasks/$id/hangup')).then((_) {});

  /// GET /voice/tasks/{id}/recording — mixed WAV (404 if not recorded).
  Future<Uint8List> recording(int id) =>
      getBytes(uri('/voice/tasks/$id/recording'));
}
