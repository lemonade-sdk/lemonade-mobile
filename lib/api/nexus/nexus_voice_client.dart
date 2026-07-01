/// Client for the Nexus gateway Voice API — Calls, Numbers, Extensions, IVR
/// flows, and Voicemail (`/api/v1/voice/*`). Authenticated with the account
/// bearer token. Powers the redesign's Calls + PBX tabs and the Live Call
/// overlay's controls.
library;

import 'dart:typed_data';

import 'nexus_call_tasks_models.dart' show NexusTranscript;
import 'nexus_gateway_base.dart';
import 'nexus_voice_models.dart';

class NexusVoiceClient extends NexusGatewayClient {
  NexusVoiceClient({required super.token, super.client});

  // ── Dashboard / settings ────────────────────────────────────────────

  /// GET /voice/dashboard — landing aggregates (counts, minutes, recent calls).
  Future<NexusVoiceDashboard> dashboard() async {
    final json = await getJson(uri('/voice/dashboard'));
    return NexusVoiceDashboard.fromJson(json);
  }

  /// GET /voice/settings — account voice settings.
  Future<NexusVoiceSettings> settings() async {
    final json = await getJson(uri('/voice/settings'));
    return NexusVoiceSettings.fromJson(json);
  }

  /// PUT /voice/settings — org Admin/Owner. Pass only fields to change.
  Future<NexusVoiceSettings> updateSettings({
    String? timeZone,
    String? callerIdName,
    bool? recordCalls,
    String? callTaskPromptTemplate,
  }) async {
    final json = await putJson(uri('/voice/settings'), {
      if (timeZone != null) 'timeZone': timeZone,
      if (callerIdName != null) 'callerIdName': callerIdName,
      if (recordCalls != null) 'recordCalls': recordCalls,
      if (callTaskPromptTemplate != null)
        'callTaskPromptTemplate': callTaskPromptTemplate,
    });
    return NexusVoiceSettings.fromJson(json);
  }

  // ── Calls ───────────────────────────────────────────────────────────

  /// POST /voice/calls — LLM dial-out. Returns the new callRef.
  Future<String> originateCall({
    required String to,
    int? fromExtensionId,
    String? callerIdNumber,
  }) async {
    final json = await postJson(uri('/voice/calls'), {
      'to': to,
      if (fromExtensionId != null) 'fromExtensionId': fromExtensionId,
      if (callerIdNumber != null) 'callerIdNumber': callerIdNumber,
    });
    return (json['callRef'] ?? '').toString();
  }

  /// GET /voice/calls — recent or active calls.
  Future<List<NexusCall>> listCalls({bool activeOnly = false}) async {
    final json =
        await getJson(uri('/voice/calls', {if (activeOnly) 'active': 'true'}));
    final calls = (json['calls'] as List?) ?? const [];
    return calls
        .whereType<Map<String, dynamic>>()
        .map(NexusCall.fromJson)
        .toList();
  }

  /// GET /voice/cdrs — terminated call detail records.
  Future<List<NexusCall>> listCdrs({String? direction}) async {
    final json = await getJson(
        uri('/voice/cdrs', {if (direction != null) 'direction': direction}));
    final cdrs = (json['cdrs'] as List?) ?? const [];
    return cdrs
        .whereType<Map<String, dynamic>>()
        .map(NexusCall.fromJson)
        .toList();
  }

  /// GET /voice/calls/{ref}.
  Future<NexusCall> getCall(String callRef) async {
    final json = await getJson(uri('/voice/calls/$callRef'));
    return NexusCall.fromJson(json);
  }

  /// GET /voice/calls/{ref}/transcript — both-sided transcript + summary for any
  /// call (AI or human). Reuses the shared transcript shape.
  Future<NexusTranscript> callTranscript(String callRef) async {
    final json = await getJson(uri('/voice/calls/$callRef/transcript'));
    return NexusTranscript.fromJson({...json, 'callRef': callRef});
  }

  // ── Team ────────────────────────────────────────────────────────────

  /// GET /voice/team — org members.
  Future<List<NexusTeamMember>> team() async {
    final json = await getJson(uri('/voice/team'));
    return ((json['members'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(NexusTeamMember.fromJson)
        .toList();
  }

  Future<void> hangup(String callRef) =>
      postJson(uri('/voice/calls/$callRef/hangup')).then((_) {});
  Future<void> hold(String callRef) =>
      postJson(uri('/voice/calls/$callRef/hold')).then((_) {});
  Future<void> unhold(String callRef) =>
      postJson(uri('/voice/calls/$callRef/unhold')).then((_) {});
  Future<void> sendDtmf(String callRef, String digits) =>
      postJson(uri('/voice/calls/$callRef/dtmf'), {'digits': digits}).then((_) {});
  Future<void> transfer(String callRef, String target,
          {String mode = 'blind'}) =>
      postJson(uri('/voice/calls/$callRef/transfer'),
          {'target': target, 'mode': mode}).then((_) {});

  // ── Numbers ─────────────────────────────────────────────────────────

  Future<List<NexusNumber>> listNumbers() async {
    final json = await getJson(uri('/voice/numbers'));
    final nums = (json['numbers'] as List?) ?? const [];
    return nums
        .whereType<Map<String, dynamic>>()
        .map(NexusNumber.fromJson)
        .toList();
  }

  /// GET /voice/numbers/available — inventory search. The carrier is never
  /// exposed; [segment] (personal|business|both) is the product-type switch, and
  /// the response says whether the switch should render (`switchEnabled`).
  /// Pass [query] (digits, ≥3) OR [state] (2-letter). [type] applies to [query].
  Future<NexusNumberSearchResult> searchAvailable({
    String? query,
    String type = 'starts',
    String? state,
    String? segment,
  }) async {
    final json = await getJson(uri('/voice/numbers/available', {
      if (query != null) 'query': query,
      'type': type,
      if (state != null) 'state': state,
      if (segment != null) 'segment': segment,
    }));
    return NexusNumberSearchResult.fromJson(json);
  }

  /// POST /voice/numbers/order — buy. Sends ONLY {did,label}; the backend
  /// resolves the provider. 402 insufficient_balance (Personal wallet) → top-up
  /// then retry; 409 already on platform; 400 no longer available.
  Future<NexusNumber> orderNumber(String did, {String? label}) async {
    final json = await postJson(uri('/voice/numbers/order'),
        {'did': did, if (label != null && label.isNotEmpty) 'label': label});
    return NexusNumber.fromJson(json);
  }

  /// PUT /voice/numbers/{id}/routing.
  Future<NexusNumber> updateRouting(
    int id, {
    required String routeType,
    int? ivrFlowId,
    int? extensionId,
    String? forwardE164,
    String? label,
  }) async {
    final json = await putJson(uri('/voice/numbers/$id/routing'), {
      'routeType': routeType,
      if (ivrFlowId != null) 'ivrFlowId': ivrFlowId,
      if (extensionId != null) 'extensionId': extensionId,
      if (forwardE164 != null) 'forwardE164': forwardE164,
      if (label != null) 'label': label,
    });
    return NexusNumber.fromJson(json);
  }

  Future<void> cancelNumber(int id) => delete(uri('/voice/numbers/$id'));

  Future<void> sendSms(int numberId, String to, String message) =>
      postJson(uri('/voice/numbers/$numberId/sms'), {'to': to, 'message': message})
          .then((_) {});

  // ── Extensions ──────────────────────────────────────────────────────

  Future<List<NexusExtension>> listExtensions() async {
    final json = await getJson(uri('/voice/extensions'));
    final exts = (json['extensions'] as List?) ?? const [];
    return exts
        .whereType<Map<String, dynamic>>()
        .map(NexusExtension.fromJson)
        .toList();
  }

  Future<NexusExtensionCreated> createExtension({
    String? number,
    String? displayName,
    int? ringTimeoutSeconds,
    bool? voicemailEnabled,
  }) async {
    final json = await postJson(uri('/voice/extensions'), {
      if (number != null) 'number': number,
      if (displayName != null) 'displayName': displayName,
      if (ringTimeoutSeconds != null) 'ringTimeoutSeconds': ringTimeoutSeconds,
      if (voicemailEnabled != null) 'voicemailEnabled': voicemailEnabled,
    });
    final ext = NexusExtension.fromJson(
        (json['extension'] as Map<String, dynamic>?) ?? json);
    return NexusExtensionCreated(ext, (json['sipPassword'] ?? '').toString());
  }

  /// PUT /voice/extensions/{id}. Pass only the fields to change.
  Future<NexusExtension> updateExtension(
    int id, {
    String? displayName,
    int? ringTimeoutSeconds,
    bool? voicemailEnabled,
    String? forwardMode,
    String? forwardTarget,
    bool? enabled,
  }) async {
    final json = await putJson(uri('/voice/extensions/$id'), {
      if (displayName != null) 'displayName': displayName,
      if (ringTimeoutSeconds != null) 'ringTimeoutSeconds': ringTimeoutSeconds,
      if (voicemailEnabled != null) 'voicemailEnabled': voicemailEnabled,
      if (forwardMode != null) 'forwardMode': forwardMode,
      if (forwardTarget != null) 'forwardTarget': forwardTarget,
      if (enabled != null) 'enabled': enabled,
    });
    return NexusExtension.fromJson(json);
  }

  Future<void> deleteExtension(int id) => delete(uri('/voice/extensions/$id'));

  // ── IVR flows ───────────────────────────────────────────────────────

  Future<List<NexusFlow>> listFlows() async {
    final json = await getJson(uri('/voice/ivr-flows'));
    final flows = (json['flows'] as List?) ?? const [];
    return flows
        .whereType<Map<String, dynamic>>()
        .map(NexusFlow.fromJson)
        .toList();
  }

  Future<NexusFlow> getFlow(int id) async {
    final json = await getJson(uri('/voice/ivr-flows/$id'));
    return NexusFlow.fromJson(json);
  }

  Future<NexusFlow> createFlow(String name, Map<String, dynamic> flowJson) async {
    final json = await postJson(
        uri('/voice/ivr-flows'), {'name': name, 'flowJson': flowJson});
    return NexusFlow.fromJson(json);
  }

  Future<NexusFlow> updateFlow(
      int id, String name, Map<String, dynamic> flowJson) async {
    final json = await putJson(
        uri('/voice/ivr-flows/$id'), {'name': name, 'flowJson': flowJson});
    return NexusFlow.fromJson(json);
  }

  Future<NexusFlow> publishFlow(int id) async {
    final json = await postJson(uri('/voice/ivr-flows/$id/publish'));
    return NexusFlow.fromJson(json);
  }

  Future<void> deleteFlow(int id) => delete(uri('/voice/ivr-flows/$id'));

  // ── Voicemail ───────────────────────────────────────────────────────

  Future<List<NexusVoicemail>> listVoicemail({int? extensionId}) async {
    final json = await getJson(uri('/voice/voicemail',
        {if (extensionId != null) 'extensionId': extensionId}));
    final msgs = (json['messages'] as List?) ?? const [];
    return msgs
        .whereType<Map<String, dynamic>>()
        .map(NexusVoicemail.fromJson)
        .toList();
  }

  Future<Uint8List> voicemailAudio(int id) =>
      getBytes(uri('/voice/voicemail/$id/audio'));

  Future<void> markVoicemailRead(int id) =>
      postJson(uri('/voice/voicemail/$id/read')).then((_) {});

  Future<void> deleteVoicemail(int id) => delete(uri('/voice/voicemail/$id'));
}
