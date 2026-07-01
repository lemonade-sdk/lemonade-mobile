import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/nexus/nexus_agents_models.dart';
import '../../providers/agents_providers.dart';
import '../../providers/nexus_gateway_provider.dart';
import '../../themes/nexus_tokens.dart';
import '../../widgets/nexus/nexus_form.dart';
import '../../widgets/nexus/nexus_ui.dart';

/// Reusable phone-agent personas (`/voice/agents`).
class AgentsScreen extends ConsumerWidget {
  const AgentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final agents = ref.watch(agentsProvider);
    return NexusPage(
      title: 'AI agents',
      actions: [
        IconButton(
          icon: Icon(Icons.add, color: t.accent),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AgentEditor(agentId: null))),
        ),
      ],
      body: agents.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('$e', style: TextStyle(color: t.danger))),
        data: (list) => list.isEmpty
            ? Center(
                child: Text('No agents yet — tap + to create one.',
                    style: TextStyle(color: t.muted)))
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _row(context, list[i]),
              ),
      ),
    );
  }

  Widget _row(BuildContext context, NexusAgentSummary a) {
    final t = context.nexus;
    return NexusCard(
      radius: 14,
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AgentEditor(agentId: a.id))),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: t.surface2, borderRadius: BorderRadius.circular(11)),
          child: Icon(Icons.support_agent, color: t.accent2, size: 20),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: t.text)),
              Text(
                  '${a.chatModelName.isEmpty ? 'no model' : a.chatModelName} · ${a.toolCount} tools · ${a.flowsUsing + a.extensionsUsing} uses',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nexusMono(fontSize: 10.5, color: t.muted)),
            ],
          ),
        ),
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
                color: a.enabled ? t.good : t.faint, shape: BoxShape.circle)),
      ]),
    );
  }
}

class AgentEditor extends ConsumerStatefulWidget {
  final int? agentId;
  const AgentEditor({super.key, required this.agentId});

  @override
  ConsumerState<AgentEditor> createState() => _AgentEditorState();
}

class _AgentEditorState extends ConsumerState<AgentEditor> {
  final _name = TextEditingController();
  final _prompt = TextEditingController();
  final _greeting = TextEditingController();
  final _ttsVoice = TextEditingController();
  final _maxTurns = TextEditingController(text: '8');
  final _notifySms = TextEditingController();
  final _webhookUrl = TextEditingController();
  final _webhookSecret = TextEditingController();
  final _test = TextEditingController();
  final _scroll = ScrollController();

  bool _enabled = true;
  bool _allowThinking = false;
  bool _allowTransfer = false;
  bool _allowScreenedTransfer = false;
  bool _allowVoicemail = false;
  bool _allowTakeMessage = false;
  bool _allowSms = false;
  bool _allowWebSearch = false;
  String _chatModel = '';
  int? _smsFrom;
  bool _hasSecret = false;
  Set<int> _toolIds = {};
  Set<int> _collectionIds = {};

  bool _loading = false;
  bool _saving = false;
  bool _testing = false;
  NexusAgentTestResult? _testResult;

  @override
  void initState() {
    super.initState();
    if (widget.agentId != null) _load();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _prompt, _greeting, _ttsVoice, _maxTurns, _notifySms,
      _webhookUrl, _webhookSecret, _test
    ]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = ref.read(nexusAgentsClientProvider);
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final a = await client.getAgent(widget.agentId!);
      _name.text = a.name;
      _prompt.text = a.systemPrompt;
      _greeting.text = a.greeting;
      _ttsVoice.text = a.ttsVoice;
      _maxTurns.text = '${a.maxTurns}';
      _notifySms.text = a.notifySmsNumber;
      _webhookUrl.text = a.webhookUrl;
      _enabled = a.enabled;
      _allowThinking = a.allowThinking;
      _allowTransfer = a.allowTransfer;
      _allowScreenedTransfer = a.allowScreenedTransfer;
      _allowVoicemail = a.allowVoicemail;
      _allowTakeMessage = a.allowTakeMessage;
      _allowSms = a.allowSms;
      _allowWebSearch = a.allowWebSearch;
      _chatModel = a.chatModelName;
      _smsFrom = a.smsFromPhoneNumberId;
      _hasSecret = a.hasWebhookSecret;
      _toolIds = a.selectedToolIds.toSet();
      _collectionIds = a.knowledgeCollectionIds.toSet();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  NexusAgent _collect() => NexusAgent(
        id: widget.agentId ?? 0,
        name: _name.text.trim(),
        enabled: _enabled,
        systemPrompt: _prompt.text,
        greeting: _greeting.text,
        chatModelName: _chatModel,
        allowThinking: _allowThinking,
        ttsVoice: _ttsVoice.text.trim(),
        maxTurns: int.tryParse(_maxTurns.text.trim()) ?? 8,
        allowTransfer: _allowTransfer,
        allowScreenedTransfer: _allowScreenedTransfer,
        allowVoicemail: _allowVoicemail,
        allowTakeMessage: _allowTakeMessage,
        allowSms: _allowSms,
        allowWebSearch: _allowWebSearch,
        notifySmsNumber: _notifySms.text.trim(),
        webhookUrl: _webhookUrl.text.trim(),
        smsFromPhoneNumberId: _smsFrom,
        selectedToolIds: _toolIds.toList(),
      );

  Future<void> _save() async {
    final client = ref.read(nexusAgentsClientProvider);
    if (client == null || _saving) return;
    setState(() => _saving = true);
    try {
      await client.saveAgent(_collect(),
          webhookSecret: _webhookSecret.text,
          collectionIds: _collectionIds.toList());
      ref.invalidate(agentsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast('Save failed: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final client = ref.read(nexusAgentsClientProvider);
    if (client == null || widget.agentId == null) return;
    final name = _name.text.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete agent?'),
        content: Text(
            'Delete ${name.isEmpty ? 'this agent' : '"$name"'}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete',
                  style: TextStyle(color: ctx.nexus.danger))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await client.deleteAgent(widget.agentId!);
      ref.invalidate(agentsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _runTest() async {
    final client = ref.read(nexusAgentsClientProvider);
    final text = _test.text.trim();
    if (client == null || widget.agentId == null || text.isEmpty || _testing) {
      return;
    }
    setState(() => _testing = true);
    try {
      final res = await client
          .testChat(widget.agentId!, [(role: 'user', content: text)]);
      setState(() => _testResult = res);
    } catch (e) {
      _toast('Test failed: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    final optionsAsync = ref.watch(agentOptionsProvider);
    final options = optionsAsync.valueOrNull ?? const NexusAgentOptions();
    final tools = ref.watch(httpToolsProvider).valueOrNull ?? const [];

    return NexusPage(
      title: widget.agentId == null ? 'New agent' : 'Edit agent',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Scrollbar(
              controller: _scroll,
              child: ListView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
                children: [
                  NexusField(label: 'Name', controller: _name, hint: 'Ava'),
                  NexusField(
                      label: 'System prompt',
                      controller: _prompt,
                      hint: 'You are a helpful receptionist for…',
                      lines: 5),
                  NexusField(
                      label: 'Greeting',
                      controller: _greeting,
                      hint: 'Thanks for calling…',
                      lines: 2),
                  _modelPicker(context, optionsAsync),
                  Row(children: [
                    Expanded(
                        child: NexusField(
                            label: 'TTS voice',
                            controller: _ttsVoice,
                            hint: 'af_heart')),
                    const SizedBox(width: 10),
                    SizedBox(
                        width: 110,
                        child: NexusField(
                            label: 'Max turns',
                            controller: _maxTurns,
                            keyboard: TextInputType.number)),
                  ]),
                  const NexusSectionLabel('Capabilities'),
                  const SizedBox(height: 6),
                  _cap('Thinking', _allowThinking, (v) => _allowThinking = v),
                  _cap('Transfer calls', _allowTransfer,
                      (v) => _allowTransfer = v),
                  _cap('Screened transfer', _allowScreenedTransfer,
                      (v) => _allowScreenedTransfer = v),
                  _cap('Voicemail', _allowVoicemail, (v) => _allowVoicemail = v),
                  _cap('Take a message', _allowTakeMessage,
                      (v) => _allowTakeMessage = v),
                  _cap('Send SMS', _allowSms, (v) => _allowSms = v),
                  _cap('Web search', _allowWebSearch,
                      (v) => _allowWebSearch = v),
                  const SizedBox(height: 14),
                  if (tools.isNotEmpty) ...[
                    const NexusSectionLabel('HTTP tools'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 7, runSpacing: 7, children: [
                      for (final tool in tools)
                        _chip(context, tool.name, _toolIds.contains(tool.id),
                            () => setState(() => _toolIds.contains(tool.id)
                                ? _toolIds.remove(tool.id)
                                : _toolIds.add(tool.id))),
                    ]),
                    const SizedBox(height: 14),
                  ],
                  if (options.collections.isNotEmpty) ...[
                    const NexusSectionLabel('Knowledge collections'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 7, runSpacing: 7, children: [
                      for (final c in options.collections)
                        _chip(context, '${c.name} (${c.documentCount})',
                            _collectionIds.contains(c.id),
                            () => setState(() => _collectionIds.contains(c.id)
                                ? _collectionIds.remove(c.id)
                                : _collectionIds.add(c.id))),
                    ]),
                    const SizedBox(height: 14),
                  ],
                  const NexusSectionLabel('SMS & webhook'),
                  const SizedBox(height: 10),
                  _smsFromPicker(context, options),
                  NexusField(
                      label: 'Notify SMS number',
                      controller: _notifySms,
                      hint: '+1 415 555 0148'),
                  NexusField(
                      label: 'Webhook URL',
                      controller: _webhookUrl,
                      hint: 'https://…'),
                  NexusField(
                      label: _hasSecret
                          ? 'Webhook secret (set — blank keeps it)'
                          : 'Webhook secret',
                      controller: _webhookSecret,
                      hint: '••••'),
                  NexusToggleTile(
                      label: 'Enabled',
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v)),
                  const SizedBox(height: 16),
                  NexusButton(label: 'Save agent', busy: _saving, onTap: _save),
                  if (widget.agentId != null) ...[
                    const SizedBox(height: 18),
                    _testChat(context),
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: GestureDetector(
                        onTap: _delete,
                        child: Center(
                            child: Text('Delete agent',
                                style: TextStyle(
                                    color: t.danger,
                                    fontWeight: FontWeight.w600))),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _cap(String label, bool value, ValueChanged<bool> set) =>
      NexusToggleTile(
          label: label, value: value, onChanged: (v) => setState(() => set(v)));

  Widget _modelPicker(
      BuildContext context, AsyncValue<NexusAgentOptions> optionsAsync) {
    final t = context.nexus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('CHAT MODEL',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: t.faint)),
          ),
          // Surface loading/error instead of an empty dropdown.
          optionsAsync.when(
            loading: () => _pickerShell(
              context,
              Row(children: [
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text('Loading models…',
                    style: TextStyle(color: t.muted, fontSize: 13)),
              ]),
            ),
            error: (e, _) => _pickerShell(
              context,
              Row(children: [
                Expanded(
                  child: Text('Couldn’t load models',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.danger, fontSize: 13)),
                ),
                GestureDetector(
                  onTap: () => ref.invalidate(agentOptionsProvider),
                  child: Text('Retry',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: t.accent2)),
                ),
              ]),
            ),
            data: (o) {
              final models = o.chatModels;
              final value = models.contains(_chatModel) ? _chatModel : null;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                    color: t.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.line2)),
                child: DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  dropdownColor: t.bg2,
                  underline: const SizedBox.shrink(),
                  hint: Text(
                      _chatModel.isEmpty
                          ? (models.isEmpty
                              ? 'No models available'
                              : 'Select a model')
                          : _chatModel,
                      style: TextStyle(color: t.muted, fontSize: 13)),
                  items: [
                    for (final m in models)
                      DropdownMenuItem(
                          value: m,
                          child: Text(m,
                              style: nexusMono(fontSize: 13, color: t.text)))
                  ],
                  onChanged: (v) => setState(() => _chatModel = v ?? ''),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _pickerShell(BuildContext context, Widget child) {
    final t = context.nexus;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
          color: t.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.line2)),
      child: child,
    );
  }

  Widget _smsFromPicker(BuildContext context, NexusAgentOptions o) {
    final t = context.nexus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('SEND SMS FROM',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: t.faint)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
                color: t.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.line2)),
            child: DropdownButton<int?>(
              value: o.smsNumbers.any((n) => n.id == _smsFrom) ? _smsFrom : null,
              isExpanded: true,
              dropdownColor: t.bg2,
              underline: const SizedBox.shrink(),
              hint: Text('None',
                  style: TextStyle(color: t.muted, fontSize: 13)),
              items: [
                DropdownMenuItem(
                    value: null,
                    child: Text('None',
                        style: TextStyle(color: t.muted, fontSize: 13))),
                for (final n in o.smsNumbers)
                  DropdownMenuItem(
                      value: n.id,
                      child: Text(n.number,
                          style: nexusMono(fontSize: 13, color: t.text)))
              ],
              onChanged: (v) => setState(() => _smsFrom = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(
      BuildContext context, String label, bool on, VoidCallback onTap) {
    final t = context.nexus;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? t.accent : t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? t.accent : t.line2),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: on ? Colors.white : t.muted)),
      ),
    );
  }

  Widget _testChat(BuildContext context) {
    final t = context.nexus;
    final res = _testResult;
    return NexusCard(
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.science_outlined, size: 16, color: t.accent2),
            const SizedBox(width: 8),
            Text('Test chat',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.text)),
            const Spacer(),
            Text('actions not executed',
                style: TextStyle(fontSize: 10, color: t.faint)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _test,
                onSubmitted: (_) => _runTest(),
                style: TextStyle(fontSize: 13.5, color: t.text),
                decoration: nexusInput(context, 'Say something to the agent…'),
              ),
            ),
            const SizedBox(width: 9),
            GestureDetector(
              onTap: _runTest,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: t.accent, borderRadius: BorderRadius.circular(12)),
                child: _testing
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, size: 17, color: Colors.white),
              ),
            ),
          ]),
          if (res != null) ...[
            const SizedBox(height: 12),
            if (res.error != null)
              Text(res.error!, style: TextStyle(color: t.danger, fontSize: 13))
            else ...[
              for (final r in res.replies)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                        color: t.surface2,
                        borderRadius: BorderRadius.circular(11)),
                    child: Text(r,
                        style: TextStyle(
                            fontSize: 13.5, height: 1.4, color: t.text)),
                  ),
                ),
              if (res.actions.isNotEmpty)
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final a in res.actions)
                    NexusPill(a.tool, color: t.accent2, outlined: true),
                ]),
              if (res.pages.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Knowledge used: ${res.pages.join(', ')}',
                      style: TextStyle(fontSize: 11, color: t.muted)),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
