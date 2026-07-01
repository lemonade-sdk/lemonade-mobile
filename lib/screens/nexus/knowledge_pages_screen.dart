import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/nexus/nexus_agents_models.dart';
import '../../providers/agents_providers.dart';
import '../../providers/nexus_gateway_provider.dart';
import '../../themes/nexus_tokens.dart';
import '../../widgets/nexus/nexus_form.dart';
import '../../widgets/nexus/nexus_ui.dart';

/// Hand-authored reference text the agent ranks/injects per turn
/// (`/voice/agent-knowledge`).
class KnowledgePagesScreen extends ConsumerWidget {
  const KnowledgePagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final pages = ref.watch(knowledgePagesProvider);
    return NexusPage(
      title: 'Agent knowledge',
      actions: [
        IconButton(
          icon: Icon(Icons.add, color: t.accent),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const KnowledgePageEditor(pageId: null))),
        ),
      ],
      body: pages.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('$e', style: TextStyle(color: t.danger))),
        data: (list) => list.isEmpty
            ? Center(
                child: Text('No knowledge pages yet — tap + to add one.',
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

  Widget _row(BuildContext context, NexusKnowledgePageSummary p) {
    final t = context.nexus;
    return NexusCard(
      radius: 14,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => KnowledgePageEditor(pageId: p.id))),
      child: Row(children: [
        Icon(Icons.menu_book_outlined, size: 18, color: t.accent2),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: t.text)),
              Text(
                  '${p.contentChars} chars · ${p.agentProfileIds.length} agents${p.keywords.isEmpty ? '' : ' · ${p.keywords}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: t.muted)),
            ],
          ),
        ),
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
                color: p.enabled ? t.good : t.faint, shape: BoxShape.circle)),
      ]),
    );
  }
}

class KnowledgePageEditor extends ConsumerStatefulWidget {
  final int? pageId;
  const KnowledgePageEditor({super.key, required this.pageId});

  @override
  ConsumerState<KnowledgePageEditor> createState() =>
      _KnowledgePageEditorState();
}

class _KnowledgePageEditorState extends ConsumerState<KnowledgePageEditor> {
  final _title = TextEditingController();
  final _keywords = TextEditingController();
  final _content = TextEditingController();
  final _scroll = ScrollController();
  bool _enabled = true;
  Set<int> _agentIds = {};
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.pageId != null) _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _keywords.dispose();
    _content.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = ref.read(nexusAgentsClientProvider);
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final p = await client.getPage(widget.pageId!);
      _title.text = p.title;
      _keywords.text = p.keywords;
      _content.text = p.content;
      _enabled = p.enabled;
      _agentIds = p.agentProfileIds.toSet();
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
      await client.savePage(NexusKnowledgePage(
        id: widget.pageId ?? 0,
        title: _title.text.trim(),
        keywords: _keywords.text.trim(),
        content: _content.text,
        enabled: _enabled,
        agentProfileIds: _agentIds.toList(),
      ));
      ref.invalidate(knowledgePagesProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast('Save failed: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final client = ref.read(nexusAgentsClientProvider);
    if (client == null || widget.pageId == null) return;
    final title = _title.text.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete page?'),
        content: Text(
            'Delete ${title.isEmpty ? 'this page' : '"$title"'}? This cannot be undone.'),
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
      await client.deletePage(widget.pageId!);
      ref.invalidate(knowledgePagesProvider);
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
    final agents = ref.watch(agentsProvider).valueOrNull ?? const [];
    return NexusPage(
      title: widget.pageId == null ? 'New page' : 'Edit page',
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
                      label: 'Title', controller: _title, hint: 'Refund policy'),
                  NexusField(
                      label: 'Keywords',
                      controller: _keywords,
                      hint: 'refund, return, money back'),
                  NexusField(
                      label: 'Content',
                      controller: _content,
                      hint: 'Reference text the agent injects per turn…',
                      lines: 8),
                  if (agents.isNotEmpty) ...[
                    const NexusSectionLabel('Linked agents'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final a in agents)
                          _agentChip(context, a),
                      ],
                    ),
                    const SizedBox(height: 13),
                  ],
                  NexusToggleTile(
                      label: 'Enabled',
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v)),
                  const SizedBox(height: 16),
                  NexusButton(label: 'Save page', busy: _saving, onTap: _save),
                  if (widget.pageId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: GestureDetector(
                        onTap: _delete,
                        child: Center(
                            child: Text('Delete page',
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

  Widget _agentChip(BuildContext context, NexusAgentSummary a) {
    final t = context.nexus;
    final on = _agentIds.contains(a.id);
    return GestureDetector(
      onTap: () => setState(() {
        if (on) {
          _agentIds.remove(a.id);
        } else {
          _agentIds.add(a.id);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? t.accent : t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? t.accent : t.line2),
        ),
        child: Text(a.name,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: on ? Colors.white : t.muted)),
      ),
    );
  }
}
