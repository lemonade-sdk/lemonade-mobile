import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/nexus/nexus_agents_models.dart';
import '../../providers/agents_providers.dart';
import '../../providers/nexus_gateway_provider.dart';
import '../../themes/nexus_tokens.dart';
import '../../widgets/nexus/nexus_form.dart';
import '../../widgets/nexus/nexus_ui.dart';

/// Custom webhooks an agent can call (`/voice/http-tools`).
class HttpToolsScreen extends ConsumerWidget {
  const HttpToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final tools = ref.watch(httpToolsProvider);
    return NexusPage(
      title: 'HTTP tools',
      actions: [
        IconButton(
          icon: Icon(Icons.add, color: t.accent),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const HttpToolEditor(toolId: null))),
        ),
      ],
      body: tools.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('$e', style: TextStyle(color: t.danger))),
        data: (list) => list.isEmpty
            ? Center(
                child: Text('No HTTP tools yet — tap + to add one.',
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

  Widget _row(BuildContext context, NexusHttpToolSummary tool) {
    final t = context.nexus;
    return NexusCard(
      radius: 14,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => HttpToolEditor(toolId: tool.id))),
      child: Row(children: [
        NexusPill(tool.method, color: t.accent2, outlined: true),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tool.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: t.text)),
              Text(tool.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nexusMono(fontSize: 11, color: t.muted)),
            ],
          ),
        ),
        if (tool.profilesUsing > 0)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('${tool.profilesUsing} agents',
                style: TextStyle(fontSize: 10.5, color: t.faint)),
          ),
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
                color: tool.enabled ? t.good : t.faint,
                shape: BoxShape.circle)),
      ]),
    );
  }
}

class HttpToolEditor extends ConsumerStatefulWidget {
  final int? toolId;
  const HttpToolEditor({super.key, required this.toolId});

  @override
  ConsumerState<HttpToolEditor> createState() => _HttpToolEditorState();
}

class _HttpToolEditorState extends ConsumerState<HttpToolEditor> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _url = TextEditingController();
  final _timeout = TextEditingController(text: '10');
  final _params = TextEditingController();
  String _method = 'GET';
  bool _enabled = true;
  final List<({TextEditingController name, TextEditingController value, bool hadValue})>
      _headers = [];
  final _scroll = ScrollController();
  bool _loading = false;
  bool _saving = false;

  static const _methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

  @override
  void initState() {
    super.initState();
    if (widget.toolId != null) _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _url.dispose();
    _timeout.dispose();
    _params.dispose();
    for (final h in _headers) {
      h.name.dispose();
      h.value.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = ref.read(nexusAgentsClientProvider);
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final tool = await client.getTool(widget.toolId!);
      _name.text = tool.name;
      _desc.text = tool.description;
      _url.text = tool.url;
      _timeout.text = '${tool.timeoutSeconds}';
      _params.text = tool.parametersJson;
      _method = tool.method;
      _enabled = tool.enabled;
      for (final h in tool.headers) {
        _headers.add((
          name: TextEditingController(text: h.name),
          value: TextEditingController(),
          hadValue: h.hasHeaderValue,
        ));
      }
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final client = ref.read(nexusAgentsClientProvider);
    if (client == null || _saving) return;
    setState(() => _saving = true);
    try {
      await client.saveTool(
        NexusHttpTool(
          id: widget.toolId ?? 0,
          name: _name.text.trim(),
          description: _desc.text.trim(),
          url: _url.text.trim(),
          method: _method,
          timeoutSeconds: int.tryParse(_timeout.text.trim()) ?? 10,
          enabled: _enabled,
          parametersJson: _params.text.trim(),
        ),
        headerNames: [for (final h in _headers) h.name.text.trim()],
        headerValues: [for (final h in _headers) h.value.text],
      );
      ref.invalidate(httpToolsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast('Save failed: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final client = ref.read(nexusAgentsClientProvider);
    if (client == null || widget.toolId == null) return;
    final name = _name.text.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete tool?'),
        content: Text(
            'Delete ${name.isEmpty ? 'this tool' : '"$name"'}? Agents using it lose it. This cannot be undone.'),
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
      await client.deleteTool(widget.toolId!);
      ref.invalidate(httpToolsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast('$e');
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
    return NexusPage(
      title: widget.toolId == null ? 'New tool' : 'Edit tool',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Scrollbar(
              controller: _scroll,
              child: ListView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
                children: [
                  NexusField(
                      label: 'Name', controller: _name, hint: 'lookup_order'),
                  NexusField(
                      label: 'Description',
                      controller: _desc,
                      hint: 'What the agent uses it for',
                      lines: 2),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 13),
                    child: Row(children: [
                      SizedBox(
                        width: 110,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11),
                          decoration: BoxDecoration(
                              color: t.bg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: t.line2)),
                          child: DropdownButton<String>(
                            value: _method,
                            isExpanded: true,
                            dropdownColor: t.bg2,
                            underline: const SizedBox.shrink(),
                            items: [
                              for (final m in _methods)
                                DropdownMenuItem(
                                    value: m,
                                    child: Text(m,
                                        style: nexusMono(
                                            fontSize: 13, color: t.text)))
                            ],
                            onChanged: (v) =>
                                setState(() => _method = v ?? 'GET'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: TextField(
                          controller: _url,
                          style: nexusMono(fontSize: 13, color: t.text),
                          decoration:
                              nexusInput(context, 'https://api.example.com/…'),
                        ),
                      ),
                    ]),
                  ),
                  NexusField(
                      label: 'Timeout (seconds)',
                      controller: _timeout,
                      keyboard: TextInputType.number),
                  NexusField(
                      label: 'Parameters (JSON schema)',
                      controller: _params,
                      hint: '{ "type":"object", "properties": {…} }',
                      lines: 4),
                  _headersSection(context),
                  const SizedBox(height: 6),
                  NexusToggleTile(
                      label: 'Enabled',
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v)),
                  const SizedBox(height: 16),
                  NexusButton(label: 'Save tool', busy: _saving, onTap: _save),
                  if (widget.toolId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: GestureDetector(
                        onTap: _delete,
                        child: Center(
                            child: Text('Delete tool',
                                style: TextStyle(
                                    color: t.danger,
                                    fontWeight: FontWeight.w600))),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _headersSection(BuildContext context) {
    final t = context.nexus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NexusSectionLabel('Headers'),
        const SizedBox(height: 8),
        for (var i = 0; i < _headers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _headers[i].name,
                  style: TextStyle(fontSize: 13, color: t.text),
                  decoration: nexusInput(context, 'Header-Name'),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: TextField(
                  controller: _headers[i].value,
                  obscureText: _headers[i].hadValue,
                  style: TextStyle(fontSize: 13, color: t.text),
                  decoration: nexusInput(context,
                      _headers[i].hadValue ? '•••• (kept)' : 'value'),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 16, color: t.danger),
                onPressed: () => setState(() => _headers.removeAt(i)),
              ),
            ]),
          ),
        GestureDetector(
          onTap: () => setState(() => _headers.add((
                name: TextEditingController(),
                value: TextEditingController(),
                hadValue: false
              ))),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: t.line2)),
            child: Text('+ Add header',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: t.accent2)),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
