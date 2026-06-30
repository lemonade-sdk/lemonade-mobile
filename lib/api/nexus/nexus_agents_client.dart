/// Client for AI agent profiles, HTTP tools, and agent knowledge pages — the
/// reusable phone-agent configuration under `/api/v1/voice/{agents,http-tools,
/// agent-knowledge}`. Mutations require org Admin/Owner (the gateway enforces).
library;

import 'nexus_agents_models.dart';
import 'nexus_gateway_base.dart';

class NexusAgentsClient extends NexusGatewayClient {
  NexusAgentsClient({required super.token, super.client});

  // ── Agent profiles ──────────────────────────────────────────────────

  Future<List<NexusAgentSummary>> listAgents() async {
    final json = await getJson(uri('/voice/agents'));
    return ((json['agents'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(NexusAgentSummary.fromJson)
        .toList();
  }

  Future<NexusAgentOptions> agentOptions() async {
    final json = await getJson(uri('/voice/agents/options'));
    return NexusAgentOptions.fromJson(json);
  }

  Future<NexusAgent> getAgent(int id) async {
    final json = await getJson(uri('/voice/agents/$id'));
    return NexusAgent.fromJson(json);
  }

  Future<NexusAgent> saveAgent(NexusAgent a,
      {String? webhookSecret, List<int> collectionIds = const []}) async {
    final body = _agentBody(a, webhookSecret, collectionIds);
    final json = a.id == 0
        ? await postJson(uri('/voice/agents'), body)
        : await putJson(uri('/voice/agents/${a.id}'), body);
    return NexusAgent.fromJson(json);
  }

  Future<void> deleteAgent(int id) => delete(uri('/voice/agents/$id'));

  /// POST /voice/agents/{id}/test-chat — run the saved agent over a message
  /// thread (actions are returned but NOT executed).
  Future<NexusAgentTestResult> testChat(
      int id, List<({String role, String content})> messages) async {
    final json = await postJson(uri('/voice/agents/$id/test-chat'), {
      'messages': [
        for (final m in messages) {'role': m.role, 'content': m.content}
      ]
    });
    return NexusAgentTestResult.fromJson(json);
  }

  Map<String, dynamic> _agentBody(
      NexusAgent a, String? webhookSecret, List<int> collectionIds) {
    return {
      'name': a.name,
      'enabled': a.enabled,
      'systemPrompt': a.systemPrompt,
      'greeting': a.greeting,
      'chatModelName': a.chatModelName,
      'allowThinking': a.allowThinking,
      'ttsVoice': a.ttsVoice,
      'maxTurns': a.maxTurns,
      'allowTransfer': a.allowTransfer,
      'allowScreenedTransfer': a.allowScreenedTransfer,
      'allowVoicemail': a.allowVoicemail,
      'allowTakeMessage': a.allowTakeMessage,
      'allowSms': a.allowSms,
      'allowWebSearch': a.allowWebSearch,
      'notifySmsNumber': a.notifySmsNumber,
      'webhookUrl': a.webhookUrl,
      if (webhookSecret != null && webhookSecret.isNotEmpty)
        'webhookSecret': webhookSecret,
      if (a.smsFromPhoneNumberId != null)
        'smsFromPhoneNumberId': a.smsFromPhoneNumberId,
      'toolIds': a.selectedToolIds,
      // The save contract takes a CSV of collection ids.
      'knowledgeCollectionIds': collectionIds.join(','),
    };
  }

  // ── HTTP tools ──────────────────────────────────────────────────────

  Future<List<NexusHttpToolSummary>> listTools() async {
    final json = await getJson(uri('/voice/http-tools'));
    return ((json['tools'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(NexusHttpToolSummary.fromJson)
        .toList();
  }

  Future<NexusHttpTool> getTool(int id) async {
    final json = await getJson(uri('/voice/http-tools/$id'));
    return NexusHttpTool.fromJson(json);
  }

  Future<NexusHttpTool> saveTool(
    NexusHttpTool t, {
    required List<String> headerNames,
    required List<String> headerValues,
  }) async {
    final body = {
      'name': t.name,
      'description': t.description,
      'url': t.url,
      'method': t.method,
      'timeoutSeconds': t.timeoutSeconds,
      'enabled': t.enabled,
      'parametersJson': t.parametersJson,
      'headerNames': headerNames,
      'headerValues': headerValues,
    };
    final json = t.id == 0
        ? await postJson(uri('/voice/http-tools'), body)
        : await putJson(uri('/voice/http-tools/${t.id}'), body);
    return NexusHttpTool.fromJson(json);
  }

  Future<void> deleteTool(int id) => delete(uri('/voice/http-tools/$id'));

  // ── Agent knowledge pages ───────────────────────────────────────────

  Future<List<NexusKnowledgePageSummary>> listPages() async {
    final json = await getJson(uri('/voice/agent-knowledge'));
    return ((json['pages'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(NexusKnowledgePageSummary.fromJson)
        .toList();
  }

  Future<NexusKnowledgePage> getPage(int id) async {
    final json = await getJson(uri('/voice/agent-knowledge/$id'));
    return NexusKnowledgePage.fromJson(json);
  }

  Future<NexusKnowledgePage> savePage(NexusKnowledgePage p) async {
    final body = {
      'title': p.title,
      'keywords': p.keywords,
      'content': p.content,
      'enabled': p.enabled,
      'agentProfileIds': p.agentProfileIds,
    };
    final json = p.id == 0
        ? await postJson(uri('/voice/agent-knowledge'), body)
        : await putJson(uri('/voice/agent-knowledge/${p.id}'), body);
    return NexusKnowledgePage.fromJson(json);
  }

  Future<void> deletePage(int id) => delete(uri('/voice/agent-knowledge/$id'));
}
