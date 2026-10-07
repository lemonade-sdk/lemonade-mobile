import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/exceptions.dart';
import '../api/nexus/nexus_call_tasks_models.dart';
import 'nexus_gateway_provider.dart';

/// AI call tasks, newest first. Empty when signed out.
final callTasksProvider =
    FutureProvider.autoDispose<List<NexusCallTask>>((ref) async {
  final client = ref.watch(nexusCallTasksClientProvider);
  if (client == null) return const [];
  return client.listTasks();
});

/// Admin-curated launch-form presets for the place-a-call card.
final callPresetsProvider =
    FutureProvider.autoDispose<List<NexusCallPreset>>((ref) async {
  final client = ref.watch(nexusCallTasksClientProvider);
  if (client == null) return const [];
  try {
    return await client.getPresets();
  } catch (_) {
    return const [];
  }
});

/// The single most-recent active task (drives the Calls live banner + nav dot).
///
/// Guards against "ghost" tasks: a call the voice node lost can sit in a
/// non-terminal state (Dialing/InProgress) server-side indefinitely. A real
/// phone call never runs for hours, so we ignore "active" tasks that started
/// more than [_ghostAfter] ago — otherwise a dead call shows as live forever.
const _ghostAfter = Duration(hours: 3);

final activeCallTaskProvider =
    FutureProvider.autoDispose<NexusCallTask?>((ref) async {
  final client = ref.watch(nexusCallTasksClientProvider);
  if (client == null) return null;
  final active = await client.listTasks(activeOnly: true);
  final now = DateTime.now();
  for (final task in active) {
    final started = task.startedAt ?? task.createdAt;
    if (started == null || now.difference(started) < _ghostAfter) {
      return task; // newest non-stale active task
    }
  }
  return null;
});

/// Errors a retry can't fix: the task is gone (404) or the session is no
/// longer accepted (401/403).
bool _isPermanent(Object e) =>
    e is LemonadeApiException &&
    (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 404);

/// One task, re-fetched live (used by the Live Call overlay header).
///
/// The polling loops below error-`continue` without yielding, and an
/// `async*` body only notices cancellation at a `yield` — so they also check
/// a disposal flag, or a closed overlay kept them running forever.
final callTaskProvider =
    StreamProvider.autoDispose.family<NexusCallTask, int>((ref, id) async* {
  final client = ref.watch(nexusCallTasksClientProvider);
  if (client == null) return;
  var disposed = false;
  ref.onDispose(() => disposed = true);
  while (!disposed) {
    NexusCallTask task;
    try {
      task = await client.getTask(id);
    } catch (e) {
      // A deleted task or a dead session will never recover — stop instead
      // of polling every 3 s for the rest of the process.
      if (_isPermanent(e)) rethrow;
      await Future.delayed(const Duration(seconds: 3));
      continue;
    }
    if (disposed) return;
    yield task;
    if (task.isFinished) return;
    await Future.delayed(const Duration(seconds: 3));
  }
});

/// Live transcript for a task, polled (~2s) until the call finishes.
final taskTranscriptProvider =
    StreamProvider.autoDispose.family<NexusTranscript, int>((ref, id) async* {
  final client = ref.watch(nexusCallTasksClientProvider);
  if (client == null) return;
  var disposed = false;
  ref.onDispose(() => disposed = true);
  while (!disposed) {
    NexusTranscript transcript;
    try {
      transcript = await client.getTranscript(id);
    } catch (e) {
      if (_isPermanent(e)) rethrow;
      await Future.delayed(const Duration(seconds: 3));
      continue;
    }
    if (disposed) return;
    yield transcript;
    if (transcript.state == TaskState.completed ||
        transcript.state == TaskState.failed ||
        transcript.state == TaskState.canceled) {
      // One more fetch already done; summary is in. Stop polling.
      return;
    }
    await Future.delayed(const Duration(milliseconds: 2200));
  }
});
