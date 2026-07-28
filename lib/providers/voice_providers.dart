import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/nexus/nexus_call_tasks_models.dart';
import '../api/nexus/nexus_voice_models.dart';
import 'account_provider.dart' show CacheForExtension;
import 'nexus_gateway_provider.dart';

/// All gateway-only; resolve to empty when signed out (the Calls/PBX tabs render
/// a "sign in to Subscription" empty state in that case based on app mode).
///
/// Each dataset keeps a short TTL cache (`ref.cacheFor`) so flipping between
/// PBX sections / reopening a screen shows data instantly; mutations still
/// `ref.invalidate` for an immediate refetch.

/// Landing aggregates: counts + minutes used/left + recent calls.
final voiceDashboardProvider =
    FutureProvider.autoDispose<NexusVoiceDashboard?>((ref) async {
  ref.cacheFor(const Duration(minutes: 2));
  final client = ref.watch(nexusVoiceClientProvider);
  if (client == null) return null;
  return client.dashboard();
});

/// Account voice settings (record calls, caller-ID name, timezone, channels).
final voiceSettingsProvider =
    FutureProvider.autoDispose<NexusVoiceSettings?>((ref) async {
  ref.cacheFor(const Duration(minutes: 5));
  final client = ref.watch(nexusVoiceClientProvider);
  if (client == null) return null;
  return client.settings();
});

/// Org team members.
final voiceTeamProvider =
    FutureProvider.autoDispose<List<NexusTeamMember>>((ref) async {
  ref.cacheFor(const Duration(minutes: 5));
  final client = ref.watch(nexusVoiceClientProvider);
  if (client == null) return const [];
  return client.team();
});

/// Read-only transcript for a finished call (by callRef).
final callTranscriptProvider =
    FutureProvider.autoDispose.family<NexusTranscript?, String>((ref, callRef) async {
  ref.cacheFor(const Duration(minutes: 5));
  final client = ref.watch(nexusVoiceClientProvider);
  if (client == null) return null;
  return client.callTranscript(callRef);
});

final voiceNumbersProvider =
    FutureProvider.autoDispose<List<NexusNumber>>((ref) async {
  ref.cacheFor(const Duration(minutes: 5));
  final client = ref.watch(nexusVoiceClientProvider);
  if (client == null) return const [];
  return client.listNumbers();
});

final voiceExtensionsProvider =
    FutureProvider.autoDispose<List<NexusExtension>>((ref) async {
  ref.cacheFor(const Duration(minutes: 5));
  final client = ref.watch(nexusVoiceClientProvider);
  if (client == null) return const [];
  return client.listExtensions();
});

final voiceFlowsProvider =
    FutureProvider.autoDispose<List<NexusFlow>>((ref) async {
  ref.cacheFor(const Duration(minutes: 2));
  final client = ref.watch(nexusVoiceClientProvider);
  if (client == null) return const [];
  return client.listFlows();
});

/// Single flow with its full node JSON (for the Flow Editor).
final voiceFlowProvider =
    FutureProvider.autoDispose.family<NexusFlow?, int>((ref, id) async {
  ref.cacheFor(const Duration(minutes: 2));
  final client = ref.watch(nexusVoiceClientProvider);
  if (client == null) return null;
  return client.getFlow(id);
});

final voicemailProvider =
    FutureProvider.autoDispose<List<NexusVoicemail>>((ref) async {
  ref.cacheFor(const Duration(minutes: 2));
  final client = ref.watch(nexusVoiceClientProvider);
  if (client == null) return const [];
  return client.listVoicemail();
});

/// Terminated call detail records (GET /voice/cdrs) — the PBX call history.
final cdrProvider =
    FutureProvider.autoDispose<List<NexusCall>>((ref) async {
  ref.cacheFor(const Duration(minutes: 2));
  final client = ref.watch(nexusVoiceClientProvider);
  if (client == null) return const [];
  final cdrs = await client.listCdrs();
  // Newest first regardless of server ordering.
  cdrs.sort((a, b) => (b.startedAt ?? DateTime(0))
      .compareTo(a.startedAt ?? DateTime(0)));
  return cdrs;
});
