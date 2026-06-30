/// DTOs for the AI agent profiles (`/voice/agents`), HTTP tools
/// (`/voice/http-tools`), and agent knowledge pages (`/voice/agent-knowledge`).
library;

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
int? _int(dynamic v) => v == null ? null : int.tryParse('$v');
String _str(dynamic v) => v?.toString() ?? '';
List<int> _ints(dynamic v) => v is List
    ? v.map((e) => int.tryParse('$e') ?? -1).where((e) => e >= 0).toList()
    : const [];

// ── Agents ─────────────────────────────────────────────────────────────

/// Agent list-row summary.
class NexusAgentSummary {
  final int id;
  final String name;
  final bool enabled;
  final String chatModelName;
  final String ttsVoice;
  final int maxTurns;
  final int toolCount;
  final int flowsUsing;
  final int extensionsUsing;
  final DateTime? updatedAt;

  const NexusAgentSummary({
    required this.id,
    required this.name,
    this.enabled = false,
    this.chatModelName = '',
    this.ttsVoice = '',
    this.maxTurns = 0,
    this.toolCount = 0,
    this.flowsUsing = 0,
    this.extensionsUsing = 0,
    this.updatedAt,
  });

  factory NexusAgentSummary.fromJson(Map<String, dynamic> j) =>
      NexusAgentSummary(
        id: _int(j['id']) ?? 0,
        name: _str(j['name']),
        enabled: j['enabled'] == true,
        chatModelName: _str(j['chatModelName']),
        ttsVoice: _str(j['ttsVoice']),
        maxTurns: _int(j['maxTurns']) ?? 0,
        toolCount: _int(j['toolCount']) ?? 0,
        flowsUsing: _int(j['flowsUsing']) ?? 0,
        extensionsUsing: _int(j['extensionsUsing']) ?? 0,
        updatedAt: _date(j['updatedAt']),
      );
}

/// Full agent profile.
class NexusAgent {
  final int id;
  final String name;
  final bool enabled;
  final String systemPrompt;
  final String greeting;
  final String chatModelName;
  final bool allowThinking;
  final String ttsVoice;
  final int maxTurns;
  final bool allowTransfer;
  final bool allowScreenedTransfer;
  final bool allowVoicemail;
  final bool allowTakeMessage;
  final bool allowSms;
  final bool allowWebSearch;
  final String notifySmsNumber;
  final String webhookUrl;
  final bool hasWebhookSecret;
  final int? smsFromPhoneNumberId;
  final List<int> knowledgeCollectionIds;
  final List<int> selectedToolIds;

  const NexusAgent({
    this.id = 0,
    this.name = '',
    this.enabled = true,
    this.systemPrompt = '',
    this.greeting = '',
    this.chatModelName = '',
    this.allowThinking = false,
    this.ttsVoice = '',
    this.maxTurns = 8,
    this.allowTransfer = false,
    this.allowScreenedTransfer = false,
    this.allowVoicemail = false,
    this.allowTakeMessage = false,
    this.allowSms = false,
    this.allowWebSearch = false,
    this.notifySmsNumber = '',
    this.webhookUrl = '',
    this.hasWebhookSecret = false,
    this.smsFromPhoneNumberId,
    this.knowledgeCollectionIds = const [],
    this.selectedToolIds = const [],
  });

  factory NexusAgent.fromJson(Map<String, dynamic> j) => NexusAgent(
        id: _int(j['id']) ?? 0,
        name: _str(j['name']),
        enabled: j['enabled'] != false,
        systemPrompt: _str(j['systemPrompt']),
        greeting: _str(j['greeting']),
        chatModelName: _str(j['chatModelName']),
        allowThinking: j['allowThinking'] == true,
        ttsVoice: _str(j['ttsVoice']),
        maxTurns: _int(j['maxTurns']) ?? 8,
        allowTransfer: j['allowTransfer'] == true,
        allowScreenedTransfer: j['allowScreenedTransfer'] == true,
        allowVoicemail: j['allowVoicemail'] == true,
        allowTakeMessage: j['allowTakeMessage'] == true,
        allowSms: j['allowSms'] == true,
        allowWebSearch: j['allowWebSearch'] == true,
        notifySmsNumber: _str(j['notifySmsNumber']),
        webhookUrl: _str(j['webhookUrl']),
        hasWebhookSecret: j['hasWebhookSecret'] == true,
        smsFromPhoneNumberId: _int(j['smsFromPhoneNumberId']),
        knowledgeCollectionIds: _ints(j['knowledgeCollectionIds']),
        selectedToolIds: _ints(j['selectedToolIds']),
      );
}

/// Options for the agent editor pickers.
class NexusAgentOptions {
  final List<String> chatModels;
  final List<({int id, String number})> smsNumbers;
  final List<({int id, String name, int documentCount})> collections;

  const NexusAgentOptions({
    this.chatModels = const [],
    this.smsNumbers = const [],
    this.collections = const [],
  });

  factory NexusAgentOptions.fromJson(Map<String, dynamic> j) =>
      NexusAgentOptions(
        chatModels: ((j['chatModels'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(),
        smsNumbers: ((j['smsNumbers'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) =>
                (id: _int(m['id']) ?? 0, number: _str(m['number'])))
            .toList(),
        collections: ((j['collections'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => (
                  id: _int(m['id']) ?? 0,
                  name: _str(m['name']),
                  documentCount: _int(m['documentCount']) ?? 0
                ))
            .toList(),
      );
}

/// Result of a saved-agent test chat.
class NexusAgentTestResult {
  final List<String> replies;
  final List<({String tool, Map<String, dynamic> args})> actions;
  final List<String> pages;
  final String? error;

  const NexusAgentTestResult({
    this.replies = const [],
    this.actions = const [],
    this.pages = const [],
    this.error,
  });

  factory NexusAgentTestResult.fromJson(Map<String, dynamic> j) =>
      NexusAgentTestResult(
        replies:
            ((j['replies'] as List?) ?? const []).map((e) => '$e').toList(),
        actions: ((j['actions'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => (
                  tool: _str(m['tool']),
                  args: (m['args'] is Map)
                      ? Map<String, dynamic>.from(m['args'] as Map)
                      : <String, dynamic>{}
                ))
            .toList(),
        pages: ((j['pages'] as List?) ?? const []).map((e) => '$e').toList(),
        error: j['error']?.toString(),
      );
}

// ── HTTP tools ─────────────────────────────────────────────────────────

class NexusHttpToolSummary {
  final int id;
  final String name;
  final String description;
  final String method;
  final String url;
  final bool enabled;
  final int timeoutSeconds;
  final int profilesUsing;

  const NexusHttpToolSummary({
    required this.id,
    required this.name,
    this.description = '',
    this.method = 'GET',
    this.url = '',
    this.enabled = true,
    this.timeoutSeconds = 10,
    this.profilesUsing = 0,
  });

  factory NexusHttpToolSummary.fromJson(Map<String, dynamic> j) =>
      NexusHttpToolSummary(
        id: _int(j['id']) ?? 0,
        name: _str(j['name']),
        description: _str(j['description']),
        method: _str(j['method']).isEmpty ? 'GET' : _str(j['method']),
        url: _str(j['url']),
        enabled: j['enabled'] != false,
        timeoutSeconds: _int(j['timeoutSeconds']) ?? 10,
        profilesUsing: _int(j['profilesUsing']) ?? 0,
      );
}

class NexusHttpTool {
  final int id;
  final String name;
  final String description;
  final String method;
  final String url;
  final bool enabled;
  final int timeoutSeconds;
  final String parametersJson;
  final List<({String name, bool hasHeaderValue})> headers;

  const NexusHttpTool({
    this.id = 0,
    this.name = '',
    this.description = '',
    this.method = 'GET',
    this.url = '',
    this.enabled = true,
    this.timeoutSeconds = 10,
    this.parametersJson = '',
    this.headers = const [],
  });

  factory NexusHttpTool.fromJson(Map<String, dynamic> j) => NexusHttpTool(
        id: _int(j['id']) ?? 0,
        name: _str(j['name']),
        description: _str(j['description']),
        method: _str(j['method']).isEmpty ? 'GET' : _str(j['method']),
        url: _str(j['url']),
        enabled: j['enabled'] != false,
        timeoutSeconds: _int(j['timeoutSeconds']) ?? 10,
        parametersJson: _str(j['parametersJson']),
        headers: ((j['headers'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => (
                  name: _str(m['name']),
                  hasHeaderValue: m['hasHeaderValue'] == true
                ))
            .toList(),
      );
}

// ── Agent knowledge pages ──────────────────────────────────────────────

class NexusKnowledgePageSummary {
  final int id;
  final String title;
  final String keywords;
  final bool enabled;
  final int contentChars;
  final List<int> agentProfileIds;
  final DateTime? updatedAt;

  const NexusKnowledgePageSummary({
    required this.id,
    required this.title,
    this.keywords = '',
    this.enabled = true,
    this.contentChars = 0,
    this.agentProfileIds = const [],
    this.updatedAt,
  });

  factory NexusKnowledgePageSummary.fromJson(Map<String, dynamic> j) =>
      NexusKnowledgePageSummary(
        id: _int(j['id']) ?? 0,
        title: _str(j['title']),
        keywords: _str(j['keywords']),
        enabled: j['enabled'] != false,
        contentChars: _int(j['contentChars']) ?? 0,
        agentProfileIds: _ints(j['agentProfileIds']),
        updatedAt: _date(j['updatedAt']),
      );
}

class NexusKnowledgePage {
  final int id;
  final String title;
  final String keywords;
  final String content;
  final bool enabled;
  final List<int> agentProfileIds;

  const NexusKnowledgePage({
    this.id = 0,
    this.title = '',
    this.keywords = '',
    this.content = '',
    this.enabled = true,
    this.agentProfileIds = const [],
  });

  factory NexusKnowledgePage.fromJson(Map<String, dynamic> j) =>
      NexusKnowledgePage(
        id: _int(j['id']) ?? 0,
        title: _str(j['title']),
        keywords: _str(j['keywords']),
        content: _str(j['content']),
        enabled: j['enabled'] != false,
        agentProfileIds: _ints(j['agentProfileIds']),
      );
}
